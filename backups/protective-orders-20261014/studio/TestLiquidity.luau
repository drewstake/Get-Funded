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
 for _,l in ipairs(levels)do qty+=l.Quantity;ticks=l.Price end
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
return T
