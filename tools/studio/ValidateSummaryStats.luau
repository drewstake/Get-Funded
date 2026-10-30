-- Isolated in-memory checks. Does not access live profiles or DataStores.
local server=game.ServerScriptService.MarketReign:Clone()
server.Name="SummaryStatsChecks" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local report={}
local ok,err=pcall(function()
 local E=require(server.MarketEngine) local F=require(server.FundedAccounts) local S=require(server.TradeStats)
 local C=require(game.ReplicatedStorage.MarketReign.MarketConfig) local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
 local function near(a,b)assert(a and math.abs(a-b)<1e-6,tostring(a).." expected "..b)end
 local function test(name,fn)local good,res=pcall(fn) table.insert(report,{Name=name,Passed=good,Detail=good and (res or "Passed") or tostring(res)})end
 local function fixture()
  local e=E.new(C,91) local f=F.new(e,L,C) assert(f:Start("test")) return e,f,f:Profile("test"),e.Accounts[f:Owner("test")]
 end
 local function fill(e,a,key,side,price,qty)
  e.NextTrade+=1 e:_fillAccount({Id=e.NextTrade,Owner=a.Id,Contract=key,Direction=side,Remaining=qty or 1,Filled=0,Notional=0,Reference=price/e.Books[key].Spec.Tick},price,qty or 1,e.NextTrade)
 end
 local function statAccount(e,id,rows)
  local a=e:AddAccount(id,5000,5,.8,true)
  for i,row in ipairs(rows)do row.TradeId=i S.Add(a.Stats,row) a.Realized+=row.Pnl a.Balance+=row.Pnl a.CompletedTrades=(a.CompletedTrades or 0)+1 end
  return a
 end
 test("Projected rising/falling P&L, multiple instruments, loss, closure without double counting",function()
  local e,f,p,a=fixture()
  fill(e,a,"BX",1,5825,1) fill(e,a,"BT",-1,20000,1)
  e.Books.BX.Last=5827/.25 e.Books.BT.Last=20002/.25
  local n=f:View("test").Next near(n.Progress,0) near(n.EligibleOpen,60) near(n.Projected,60)
  e.Books.BX.Last=5823/.25 n=f:View("test").Next near(n.Projected,-140)
  e.Books.BX.Last=5900/.25 n=f:View("test").Next assert(n.Projected>3000)
  f:Evaluate("test") assert(not p.Tiers.F10K,"Unrealized profit unlocked a tier")
  e.Books.BX.Last=5827/.25
  fill(e,a,"BX",-1,5827,1)
  n=f:View("test").Next near(n.Progress,100) near(n.EligibleOpen,-40) near(n.Projected,60)
  fill(e,a,"BT",1,20002,1)
  n=f:View("test").Next near(n.Progress,60) near(n.EligibleOpen,0) near(n.Projected,60)
 end)
 test("Copy accounts and account switching count each eligible attempt once",function()
  local e,f,p,a=fixture() a.Realized=3000 a.Balance=8000 f:Evaluate("test") assert(f:Activate("test","F10K"))
  assert(f:SetCopy("test",{Enabled=1,Leader="F10K",Followers="F5K",Sizing="Same"}))
  local b=e.Accounts[p.Tiers.F10K.Account]
  fill(e,a,"BX",1,5825,1) fill(e,b,"BX",1,5825,1) e.Books.BX.Last=5827/.25
  table.insert(p.Ledger,a.Id) -- corrupt duplicate must not double-count a real attempt
  local n=f:View("test").Next near(n.Projected,n.Progress+200)
  local before=n.Projected assert(f:Select("test","F5K")) near(f:View("test").Next.Projected,before)
  assert(f:Select("test","F10K")) near(f:View("test").Next.Projected,before)
  assert(f:View("test").UsableCount==2)
 end)
 test("Re-earn exclusion and write-offs do not project ineligible open profit",function()
  local e,f,p,a=fixture() a.Realized=3000 a.Balance=8000 f:Evaluate("test") assert(f:Activate("test","F10K"))
  local b=e.Accounts[p.Tiers.F10K.Account] b.Locked=true b.Depleted=true b.Balance=0 b.Realized=-10000
  f:Evaluate("test") assert(p.Tiers.F10K.Reearn and p.Tiers.F10K.State=="Locked")
  fill(e,a,"BX",1,5825,1) e.Books.BX.Last=5895/.25
  b.Positions.BX={Direction=1,Quantity=1,Entry=5800} -- excluded even while old liquidation remains
  local n=f:View("test").Next near(n.Progress,0) near(n.Projected,3500)
  f:Evaluate("test") assert(p.Tiers.F10K.State=="Locked")
  b.Positions={} fill(e,a,"BX",-1,5885,1) f:Evaluate("test") assert(p.Tiers.F10K.State=="Unlocked")
  assert(f:View("test").UsableCount==1)
 end)
 test("Six metrics: UTC boundaries, break-even days, >100% best day and same-day account aggregation",function()
  local e=E.new(C,91) local d=DateTime.fromUniversalTime(2026,9,27).UnixTimestamp
  local a=statAccount(e,"a",{{Pnl=300,ClosedAt=d+86399},{Pnl=-100,ClosedAt=d+1},{Pnl=-50,ClosedAt=d+86400},{Pnl=0,ClosedAt=d+172800}})
  local x=S.Finish(S.Include(S.Empty(),e,a))
  near(x.Net,150) near(x.WinRate,.25) near(x.AvgWin,300) near(x.AvgLoss,75) near(x.WinLossRatio,4)
  near(x.ProfitFactor,2) near(x.DayWinRate,1/3) near(x.BestDayShare,200/150) assert(x.DayCount==3)
  local b=statAccount(e,"b",{{Pnl=-250,ClosedAt=d+4}})
  local combined=S.Finish(S.Include(S.Include(S.Empty(),e,a),e,b))
  near(combined.Net,-100) assert(combined.DayCount==3 and combined.DayWinRate==0 and combined.BestDayShare==nil)
 end)
 test("Empty, breakeven-only, no losses, no wins and negative denominators",function()
  local e=E.new(C,91) local d=os.time()
  local function stats(id,values)local rows={} for _,v in ipairs(values)do table.insert(rows,{Pnl=v,ClosedAt=d})end return S.Finish(S.Include(S.Empty(),e,statAccount(e,id,rows)))end
  local zero=stats("zero",{}) assert(zero.WinRate==nil and zero.ProfitFactor==nil and zero.DayWinRate==nil and zero.BestDayShare==nil)
  local even=stats("even",{0}) near(even.WinRate,0) near(even.DayWinRate,0) assert(even.WinLossRatio==nil and not even.NoLosses and even.BestDayShare==nil)
  local gain=stats("gain",{100,200}) assert(gain.NoLosses and gain.ProfitFactor==nil) near(gain.BestDayShare,1)
  local loss=stats("loss",{-100}) near(loss.ProfitFactor,0) near(loss.WinLossRatio,0) assert(loss.BestDayShare==nil)
 end)
 test("Undated old history preserved; Dated scope uses one filter for all six cards",function()
  local e=E.new(C,91) local a=statAccount(e,"old",{{Pnl=800},{Pnl=-200},{Pnl=100,ClosedAt=os.time()}})
  local x=S.Finish(S.Include(S.Empty(),e,a)) near(x.Net,700) assert(x.UndatedTrades==2 and not x.DailyComplete and x.DayWinRate==nil and x.BestDayShare==nil)
  near(x.Dated.Net,100) near(x.Dated.WinRate,1) near(x.Dated.DayWinRate,1) near(x.Dated.BestDayShare,1) assert(x.Dated.AllTrades==1)
 end)
 test("Daily migration is additive, idempotent and survives trimmed history + checkpoint JSON",function()
  local e=E.new(C,91) local a=statAccount(e,"old",{{Pnl=100,ClosedAt=os.time()},{Pnl=-20}})
  a.History={{TradeId=2,Pnl=-20},{TradeId=1,Pnl=100,ClosedAt=os.time()}}
  a.Stats.DayV=nil a.Stats.Days=nil S.Reconcile(e,a,os.time()) S.Reconcile(e,a,os.time())
  local x=S.Finish(S.Include(S.Empty(),e,a)) near(x.Net,80) near(x.Dated.Net,100) assert(x.UndatedTrades==1)
  for i=3,90 do S.Add(a.Stats,{TradeId=i,Pnl=1,ClosedAt=os.time()}) a.Realized+=1 a.Balance+=1 a.CompletedTrades+=1 end
  a.History={} local h=game:GetService("HttpService") a.Stats=h:JSONDecode(h:JSONEncode(a.Stats))
  S.Reconcile(e,a,os.time()) x=S.Finish(S.Include(S.Empty(),e,a)) near(x.Dated.Net,188) assert(x.Dated.Trades==89 and x.DayCount==1 and x.UndatedTrades==1)
 end)
end)
server:Destroy()
if not ok then error(err)end
return report
