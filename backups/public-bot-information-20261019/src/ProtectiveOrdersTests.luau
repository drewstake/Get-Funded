local E=require(script.Parent.MarketEngine)
local C=table.clone(require(game.ReplicatedStorage.MarketReign.MarketConfig))
C.BotPopulation=nil -- This fixture intentionally has no autonomous population.
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Policy=require(script.Parent.PlayerExecution)
local F=require(script.Parent.FundedAccounts)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function order(e,id,side,qty,price,extra)
 local r={Contract="BX",Direction=side,Quantity=qty,Type=price and "Limit"or "Market",Price=price}
 for k,v in pairs(extra or {})do r[k]=v end
 local ok,result=e:Submit(id,r);assert(ok,tostring(result));return result
end
local function fresh(side,qty,entry,targetTicks)
 local c=clone(C);local e=E.new(c,731)
 for _,id in ipairs({"maker","other"})do e:AddAccount(id,1e9,10000,.9,false)end
 local a=e:AddAccount("user",1e9,1000000,.9,true)
 order(e,"maker",-side,qty,entry)
 assert(order(e,a.Id,side,qty,nil,{StopTicks=4,TargetTicks=targetTicks or 4}).Filled==qty)
 return e,a,a.Positions.BX,c
end
local function capture(e)
 return CP.Capture(e,setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(731),Agents={}},P))
end
local function same(a,b)
 assert(type(a)==type(b),"Different types")
 if type(a)~="table"then assert(a==b,"Different values: "..tostring(a).." / "..tostring(b));return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Extra key: "..tostring(k))end
end
function Tests.Run()
 local results={};local function test(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
 test("Reset with a working or partially filled target permits subsequent market updates and protection",function()
  for _,side in ipairs({-1,1})do for _,partial in ipairs({false,true})do
   local e=E.new(C,731);local f=F.new(e,L,C);f:Join("101")
   for _,id in ipairs({"maker","other"})do e:AddAccount(id,1e9,10000,.9,false)end
   local a=e.Accounts[f:Owner("101")]
   order(e,"maker",-side,3,5825)
   order(e,a.Id,side,3,nil,{StopTicks=8,TargetTicks=4})
   local p=a.Positions.BX;local target=p.TargetOrder
   if partial then order(e,"maker",side,1,p.Target)end
   local remaining=p.Quantity;local volume=e.TotalVolume
   local used=Policy.State(e).Owners["101:"..side]
   order(e,"maker",side,remaining,5825)
   assert(f:ResetAccount("101",a.Id))
   assert(not e.Accounts[a.Id]and not e.Orders[target])
   assert(e.TotalVolume==volume+remaining,"Reset did not trade its remaining exposure")
   assert(not e.Accounts["house:reset-exposure"],"Reset parked exposure off-market")
   assert(Policy.State(e).Owners["101:"..side]==used,"Reset replenished the entry allowance")
   e:ProcessStops();e:AdvanceClock(.25);e:ProcessPlayerOrders();e:Audit()
   local nextA=e.Accounts[f:Owner("101")]
   order(e,"maker",-side,1,5825)
   order(e,nextA.Id,side,1,nil,{StopTicks=8,TargetTicks=4})
   local nextP=nextA.Positions.BX;assert(nextP and e.Orders[nextP.TargetOrder],"Protection stopped syncing after reset")
   order(e,"other",side,1,nextP.Target)
   assert(not nextA.Positions.BX);e:Audit()
  end end
 end)
 for _,side in ipairs({-1,1})do
  test(side..": 307-contract target fills in thin liquidity with exhausted entry allowance",function()
   local e,a,p,c=fresh(side,307,5939.75,107);local target=p.Target;local stop=p.Stop
   local child=e.Orders[p.TargetOrder];assert(child and child.Remaining==307 and not child.Queued and not p.Triggered)
   local state=Policy.State(e);state.Markets["BX:"..(-side)]={Used=0,Limit=0};state.Owners["user:"..(-side)]=c.PlayerExecution.OwnerContracts
   e.Books.BX.FairReference=target/.25
   local before=e.TotalVolume
   order(e,"maker",side,9,target)
   assert(p.Quantity==298 and p.TargetFilled==9 and p.Stop==stop and p.Triggered=="Take profit")
   assert(e.TotalVolume==before+9 and e.Books.BX.Last*.25==target)
   order(e,"other",side,298,target+side*.25)
   assert(not a.Positions.BX and not e.Orders[child.Id],"Target was skipped or exposure reversed")
   assert(a.History[1].Reason=="Take profit"and a.History[1].Exit==target)
   assert(state.Markets["BX:"..(-side)].Used==0,"Protection consumed entry allowance")
   e:Audit();return {Contracts=307,Target=target,FirstFill=9,FinalPosition=0}
  end)
  test(side..": partial TP keeps stop and stop closes only the residual",function()
   local e,a,p=fresh(side,3,5825);local stop,target=p.Stop,p.Target;local tp=p.TargetOrder
   order(e,"maker",side,1,target);e:ProcessStops()
   assert(p.Quantity==2 and p.Stop==stop and e.Orders[tp].Remaining==2)
   local snap=e:Snapshot(a.Id,"BX","1m",true);assert(#snap.Orders==2)
   local found=false;for _,o in ipairs(snap.Orders)do if o.Protection=="Target"then
    assert(o.Filled==1 and o.Quantity==2 and o.Closing and o.Status:find("1 filled",1,true));found=true
   end end;assert(found)
   order(e,"maker",side,3,stop);order(e,"other",-side,1);e:ProcessStops();e:ProcessPlayerOrders()
   assert(not a.Positions.BX and not e.Orders[tp]and not next(a.OpenOrders))
   assert(a.History[1].Reason=="Stop loss"and a.History[1].Quantity==2)
   e:Audit()
  end)
  test(side..": saved working/partial targets retain FIFO and residual stop",function()
   local e,a,p,c=fresh(side,5,5825);order(e,"maker",side,2,p.Target);e:ProcessStops()
   local before=capture(e);local restored=CP.Restore(CP.Decode(CP.Encode(before)),c)
   same(before.Engine, capture(restored).Engine)
   local saved=restored.Accounts.user.Positions.BX
   assert(saved.Stop==p.Stop and saved.TargetFilled==2 and restored.Orders[saved.TargetOrder].Priority==e.Orders[p.TargetOrder].Priority)
   order(restored,"maker",side,3,saved.Target);assert(not restored.Accounts.user.Positions.BX);restored:Audit()
  end)
 end
 test("Resting TP observes FIFO and a later ordinary order cannot trade through it",function()
  local e,a,p=fresh(-1,3,5825);local target=p.Target
  local later=order(e,"other",1,2,target)
  order(e,"maker",-1,4,target-.25)
  assert(not a.Positions.BX and e.Orders[later.Id].Remaining==1)
  assert(e.Trades[#e.Trades-1].Buyer==a.Id and e.Trades[#e.Trades].Buyer=="other");e:Audit()
 end)
 test("Target resizing preserves prices, reduces quantity, and removes orphan orders on reversal",function()
  local e,a,p=fresh(1,3,5825);local target,stop=p.Target,p.Stop;local old=e.Orders[p.TargetOrder]
  order(e,"maker",-1,2,5825);order(e,a.Id,1,2)
  assert(p.Quantity==5 and p.Target==target and p.Stop==stop and e.Orders[p.TargetOrder].Remaining==5)
  assert(not e.Orders[old.Id],"Adding size retained old FIFO priority")
  local resized=e.Orders[p.TargetOrder];local priority=resized.Priority
  order(e,"maker",1,1,5825);order(e,a.Id,-1,1,nil,{ReduceOnly=true})
  assert(p.Quantity==4 and e.Orders[p.TargetOrder]==resized and resized.Remaining==4 and resized.Priority==priority)
  order(e,"maker",1,5,5825);order(e,a.Id,-1,5,nil,{StopTicks=8,TargetTicks=12})
  local reversed=a.Positions.BX;assert(reversed.Id~=p.Id and reversed.Quantity==1 and reversed.Direction==-1)
  assert(not e.Orders[resized.Id]and e.Orders[reversed.TargetOrder].ProtectivePosition==reversed.Id);e:Audit()
 end)
 test("Moving/cancelling a TP updates the book without printing a trade",function()
  local e,a,p=fresh(1,3,5825);local old=p.TargetOrder;local price=p.Target;local volume=e.TotalVolume
  assert(e:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=price+.25,ExpectedPrice=price}))
  assert(not e.Orders[old]and e.Orders[p.TargetOrder].Price==(price+.25)/.25 and e.TotalVolume==volume)
  assert(not e:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=price+.5,ExpectedPrice=price}))
  assert(not e:AmendOrder(a.Id,{Contract="BX",OrderId=p.TargetOrder,Price=price,ExpectedPrice=price+.25,ExpectedQuantity=3}))
  assert(not F.Perform(e,a.Id,{Action="Cancel",OrderId=p.TargetOrder}),"Raw child-id cancellation bypassed protection controls")
  local target=p.TargetOrder;assert(e:CancelProtection(a.Id,p.Id,"Target"));assert(not p.Target and not e.Orders[target]and p.Stop)
  e:ProcessStops();assert(not p.TargetOrder);e:Audit()
 end)
 test("Legacy queued TP migrates without fills then ignores exhausted entry budget",function()
  local e,a,p,c=fresh(-1,307,5939.75,107);local target=p.Target
  local state=Policy.State(e);state.Markets["BX:1"]={Used=0,Limit=0}
  local child=e.Orders[p.TargetOrder];e:_unrest(e.Books.BX,child);child.Queued=true;child.Protection=nil;child.ProtectivePosition=nil
  p.Triggered="Take profit";p.ExitOrder=child.Id;p.TargetOrder=nil
  e.Books.BX.FairReference=target/.25;order(e,"maker",-1,9,target-.25)
  local saved=capture(e);saved.Version=12
  local restored=CP.Restore(saved,c);local migrated=restored.Accounts.user.Positions.BX
  assert(restored.TotalVolume==e.TotalVolume and migrated.Quantity==307 and migrated.TargetOrder==child.Id)
  restored:ProcessPlayerOrders();assert(migrated.Quantity==298 and migrated.TargetFilled==9)
  assert(restored.Accounts.user.History[1].Exit==target-.25);restored:Audit()
 end)
 test("Fake protective fields and voluntary reduce-only orders cannot bypass entry budgets",function()
  local e,a,p,c=fresh(-1,3,5825);local state=Policy.State(e)
  state.Owners["user:1"]=c.PlayerExecution.OwnerContracts
  order(e,"maker",-1,3,5825)
  local r=order(e,a.Id,1,3,nil,{ReduceOnly=true,Execution="Immediate",Protection="Take profit",ProtectivePosition=p.Id})
  assert(r.Filled==0 and p.Quantity==3);assert(not next(a.History));e:Audit()
 end)
 test("Protective exits retain actual-price safeguards and report the reason",function()
  local e,a,p=fresh(-1,3,5825);local b=e.Books.BX
  -- Existing queued target is marketable against real quotes, but buying there is outside the guard.
  local child=e.Orders[p.TargetOrder];e:_unrest(b,child);child.Queued=true
  b.FairReference=(p.Target-10)/.25;p.Triggered="Take profit";p.ExitOrder=child.Id
  order(e,"maker",-1,2,p.Target-.25);e:ProcessPlayerOrders()
  assert(p.Quantity==3 and child.Queued and child.BlockedReason:find("price safeguard",1,true))
  local snap=e:Snapshot(a.Id,"BX","1m",true);local found=false
  for _,o in ipairs(snap.Orders)do if o.Protection=="Target"then found=o.Status:find("price safeguard",1,true)~=nil end end;assert(found)
  b.FairReference=p.Target/.25;e:ProcessPlayerOrders();assert(p.Quantity==1);e:Audit()
 end)
 test("Disconnected TP leaves depth but can close against connected liquidity",function()
  local e,a,p=fresh(-1,3,5825);e:SetConnectedOwners({user=true});e:SetConnected(a.Id,false)
  assert(#e.Books.BX.Bids==0 and e.Orders[p.TargetOrder].Queued)
  order(e,"maker",-1,2,p.Target);e:ProcessPlayerOrders();assert(p.Quantity==1 and p.Stop and p.TargetFilled==2)
  e:SetConnected(a.Id,true);e:ProcessPlayerOrders();assert(#e.Books.BX.Bids==1 and e.Orders[p.TargetOrder].Remaining==1)
  order(e,"maker",-1,1,p.Target);assert(not a.Positions.BX);e:Audit()
 end)
 test("A zero-liquidity market never fabricates a protective fill",function()
  local e,a,p=fresh(-1,307,5939.75,107);local volume=e.TotalVolume
  for _=1,5 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(p.Quantity==307 and e.TotalVolume==volume and not next(a.History));e:Audit()
 end)
 test("A bot limit cannot cross a target blocked by the price safeguard",function()
  local e,a,p=fresh(1,3,5825,100);e.Books.BX.FairReference=5825/.25
  local n=e.NextOrder
  local ok,message=e:Submit("maker",{Contract="BX",Direction=1,Quantity=2,Type="Limit",Price=p.Target})
  assert(not ok and message:find("No order placed",1,true)and e.NextOrder==n and p.Quantity==3);e:Audit()
 end)
 test("A stop consumes thin liquidity despite an exhausted entry budget",function()
  local e,a,p,c=fresh(1,3,5825);local stop=p.Stop
  local state=Policy.State(e);state.Markets["BX:-1"]={Used=0,Limit=0}
  state.Owners["user:-1"]=c.PlayerExecution.OwnerContracts;e.Books.BX.FairReference=stop/.25
  order(e,"maker",1,4,stop);order(e,"other",-1,1);e:ProcessStops()
  assert(not a.Positions.BX and a.History[1].Reason=="Stop loss");e:Audit()
 end)
 return results
end
return Tests
