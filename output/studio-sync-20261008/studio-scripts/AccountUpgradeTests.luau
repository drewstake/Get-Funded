local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local CP=require(script.Parent.WorldCheckpoint)
local P=require(script.Parent.Participants)
local T=require(script.Parent.TestLiquidity)
local Tools=require(game.ReplicatedStorage.MarketReign.ChartTools)
local Ranking=require(script.Parent.LeaderboardRanking)
local Tests={}
local function fresh()
 local e=E.new(C,712);local f=F.new(e,L,C);f:Join("101");return e,f,e.Accounts[f:Owner("101")]
end
local function restore(e)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(712),Agents={}},P)
 local r=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),C)
 return r,F.new(r,L,C)
end
local function open(e,a,side,qty)
 assert(T.Submit(e,a.Id,{Contract="BX",Type="Market",Quantity=qty or 1,Direction=side}))
 return a.Positions.BX
end
local function printPrice(e,price)
 local n="print:"..e.NextOrder;local b=e.Books.BX
 e:AddAccount(n,1e9,1e6,.99,false)
 T.Offer(e,"BX",-1,1,price)
 assert(e:Submit(n,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
 assert(b.Last*b.Spec.Tick==price,"Fixture did not execute the requested price")
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Legacy earned awards receive the current permanent bonus once",function()
  local e,f,a=fresh();local p=f:Profile("101")
  p.Awards.FirstWin={At=1,Title="Green Spark",Goal=25};p.Awards.Trades5={At=2,Title="Tape Reader",Goal=100}
  f:Evaluate("101",true);assert(f:StartingBalance(p)==22500 and a.Balance==10000)
  for _=1,3 do f:Evaluate("101",true);f:Join("101")end
  e,f=restore(e);p=f:Profile("101");assert(f:StartingBalance(p)==22500)
  assert(p.Awards.FirstWin.StartingBonus==5000 and p.Awards.Trades5.StartingBonus==7500)
 end)
 test("Saved bonuses increase on reload, never stack or shrink, and fund the next reset",function()
  local e,f,a=fresh();local p=f:Profile("101")
  for _,m in ipairs(L.Milestones)do p.Awards[m.Id]={At=1,Title=m.Title,Goal=m.Goal,StartingBonus=m.StartingBonus/10}end
  e,f=restore(e);p=f:Profile("101");a=e.Accounts[p.Account]
  local view=f:View("101");assert(view.StartingBonus==250000 and view.StartingBalance==260000)
  assert(a.Balance==10000 and f:Earned(p)==0 and f:_counts(p)==0)
  for i,m in ipairs(L.Milestones)do assert(view.Milestones[i].Earned and view.Milestones[i].StartingBonus==m.StartingBonus)end
  local revision=p.Revision
  for _=1,3 do assert(#f:Evaluate("101",true)==0);f:Join("101")end
  assert(p.Revision==revision and f:StartingBalance(p)==260000)
  -- A later lower tuning must preserve an already-earned larger reward.
  p.Awards.FirstWin.StartingBonus=6000
  e,f=restore(e);p=f:Profile("101");assert(p.Awards.FirstWin.StartingBonus==6000 and f:StartingBalance(p)==261000)
  assert(f:ResetAccount("101",p.Account));assert(e.Accounts[p.Account].Balance==261000)
  assert(f:Earned(p)==0 and f:_counts(p)==0);e:Audit()
  e,f=restore(e);p=f:Profile("101");assert(e.Accounts[p.Account].Balance==261000 and f:StartingBalance(p)==261000);e:Audit()
 end)
 test("Reset clears both directions and pending stops without trades, P&L or milestone progress",function()
  for _,side in ipairs({1,-1})do
   local e,f,a=fresh();local p=f:Profile("101");local held=open(e,a,side,2)
   held.Stop=held.Entry-side*2;held.Target=held.Entry+side*4
   assert(e:Submit(a.Id,{Contract="BT",Type="Limit",Direction=1,Quantity=1,Price=C.Contracts.BT.Last-100}))
   table.insert(e.PendingStops,{Owner=a.Id,Contract="BX",Position=held.Id})
   f:Depart("101",100);local id=a.Id;local trades=e.NextTrade
   local stats=f:Stats("101");assert(f:ResetAccount("101",id));assert(not f:ResetAccount("101",id))
   local nextA=e.Accounts[f:Owner("101")];assert(nextA.Balance==10000 and not next(nextA.Positions)and not next(nextA.OpenOrders))
   assert(e.NextTrade==trades and f:Earned(p)==0 and f:_counts(p)==0 and not next(p.Awards))
   assert(not p.Absence and not p.AwaySummary)
   e:ProcessStops();e:AdvanceClock(.25);e:Audit()
   e,f=restore(e);assert(not next(e.Accounts[f:Owner("101")].Positions));assert(f:_counts(f:Profile("101"))==0);e:Audit()
  end
 end)
 test("Earned balance and permanent rank survive healthy resets; reset tokens and ownership are enforced",function()
  local e,f,a=fresh();local p=f:Profile("101")
  p.Awards.FirstWin={StartingBonus=500};p.RankId="Apprentice";f:Evaluate("101",true)
  assert(not f:ResetAccount("101","player:other:single:1"))
  for _=1,L.ResetLimits.Burst do local id=p.Account;assert(f:ResetAccount("101",id));assert(e.Accounts[p.Account].Balance==15000 and p.RankId=="Apprentice")end
  assert(not f:ResetAccount("101",p.Account));e:Audit()
 end)
 test("Open positions remain open; gains before disconnect are excluded; summary acknowledgment persists",function()
  local e,f,a=fresh();local held=open(e,a,1);local entry=held.Entry
  printPrice(e,entry+2);f:Depart("101",100);e:SetConnected(a.Id,false)
  printPrice(e,entry+3);e:AdvanceClock(.25);f:Return("101",160)
  local p=f:Profile("101");local summary=p.AwaySummary
  assert(a.Positions.BX and summary.Seconds==60 and summary.Realized==0 and summary.UnrealizedChange==50 and summary.Total==50)
  assert(summary.Unrealized==150 and summary.Rows[1].Unrealized==150 and f:View("101").AwaySummary.Unrealized==150)
  local id=summary.Id;f:Return("101",170);assert(p.AwaySummary.Id==id)
  assert(f:AcknowledgeAway("101",id));assert(f:AcknowledgeAway("101",id))
  e,f=restore(e);assert(not f:Profile("101").AwaySummary);e:Audit()
 end)
 for _,side in ipairs({1,-1})do for _,field in ipairs({"Stop","Target"})do
  test((side==1 and "Long"or "Short").." offline "..field.." latches from executed history and settles once",function()
   local e,f,a=fresh();local held=open(e,a,side,2);local entry=held.Entry
   local threshold=entry+(field=="Stop"and -side or side)*4;held[field]=threshold
   printPrice(e,entry+side);f:Depart("101",100);e:SetConnected(a.Id,false)
   printPrice(e,threshold)
   assert(held.Triggered==(field=="Stop"and "Stop loss"or "Take profit"))
   -- Real executable counterparties fill the protective reduction.
   T.Offer(e,"BX",side,2,threshold);e:ProcessStops()
   assert(not a.Positions.BX,"Protection must close against offered liquidity")
   printPrice(e,entry);e:ProcessStops()
   local count=f:_counts(f:Profile("101"));assert(count==1)
   e,f=restore(e);f:Return("101",200)
   local p=f:Profile("101");local summary=p.AwaySummary
   assert(summary and #summary.Rows[1].Exits==1 and summary.Rows[1].Exits[1].Reason==(field=="Stop"and "Stop loss"or "Take profit"))
   assert(summary.RealizedChange==(threshold-entry-side)*side*2*50 and summary.UnrealizedChange==0)
   assert(summary.Realized==(threshold-entry)*side*2*50 and summary.Unrealized==0)
   assert(summary.Rows[1].Exits[1].Realized==summary.Realized)
   e:ProcessStops();assert(f:_counts(p)==count);e:Audit()
  end)
 end end
 test("Liquidation while absent uses an intervening execution, not recovered reconnect price",function()
  local e,f,a=fresh();local held=open(e,a,1,5);local entry=held.Entry
  f:Depart("101",100);e:SetConnected(a.Id,false);printPrice(e,entry-40)
  assert(a.Depleted and held.Triggered=="Account depleted")
  T.Offer(e,"BX",1,5,entry-40);e:ProcessStops();printPrice(e,entry)
  f:Return("101",200);local summary=f:Profile("101").AwaySummary
  assert(summary.Total==-10000 and summary.Rows[1].Exits[1].Reason=="Account depleted");e:Audit()
 end)
 test("Partial offline exits split carried-in, realized change and remaining unrealized change",function()
  local e,f,a=fresh();local held=open(e,a,1,2);local entry=held.Entry
  printPrice(e,entry+2);f:Depart("101",100)
  assert(T.Submit(e,a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
  printPrice(e,entry+3);f:Return("101",140);local s=f:Profile("101").AwaySummary
  assert(s.Realized==100 and s.CarriedIn==100 and s.RealizedChange==0 and s.UnrealizedChange==50 and s.Total==50)
  assert(s.Unrealized==150 and s.Realized+s.Unrealized==250)
  assert(s.Rows[1].Remaining==1);e:Audit()
 end)
 test("Paused returns show full entry P&L for long and short gains and losses",function()
  for _,side in ipairs({1,-1})do for _,move in ipairs({-8,8})do
   local e,f,a=fresh();local held=open(e,a,side,2)
   printPrice(e,held.Entry+move);local expected=e:Summary(a).Unrealized
   f:Depart("101",100);e,f=restore(e);f:Return("101",200)
   local summary=f:View("101").AwaySummary
   assert(expected==move*side*2*50 and summary.Unrealized==expected)
   assert(summary.Total==0 and summary.Realized==0 and summary.MarketSeconds==0)
   e:Audit()
  end end
 end)
 test("Older saved summaries recover full P&L from their return price without changing with live quotes",function()
  local e,f,a=fresh();local held=open(e,a,1,2);local entry=held.Entry
  printPrice(e,entry+8);f:Depart("101",100);f:Return("101",200)
  local p=f:Profile("101");p.AwaySummary.Unrealized=nil;p.AwaySummary.Rows[1].Unrealized=nil
  e,f=restore(e);p=f:Profile("101");printPrice(e,entry+10)
  local summary=f:View("101").AwaySummary
  assert(summary.Unrealized==800 and summary.Rows[1].Unrealized==800 and summary.Total==0)
  assert(f:View("101").Open==1000 and p.AwaySummary.Unrealized==nil and p.AwaySummary.Rows[1].Unrealized==nil)
  assert(f:AcknowledgeAway("101",summary.Id));assert(not f:View("101").AwaySummary);e:Audit()
 end)
 test("Price-history absence never creates returns while simulation is paused",function()
  local e,f,a=fresh();open(e,a,-1);f:Depart("101",100);e,f=restore(e);f:Return("101",86400)
  local s=f:Profile("101").AwaySummary;assert(s.MarketSeconds==0 and s.Total==0 and s.Rows[1].Remaining==1 and #s.Rows[1].Exits==0)
 end)
 test("Drag-created SL/TP validates both directions, stale quantities, wrong sides and duplicates",function()
  for _,side in ipairs({1,-1})do
   local e,f,a=fresh();local held=open(e,a,side,2)
   for _,field in ipairs({"Stop","Target"})do
    local price=held.Entry+(field=="Stop"and -side or side)*2
    local req={Contract="BX",OrderId=held.Id,Protection=field,Create=true,ExpectedQuantity=2,Price=price}
    assert(e:AmendProtection(a.Id,req));assert(not e:AmendProtection(a.Id,req))
   end
   assert(held.Stop and held.Target)
   e:CancelProtection(a.Id,held.Id,"Stop")
   local req={Contract="BX",OrderId=held.Id,Protection="Stop",Create=true,ExpectedQuantity=1,Price=held.Entry-side*2}
   assert(not e:AmendProtection(a.Id,req));req.ExpectedQuantity=2;req.Price=held.Entry+side*2;assert(not e:AmendProtection(a.Id,req))
   req.Price=0/0;assert(not e:AmendProtection(a.Id,req));e:Audit()
  end
 end)
 test("Soft magnet chooses nearest OHLC, holds near ties and releases at different zoom levels",function()
  local c={Time=100,Open=100,Close=104,High=108,Low=96}
  for _,scale in ipairs({1,4,20})do
   local function y(p)return (110-p)*scale end
   local hit=Tools.SoftSnap(c,y,y(c.High)+.5);assert(hit and hit.Field=="High")
   assert(Tools.SoftSnap(c,y,y(c.Low)+.5).Field=="Low")
   assert(Tools.SoftSnap(c,y,y(c.High)-9,hit).Field=="High")
   assert(not Tools.SoftSnap(c,y,y(c.High)-12,hit))
  end
  assert(Tools.ProtectionField(1,100,99)=="Stop" and Tools.ProtectionField(1,100,101)=="Target")
  assert(Tools.ProtectionField(-1,100,99)=="Target" and Tools.ProtectionField(-1,100,101)=="Stop")
 end)
 test("Leaderboard projects raw account balance without changing negative accounting",function()
  local e,f,a=fresh();a.Balance=-125;a.Realized=a.Balance-a.Base;a.Stats.UntrackedNet=a.Realized;a.Stats.Trades=1;a.Stats.Losses=1
  assert(Ranking.Row(f,"101").Cents==-12500 and a.Balance==-125)
 end)
 test("Reset confirmation keeps its original run token after a lost response",function()
  local M=require(game.ReplicatedStorage.MarketReign.MarketClient);local session=M.New(nil,true)
  session.Preview=false;session.CanTrade=true;session.AccountToken="new-run"
  local captured;session.Remote={FireServer=function(_,request)captured=request end}
  assert(session:ResetAccount("confirmed-old-run"));assert(captured.ExpectedAccount=="confirmed-old-run")
  session:Destroy()
 end)
 return rows
end
return Tests


