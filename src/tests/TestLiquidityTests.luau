-- Regression coverage for explicit settlement fixtures and finite execution liquidity.
local C=table.clone(require(game.ReplicatedStorage.MarketReign.MarketConfig))
C.BotPopulation=nil
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local T=require(script.Parent.TestLiquidity)
local Tests={}
local function fresh()
 local e=E.new(C,641);local f=F.new(e,L,C);f:Join("fixture-test")
 return e,f,f:Owner("fixture-test"),C.Contracts.BX.Last
end
local function request(side,qty,reduce)return {Contract="BX",Direction=side,Quantity=qty,Type="Market",ReduceOnly=reduce}end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(r)})end
 test("Exact offers retain thin-book partial fills and immediate cancellation",function()
  local e,_,id,price=fresh();e.Books.BX.FairReference=e.Books.BX.Reference
  local offer=T.Offer(e,"BX",-1,10,price);assert(e.Orders[offer.Id].Remaining==10)
  local ok,r=e:Submit(id,request(1,2));assert(ok and r.Filled==1 and r.Cancelled==1 and not e.Orders[r.Id])
  assert(e.Accounts[id].Positions.BX.Quantity==1 and e.TotalVolume==1);e:Audit()
 end)
 test("Adding quotes does not reset a spent window; elapsed windows restore capacity",function()
  local e,_,id,price=fresh();e.Books.BX.FairReference=e.Books.BX.Reference
  T.Offer(e,"BX",-1,10,price);local _,first=e:Submit(id,request(1,1));assert(first.Filled==1)
  T.Offer(e,"BX",-1,100,price);local _,blocked=e:Submit(id,request(1,1));assert(blocked.Filled==0 and blocked.Cancelled==1)
  e:AdvanceClock(C.PlayerExecution.WindowSeconds);local _,nextFill=e:Submit(id,request(1,1));assert(nextFill.Filled==1);e:Audit()
 end)
 test("Manual close retains its remainder and announces only after the final real fill",function()
  local e,f,id,price=fresh();T.FillAt(e,id,request(1,3),price)
  T.Offer(e,"BX",1,1,price);local ok,r=F.Perform(e,id,{Action="Close",Contract="BX"})
  assert(ok and r.Filled==1 and r.Remaining==2 and e.Orders[r.Id].Queued)
  assert(e.Accounts[id].Positions.BX.Quantity==2 and not f:TakeEvents("fixture-test"))
  e:ProcessPlayerOrders();assert(e.Accounts[id].Positions.BX.Quantity==2)
  T.Offer(e,"BX",1,2,price);e:AdvanceClock(C.PlayerExecution.WindowSeconds);e:ProcessPlayerOrders()
  local events=f:TakeEvents("fixture-test");assert(not e.Accounts[id].Positions.BX and events and #events==1 and events[1].Quantity==3)
  assert(not f:TakeEvents("fixture-test") and e.TotalVolume==6);e:Audit()
 end)
 test("Settlement helpers use real counterparties, preserve policy and clear stale quotes",function()
  local e,_,id,price=fresh();local base=e.Accounts[id].Balance;local clock=e.Time
  for _=1,2 do T.FillAt(e,id,request(1,2),price);T.FillAt(e,id,request(-1,2,true),price+.5)end
  assert(e.TotalVolume==8 and e.Accounts[id].Realized==100 and e.Accounts[id].Balance==base+100)
  assert(e.Time==clock+4*C.PlayerExecution.WindowSeconds and C.PlayerExecution.BookFraction==.1)
  for _,a in pairs(e.Accounts)do if a.Id:sub(1,8)=="fixture:"then assert(not next(a.OpenOrders))end end
  assert(not e.Accounts[E.HouseId]);e:Audit()
 end)
 test("Settlement helper fails loudly when a request exceeds player capacity",function()
  local e,_,id,price=fresh();assert(not pcall(T.FillAt,e,id,request(1,100),price))
  assert(not e.Accounts[id].Positions.BX and e.TotalVolume==0);e:Audit()
 end)
 test("Ticket settlement retains dollar-to-tick validation and creates real protection",function()
  local e,_,id,price=fresh()
  T.PlaceAt(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=2,Type="Market",StopDollars=100,TargetDollars=200},price)
  local p=e.Accounts[id].Positions.BX;assert(p.Stop==price-1 and p.Target==price+2 and p.TargetOrder)
  assert(e.TotalVolume==2);e:Audit()
 end)
 test("Price fixture walks real executions inside the collar in both directions",function()
  for _,side in ipairs({1,-1})do
   local e,_,_,price=fresh();local tick=e.Books.BX.Spec.Tick;local guard=C.PlayerExecution.GuardTicks
   T.PrintPrice(e,"BX",price+side*(guard*2+3)*tick)
   assert(e.TotalVolume==3 and e.Books.BX.Last*tick==price+side*(guard*2+3)*tick)
   local trades=table.clone(e.Trades);table.sort(trades,function(a,b)return a.Id<b.Id end)
   local prior=price;for _,trade in ipairs(trades)do assert(trade.Quantity==1 and math.abs(trade.Price-prior)<=guard*tick);prior=trade.Price end
   assert(#trades==3 and not next(e.Accounts["fixture:print:BX"].OpenOrders));e:Audit()
  end
 end)
 return rows
end
return Tests
