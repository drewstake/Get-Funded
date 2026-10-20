local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(script.Parent.TestLiquidity)
local Tests={}
function Tests.Run()
 local results={};local function test(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
 for _,key in ipairs(C.ContractOrder)do for _,side in ipairs({1,-1})do
  test(key.." "..side..": protections survive adds, partial fills and reductions; reversal gets new levels",function()
   local e=E.new(C,451);local a=e:AddAccount("player",2000000,2000,.8,true)
   local b=e.Books[key];local price=b.Reference*b.Spec.Tick;local tick=b.Spec.Tick
   L.Offer(e,key,-side,2,price)
   assert(e:Submit(a.Id,{Contract=key,Direction=side,Quantity=2,Type="Market",StopTicks=10,TargetTicks=20}))
   local p=a.Positions[key];local stop,target,entry=p.Stop,p.Target,p.Entry
   L.Offer(e,key,-side,1,price+side*2*tick)
   local ok,order=e:Submit(a.Id,{Contract=key,Direction=side,Quantity=3,Type="Limit",Price=price+side*4*tick,StopTicks=1,TargetTicks=2})
   assert(ok and order.Filled==1 and order.Remaining==2)
   assert(p.Quantity==3 and p.Stop==stop and p.Target==target and p.Entry~=entry)
   local provider="fixture:liquidity:"..key..":"..(-side)
   assert(e:Submit(provider,{Contract=key,Direction=-side,Quantity=2,Type="Market"}))
   assert(p.Quantity==5 and p.Stop==stop and p.Target==target and not p.Triggered)
   local covered=0;for _,o in ipairs(e:Snapshot(a.Id,key,"1m",true).Orders)do
    if o.Protection then assert(o.Quantity==5);covered+=1 end
   end;assert(covered==2)
   L.Offer(e,key,side,1,price)
   assert(e:Submit(a.Id,{Contract=key,Direction=-side,Quantity=1,Type="Market",ReduceOnly=true}))
   assert(p.Quantity==4 and p.Stop==stop and p.Target==target)
   L.Offer(e,key,side,5,price)
   assert(e:Submit(a.Id,{Contract=key,Direction=-side,Quantity=5,Type="Market",StopTicks=8,TargetTicks=16}))
   local reversed=a.Positions[key]
   assert(reversed.Id~=p.Id and reversed.Direction==-side and reversed.Quantity==1)
   assert(math.abs(reversed.Stop-(price+side*8*tick))<1e-6 and math.abs(reversed.Target-(price-side*16*tick))<1e-6)
   e:Audit()
  end)
 end end
 test("Entry-label replacement rejects stale quantity and stale price atomically",function()
  local e=E.new(C,452);local a=e:AddAccount("player",2000000,2000,.8,true)
  assert(L.Submit(e,a.Id,{Contract="BX",Direction=1,Quantity=2,Type="Market",StopTicks=10,TargetTicks=20}))
  local p=a.Positions.BX;local old=p.Stop
  local request={Contract="BX",OrderId=p.Id,Protection="Stop",Price=old-.25,ExpectedPrice=old,ExpectedQuantity=1}
  assert(not e:AmendProtection(a.Id,request)and p.Stop==old)
  request.ExpectedQuantity=2;request.ExpectedPrice=old-.25
  assert(not e:AmendProtection(a.Id,request)and p.Stop==old)
  request.ExpectedPrice=old;assert(e:AmendProtection(a.Id,request));assert(p.Stop==old-.25)
  assert(e:CancelProtection(a.Id,p.Id,"Target"))
  assert(e:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=p.Entry+10,Create=true,ExpectedQuantity=2}))
  e:Audit()
 end)
 return results
end
return Tests
