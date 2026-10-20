-- Disposable exchanges only: close notifications must describe a whole position, not its last fill.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Liquidity=require(script.Parent.TestLiquidity)
local Tests={}
local uid="closed-pnl-test"
local function fresh()
 local c=table.clone(C);local l=table.clone(L);l.StartingBalance=200000
 local e=E.new(c,8192);local f=F.new(e,l,c);f:Join(uid)
 return e,f,f:Owner(uid)
end
local function fill(e,id,key,side,qty,price,reduce)
 Liquidity.Offer(e,key,-side,qty,price)
 local ok,r=e:Submit(id,{Contract=key,Direction=side,Quantity=qty,Type="Market",ReduceOnly=reduce})
 assert(ok and r.Filled==qty,tostring(r));return r
end
local function near(actual,expected)
 assert(math.abs(actual-expected)<0.001,tostring(actual).." differs from "..tostring(expected))
end
local function closed(f,expected,qty)
 local events=f:TakeEvents(uid);assert(events and #events==1,"Expected one completed-position notification")
 local ev=events[1];assert(ev.Kind=="TradeClosed");near(ev.Pnl,expected)
 assert(ev.Quantity==qty and ev.PositionId and ev.TradeId,"Missing closed-position identity/quantity")
 assert(not f:TakeEvents(uid),"Close was announced twice");return ev
end
local function restore(e)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(8192),Agents={}},P)
 local r=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),e.Config)
 return r,F.new(r,L,r.Config)
end
function Tests.Run()
 local rows={}
 local function test(name,fn)
  local ok,detail=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and (detail or "Passed")or tostring(detail)})
 end
 for _,side in ipairs({1,-1})do for _,move in ipairs({4,-4,0})do
  test((side==1 and "Long"or "Short").." 40 + 20 + 30 + 30 contracts: whole-position PNL, move "..move,function()
   local e,f,id=fresh();local cost=0
   for _,entry in ipairs({{40,5825},{20,5826},{30,5827},{30,5828}})do
    fill(e,id,"BX",side,entry[1],entry[2]);cost+=entry[1]*entry[2]
   end
   local position=e.Accounts[id].Positions.BX;local positionId=position.Id
   local average=cost/120;near(position.Entry,average)
   assert(not f:TakeEvents(uid),"Entries should not announce a close")
   -- Offer 100 first, then the final 20 on a later step to exercise a partial close.
   local proceeds=0
   for _,q in ipairs({10,15,25,50})do
    local price=5826.5+side*move
    Liquidity.Offer(e,"BX",side,q,price);proceeds+=q*price
   end
   local before=e.Accounts[id].Realized
   assert(F.Perform(e,id,{Action="Close",Contract="BX"}))
   assert(e.Accounts[id].Positions.BX.Quantity==20)
   assert(not f:TakeEvents(uid),"A partial fill announced the whole trade closed")
   local finalPrice=5826.5+side*move;Liquidity.Offer(e,"BX",side,20,finalPrice);proceeds+=20*finalPrice
   e:AdvanceClock(e.Config.StepSeconds);e:ProcessPlayerOrders();assert(not e.Accounts[id].Positions.BX)
   local expected=(proceeds-cost)*side*50;local ev=closed(f,expected,120)
   assert(ev.PositionId==positionId and ev.Reason=="Player close")
   near(e.Accounts[id].Realized-before,expected);near(ev.Balance,e.Accounts[id].Balance);e:Audit()
   return {Pnl=ev.Pnl,LastFillPnl=e.Accounts[id].History[1].Pnl,Quantity=ev.Quantity}
  end)
 end end
 test("Partial exits survive save/rejoin and trimmed history; new additions stay in the same trade",function()
  local e,f,id=fresh();e.Config.MaxAccountHistory=2
  fill(e,id,"BX",1,40,5825)
  for _=1,5 do fill(e,id,"BX",-1,5,5827,true)end
  assert(not f:TakeEvents(uid));assert(#e.Accounts[id].History==2)
  e,f=restore(e)
  fill(e,id,"BX",1,20,5826)
  fill(e,id,"BX",-1,35,5828,true)
  closed(f,(25*2+15*3+20*2)*50,60)
  assert(not f:Profile(uid).PendingTradeCloses);e:Audit()
 end)
 test("Prior trades and other open markets never enter the closed position total",function()
  local e,f,id=fresh()
  fill(e,id,"BX",1,2,5825);fill(e,id,"BX",-1,2,5832,true);closed(f,700,2)
  fill(e,id,"BX",1,4,5825);fill(e,id,"BT",-1,3,20480)
  fill(e,id,"BX",-1,1,5826,true);assert(not f:TakeEvents(uid))
  fill(e,id,"BT",1,3,20482,true);local other=closed(f,-120,3);assert(other.Contract=="BT")
  fill(e,id,"BX",-1,3,5827,true);closed(f,350,4)
  near(e.Accounts[id].Realized,930);e:Audit()
 end)
 test("A reversal completes the old trade and starts a separate result for the new direction",function()
  local e,f,id=fresh()
  fill(e,id,"BX",1,3,5825);fill(e,id,"BX",-1,1,5826,true)
  assert(not f:TakeEvents(uid))
  fill(e,id,"BX",-1,5,5827);closed(f,250,3)
  assert(e.Accounts[id].Positions.BX.Direction==-1 and e.Accounts[id].Positions.BX.Quantity==3)
  fill(e,id,"BX",1,3,5828,true);closed(f,-150,3);e:Audit()
 end)
 test("Rewards earned on earlier fills accompany the final notification once",function()
  local e,f,id=fresh();local profile=f:Profile(uid)
  -- Set only the test configuration threshold; the award still comes from real close accounting.
  local config=table.clone(f.Config);config.Milestones={{Id="FillReward",Kind="Profit",Goal=50,Title="Fill reward",Name="Fill reward",StartingBonus=0}}
  f.Config=config
  fill(e,id,"BX",1,3,5825);fill(e,id,"BX",-1,1,5826,true)
  assert(profile.Awards.FillReward and not f:TakeEvents(uid))
  fill(e,id,"BX",-1,2,5825,true);local ev=closed(f,50,3)
  assert(#ev.Rewards==1 and ev.Rewards[1]=="Fill reward");e:Audit()
 end)
 test("Older open trades recover earlier partial closes from their retained position history",function()
  local e,f,id=fresh()
  fill(e,id,"BX",1,3,5825);fill(e,id,"BX",-1,1,5826,true)
  f:TakeEvents(uid);f:Profile(uid).PendingTradeCloses=nil
  fill(e,id,"BX",-1,2,5827,true);closed(f,250,3);e:Audit()
 end)
 test("Reset discards an unfinished close result and never carries it into the next account",function()
  local e,f,id=fresh();fill(e,id,"BX",1,3,5825);fill(e,id,"BX",-1,1,5826,true)
  assert(f:Profile(uid).PendingTradeCloses and not f:TakeEvents(uid))
  assert(f:ResetAccount(uid,id));assert(not f:Profile(uid).PendingTradeCloses)
  id=f:Owner(uid);fill(e,id,"BX",1,1,5825);fill(e,id,"BX",-1,1,5824,true)
  closed(f,-50,1);e:Audit()
 end)
 for _,reason in ipairs({"Take profit","Stop loss"})do
  test(reason.." aggregates multiple exit prices and waits for the final fill",function()
   local e,f,id=fresh();fill(e,id,"BX",1,4,5825)
   local p=e.Accounts[id].Positions.BX;p.Triggered=reason
   local first=reason=="Take profit"and 5828 or 5822
   if reason=="Take profit"then p.Target=first-1 end
   Liquidity.Offer(e,"BX",1,1,first);e:AdvanceClock(e.Config.StepSeconds);e:ProcessPlayerOrders()
   assert(e.Accounts[id].Positions.BX and not f:TakeEvents(uid))
   Liquidity.Offer(e,"BX",1,3,first-1);e:AdvanceClock(e.Config.StepSeconds);e:ProcessPlayerOrders()
   local ev=closed(f,((first-5825)+3*(first-1-5825))*50,4);assert(ev.Reason==reason);e:Audit()
  end)
 end
 test("Break-even closes still produce exactly one zero-PNL message",function()
  local e,f,id=fresh();fill(e,id,"BX",1,2,5825)
  fill(e,id,"BX",-1,1,5826,true);assert(not f:TakeEvents(uid))
  fill(e,id,"BX",-1,1,5824,true);closed(f,0,2);e:Audit()
 end)
 return rows
end
return Tests
