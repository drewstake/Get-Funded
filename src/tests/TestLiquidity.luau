-- Test fixtures only. Production modules never require this file.
-- Legacy account/profile tests now post actual counterpart orders instead of relying on house fills.
local F=require(script.Parent.FundedAccounts)
local T={}
function T.Offer(e,key,side,qty,price)
 local id="fixture:liquidity:"..key..":"..side
 e:AddAccount(id,1e12-1,1000000,.99,false)
 local ok,result=e:Submit(id,{Contract=key,Direction=side,Quantity=qty,Type="Limit",Price=price})
 assert(ok,tostring(result));return result
end
function T.Ensure(e,id,r)
 local a=e.Accounts[id];local b=e.Books[r.Contract]
 if not a or not a.Player or not b or r.Type~="Market"or type(r.Quantity)~="number"or r.Quantity<1 or r.Quantity%1~=0 then return end
 if not r.ReduceOnly and (a.Locked or e:OrderCapacity(a,r.Contract,r.Direction)<r.Quantity)then return end
 local levels=r.Direction==1 and b.Asks or b.Bids;local qty=0;local ticks=b.Last or b.Reference
 for _,l in ipairs(levels)do for _,o in ipairs(l.Orders)do
  local other=e.Accounts[o.Owner]
  local same=o.Owner==id or a.Group and a.Group==other.Group or a.ProfileId and a.ProfileId==other.ProfileId
  local available=not same and e:_available(o,true)or 0
  if available>0 then qty+=available;ticks=l.Price end
 end end
 if qty<r.Quantity then T.Offer(e,r.Contract,-r.Direction,r.Quantity-qty,ticks*b.Spec.Tick)end
end
function T.Submit(e,id,r,...)
 T.Ensure(e,id,r);return e:Submit(id,r,...)
end
function T.Perform(e,id,r)
 local p=e.Accounts[id]and e.Accounts[id].Positions[r.Contract]
 if r.Action=="Close"and p then T.Ensure(e,id,{Contract=r.Contract,Direction=-p.Direction,Quantity=p.Quantity,Type="Market",ReduceOnly=true})
 elseif r.Action=="Place"then T.Ensure(e,id,r)end
 return F.Perform(e,id,r)
end
-- Explicit settlement fixture for accounting/progression tests. Start a new
-- execution window and supply enough real bot depth for the configured fraction.
-- The optional mark seeds a scenario price; it does not claim to simulate price
-- discovery. Use PrintPrice below when testing triggers or intervening trades.
-- Offer/Submit/Perform above deliberately retain their exact/thin-book behavior.
function T.Clear(e)
 for _,id in ipairs(e.AccountOrder)do if id:sub(1,8)=="fixture:"then e:CancelAll(id)end end
end
function T.Ready(e,key,side,qty,price)
 assert(qty>0,"Ready requires positive quantity")
 T.Clear(e)
 e:AdvanceClock(e.Config.PlayerExecution and e.Config.PlayerExecution.WindowSeconds or e.Config.StepSeconds)
 local b=e.Books[key]
 if price then b.Last=math.round(price/b.Spec.Tick)end
 local quantity=math.ceil(qty/(e.Config.PlayerExecution and e.Config.PlayerExecution.BookFraction or 1))
 T.Offer(e,key,-side,quantity,(b.Last or b.Reference)*b.Spec.Tick)
end
function T.FillAt(e,id,r,price)
 assert(r.Type=="Market"and r.Quantity>0,"FillAt requires a positive market request")
 T.Ready(e,r.Contract,r.Direction,r.Quantity,price)
 local ok,result=e:Submit(id,r)
 assert(ok and result.Filled==r.Quantity,"Settlement fixture did not fully execute: "..tostring(ok and result.Status or result))
 T.Clear(e)
 return result
end
-- Exercise the player ticket path, including dollar-to-tick conversion, when a
-- test asserts ticket-created protections rather than a raw engine submission.
function T.PlaceAt(e,id,r,price)
 assert(r.Action=="Place"and r.Type=="Market"and r.Quantity>0,"PlaceAt requires a positive market ticket")
 T.Ready(e,r.Contract,r.Direction,r.Quantity,price)
 local ok,result=F.Perform(e,id,r)
 assert(ok and result.Filled==r.Quantity,"Ticket fixture did not fully execute: "..tostring(ok and result.Status or result))
 T.Clear(e)
 return result
end
-- Walk actual executions through the current price collar. Never mutate Last or
-- FairReference to bypass the protection/depletion path being tested.
function T.PrintPrice(e,key,price)
 T.Clear(e)
 local b=e.Books[key];local target=math.round(price/b.Spec.Tick)
 assert(math.abs(target*b.Spec.Tick-price)<1e-6,"Print price must be on tick")
 local id="fixture:print:"..key;e:AddAccount(id,1e12-1,1000000,.99,false)
 local steps=0
 while (b.Last or b.Reference)~=target do
  steps+=1;assert(steps<10000,"Print fixture could not reach price")
  local last=b.Last or b.Reference
  local side=target>last and 1 or -1
  local guard=e.Config.PlayerExecution and e.Config.PlayerExecution.GuardTicks*math.max(1,b.Spec.Scale or 1)or math.abs(target-last)
  local nextPrice=last+side*math.min(math.abs(target-last),guard)
  T.Offer(e,key,-side,1,nextPrice*b.Spec.Tick)
  local ok,result=e:Submit(id,{Contract=key,Direction=side,Quantity=1,Type="Market"})
  assert(ok and result.Filled==1,"Print fixture did not execute")
 end
 T.Clear(e)
end
return T
