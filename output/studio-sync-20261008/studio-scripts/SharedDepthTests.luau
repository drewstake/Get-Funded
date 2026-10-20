-- Finite shared liquidity: isolated engines, no live player balances or purchase grants.
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Tests={}
function Tests.Run()
 local results={}
 local function test(name,fn)local ok,result=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(result)})end
 local function fresh()
  local e=E.new(C,7261)
  for _,id in ipairs({"p1","p2","p3"})do e:AddAccount(id,100000,100,.9,true)end
  e:AddAccount("bot",1e9,10000,.9,false)
  e:SetConnectedOwners({p1=true,p2=true,p3=true})
  return e
 end
 local function order(e,id,side,qty,price,extra)
  local req={Contract="BX",Direction=side,Quantity=qty,Type=price and "Limit"or "Market",Price=price}
  for k,v in pairs(extra or{})do req[k]=v end
  local ok,result=e:Submit(id,req);assert(ok,tostring(result));return result
 end
 local function book(e)return e:Snapshot("p2","BX","1m",true).Quotes.BX.Depth end
 test("Player and participant quantities aggregate anonymously and execute FIFO",function()
  local e=fresh();local first=order(e,"p1",-1,3,5825);local second=order(e,"bot",-1,4,5825)
  local depth=book(e);assert(#depth.Asks==1 and depth.Asks[1].Quantity==7 and depth.Asks[1].Price==5825)
  for k in pairs(depth.Asks[1])do assert(k=="Price"or k=="Quantity","Identity leaked")end
  order(e,"p2",1,2);assert(e.Orders[first.Id].Remaining==1 and e.Orders[second.Id].Remaining==4 and book(e).Asks[1].Quantity==5)
  order(e,"p3",1,2);assert(not e.Orders[first.Id]and e.Orders[second.Id].Remaining==3 and book(e).Asks[1].Quantity==3)
  assert(e:Cancel("bot",second.Id));assert(#book(e).Asks==0)
  assert(not e.Accounts[E.HouseId],"Live player fill used the historical house")
  e:Audit()
 end)
 test("Price priority and finite marketable limits leave exact residuals",function()
  local e=fresh();order(e,"p1",-1,2,5825.25);order(e,"bot",-1,2,5825)
  local r=order(e,"p2",1,6,5825);assert(r.Filled==2 and r.Remaining==4 and r.Average==5825)
  assert(book(e).Bids[1].Quantity==4 and book(e).Asks[1].Price==5825.25)
  order(e,"p3",-1,1);assert(e.Orders[r.Id].Remaining==3 and book(e).Bids[1].Quantity==3)
  e:Audit()
 end)
 test("Empty and one-sided books never generate synthetic fills or levels",function()
  local e=fresh();local r=order(e,"p1",1,3);assert(r.Filled==0 and r.Cancelled==3 and not e.Accounts.p1.Positions.BX)
  assert(#book(e).Asks==0 and #book(e).Bids==0)
  order(e,"p2",1,2,5824);assert(#book(e).Asks==0 and #book(e).Bids==1)
  e:Audit()
 end)
 test("Repricing retains identity and protection but resets FIFO priority",function()
  local e=fresh();local a=order(e,"p1",-1,3,5826,{StopTicks=10,TargetTicks=20});local b=order(e,"p3",-1,2,5825)
  assert(e:AmendOrder("p1",{Contract="BX",OrderId=a.Id,Price=5825,ExpectedPrice=5826,ExpectedQuantity=3}))
  assert(e.Orders[a.Id].StopTicks==10 and e.Orders[a.Id].TargetTicks==20)
  local snapshot=Checkpoint.Capture(e,setmetatable({Engine=e,Config=C,Random=P.RNG.new(7261),Agents={}},P))
  local restored=Checkpoint.Restore(snapshot,C);assert(restored.Books.BX.Asks[1].Orders[1].Id==b.Id)
  order(restored,"p2",1,3);assert(not restored.Orders[b.Id]and restored.Orders[a.Id].Remaining==2)
  restored:Audit()
 end)
 test("Self-trade prevention covers multiple accounts with the same owner",function()
  local e=fresh();e.Accounts.p1.Group="same";e.Accounts.p2.Group="same"
  local a=order(e,"p1",-1,3,5825);order(e,"p2",1,3)
  assert(not e.Orders[a.Id]and e.TotalVolume==0 and not e.Accounts.p1.Positions.BX)
  e:Audit()
 end)
 test("Disconnect cancels all resting liquidity and rejects stale entries",function()
  local e=fresh();local a=order(e,"p1",-1,3,5825);order(e,"p3",1,2,5824)
  e:SetConnected("p1",false);assert(not e.Orders[a.Id]and #book(e).Asks==0 and book(e).Bids[1].Quantity==2)
  assert(not e:Submit("p1",{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  e:SetConnected("p1",true);assert(#book(e).Asks==0,"Reconnect resurrected cancelled orders")
  e:Audit()
 end)
 test("Invalid capacity, expired orders and untriggered stops are excluded",function()
  local e=fresh();local a=order(e,"p1",-1,10,5825);e.Accounts.p1.Balance=1000;e.Accounts.p1.Realized=-99000
  local r=order(e,"p3",1,2,5824,{Expires=e.Time+1})
  order(e,"p2",1,2,5830,{Type="Stop"})
  assert(#book(e).Asks==0 and not e.Orders[a.Id]and #book(e).Bids==1)
  e:AdvanceClock(1);assert(not e.Orders[r.Id]and #book(e).Bids==0)
  e.Accounts.p1.Balance=e.Accounts.p1.Base;e.Accounts.p1.Realized=0;e:Audit()
 end)
 test("Stop entries wait for liquidity, partially fill, then report once",function()
  local e=fresh();local r=order(e,"p1",1,3,5826,{Type="Stop",StopTicks=4,TargetTicks=8})
  order(e,"bot",-1,1,5826);order(e,"p2",1,1);e:ProcessStops()
  assert(e.Orders[r.Id]and not e.Accounts.p1.Positions.BX)
  order(e,"bot",-1,1,5826.25);e:ProcessStops();assert(e.Accounts.p1.Positions.BX.Quantity==1 and e.Orders[r.Id].Remaining==2)
  order(e,"p3",-1,2,5826.5);e:ProcessStops()
  assert(not e.Orders[r.Id]and e.Accounts.p1.Positions.BX.Quantity==3 and #e.Accounts.p1.Triggers==1 and e.Accounts.p1.Triggers[1].Filled==3)
  e:Audit()
 end)
 test("Stop-loss partial fills retry without reversing and preserve OCO",function()
  local e=fresh();order(e,"bot",-1,3,5825);order(e,"p1",1,3,nil,{StopTicks=4,TargetTicks=8})
  order(e,"p2",1,2,5824);order(e,"p3",-1,1);e:ProcessStops()
  local p=e.Accounts.p1.Positions.BX;assert(p.Quantity==2 and p.Triggered=="Stop loss"and not p.Target)
  order(e,"p2",1,2,5823.75);e:AdvanceClock(.25);assert(not e.Accounts.p1.Positions.BX)
  e:Audit()
 end)
 test("Take-profit rests at its target and cannot fill at a worse price",function()
  local e=fresh();order(e,"bot",-1,3,5825);order(e,"p1",1,3,nil,{StopTicks=4,TargetTicks=8})
  order(e,"p2",1,1,5827);order(e,"p3",-1,1);e:ProcessStops()
  local p=e.Accounts.p1.Positions.BX;assert(p and p.ExitOrder and e.Orders[p.ExitOrder].Remaining==3 and not p.Stop)
  local id=p.ExitOrder;e:AdvanceClock(.25);assert(p.ExitOrder==id and e.Orders[id],"TP lost priority during retry")
  order(e,"p2",1,2,5826.75);assert(e.Accounts.p1.Positions.BX.Quantity==3)
  order(e,"p2",1,3,5827);assert(not e.Accounts.p1.Positions.BX and e.Accounts.p1.History[1].Exit==5827)
  e:Audit()
 end)
 test("Old checkpoints cancel off-book player limits without rewriting balances or tape",function()
  local e=fresh();local r=order(e,"p1",1,3,5824)
  local state=Checkpoint.Capture(e,setmetatable({Engine=e,Config=C,Random=P.RNG.new(7261),Agents={}},P));state.Version=8
  local restored=Checkpoint.Restore(state,C)
  assert(not restored.Orders[r.Id]and restored.TotalVolume==e.TotalVolume and restored.Accounts.p1.Balance==e.Accounts.p1.Balance)
  restored:Audit()
 end)
 test("Maker quotes retain queue position and partial quantity between material changes",function()
  local e=E.new(C,42617);local bots=P.new(e);local a=bots.Agents[1]
  -- Freeze the other participants and fair value to isolate cancellation churn.
  e:CancelAll(a.Id);a.QuotePolicy=nil;bots:_maker(a)
  local ids={};for _,id in pairs(a.Quotes)do ids[id]=e.Orders[id].Remaining end
  assert(next(ids),"No maker quote")
  for _=1,5 do e.Time+=1;bots:_maker(a)end
  for id,qty in pairs(ids)do assert(e.Orders[id]and e.Orders[id].Remaining==qty,"Unchanged quote churned")end
  e:Audit()
 end)
 return results
end
return Tests
