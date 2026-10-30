-- Isolated engine fixtures; never reads/writes player DataStores.
local h=game:GetService("HttpService")
local server=game.ServerScriptService.MarketReign:Clone();server.Name="AccountCleanupChecks";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local report={Reset={},Regression={}}
local ok,err=pcall(function()
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local C=require(game.ReplicatedStorage.MarketReign.MarketConfig);local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
 local CP=require(server.WorldCheckpoint);local P=require(server.Participants)
 local function check(v,msg)assert(v,msg)end
 local function test(name,fn)local yes,why=pcall(fn);table.insert(report.Reset,{Name=name,Passed=yes,Detail=tostring(why or "OK")})end
 local function fresh()
  local e=E.new(C,1234);local f=F.new(e,L,C);f:Start("test");return e,f,f:Profile("test"),e.Accounts[f:Owner("test")]
 end
 local function profit(e,a,value)
  local b=e.Books.BX;b.Last=24000;b.Reference=24000;b.Bids={};b.Asks={}
  assert(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  b.Last+=value/50/b.Spec.Tick
  assert(e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
  if a.Balance<=0 then a.Locked=true;a.Depleted=true end
 end
 test("Healthy starter reset is a single fresh attempt; duplicate intent and Start cannot mint funds",function()
  local e,f,p,a=fresh();local key=p.Active
  check(f:View("test").Accounts[1].CanReset,"healthy reset missing")
  check(f:Restart("test",key),"reset rejected")
  local fresh=e.Accounts[f:Owner("test")];check(fresh.Balance==5000 and fresh.Realized==0,"fresh balance")
  for _=1,20 do check(not f:Restart("test",key),"duplicate intent accepted")end
  f:Start("test");check(#p.Ledger==2 and f:View("test").UsableCount==1,"duplicate account")
  check(a.Retired and a.Locked and a.InstanceKey==key,"original id mutated")
  check(p.WalletCents==0 and p.WalletEarnedCents==0 and f:StageProgress(p)==0 and not p.Tiers.F10K,"reset reward")
  check(not e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}),"retired account accepts entry")
  check(not f:TakeEvents("test"),"reset manufactured a depletion or reward event")
  e:Audit()
 end)
 test("Drawdown reset closes multiple protected positions and cancels limit/stop orders before restoring $5K",function()
  local e,f,p,a=fresh();profit(e,a,-500)
  for _,contract in ipairs({"BX","BT"})do
   check(e:Submit(a.Id,{Contract=contract,Direction=1,Quantity=1,Type="Market",StopTicks=100,TargetTicks=200}),"open protected")
  end
  local price=e.Books.BX.Last*e.Books.BX.Spec.Tick
  check(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=price-100}),"limit")
  check(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Stop",Price=price+100}),"stop")
  e.Books.BX.Last-=20
  local expected=a.Realized+e:Summary(a).Unrealized;local key=p.Active
  check(f:Restart("test",key),"drawdown reset rejected")
  check(not next(a.Positions) and not next(a.OpenOrders),"risk left on retired account")
  check(math.abs(a.Realized-expected)<.001,"settlement lost P&L")
  local current=e.Accounts[f:Owner("test")];check(current.Balance==5000 and not next(current.Positions) and not next(current.OpenOrders),"replacement state")
  local stats=f:Stats("test").Scopes[2];check(stats.Life.Attempts==2 and stats.Current.Attempts==1 and stats.Life.Net==a.Realized,"history lost")
  local balance=a.Balance;e.Books.BX.Last+=1000;e:ProcessStops();check(a.Balance==balance and not next(a.Positions),"cancelled orders revived")
  check(p.WalletCents==0 and f:StageProgress(p)==0,"drawdown generated reward")
  e:Audit()
 end)
 test("Other purchased/funded accounts, copy positions, earned balance and stage progress are preserved",function()
  local e,f,p,a=fresh();profit(e,a,8000);f:Activate("test","F10K")
  local other=e.Accounts[p.Tiers.F10K.Account];profit(e,other,500)
  local _,_,receipt=f:Purchase("test","F5K",1);local bought=e.Accounts[receipt.Account]
  check(f:SetCopy("test",{Enabled=1,Leader=a.InstanceKey,Followers=other.InstanceKey,Sizing="Same"}),"copy setup")
  local request={Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}
  local plan=f:Plan("test",a.Id);local yes,result=F.Perform(e,a.Id,request);f:Mirror(plan,request,yes,result)
  local held=other.Positions.BX;local wallet=p.WalletCents;local earned=p.WalletEarnedCents
  check(not f:Restart("test",receipt.Key),"purchased account can reset")
  check(not f:Restart("test",other.InstanceKey),"higher tier can reset")
  check(not f:Restart("stranger",a.InstanceKey),"foreign reset")
  check(not f:Restart("test","invalid"),"unknown reset")
  check(f:Restart("test",a.InstanceKey),"free reset with other active accounts")
  check(other.Positions.BX==held and bought.Balance==5000,"other accounts mutated")
  check(p.WalletCents==wallet and p.WalletEarnedCents==earned,"starting capital credited")
  check(f:StageProgress(p)==500 and p.Tiers.F10K and p.Tiers.F25K,"other progress/unlocks lost")
  check(not p.Copy.Enabled and not p.Copy.Leader,"copy still targets retired leader")
  e:Audit()
 end)
 test("Positive settlement rewards genuine close once; replay survives checkpoint/JSON round trip",function()
  local e,f,p,a=fresh();e.Books.BX.Last=24000
  check(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}),"entry")
  e.Books.BX.Last+=240;local key=p.Active
  check(f:Restart("test",key),"reset")
  check(a.Realized==3000 and p.WalletCents==300000 and p.Tiers.F10K,"settlement not accounted")
  local events=f:TakeEvents("test");check(events and #events==2,"expected genuine close events")
  local encoded=CP.Encode(CP.Capture(e,P.new(e)))
  local restored=CP.Restore(CP.Decode(h:JSONDecode(h:JSONEncode(encoded))),C);local f2=F.new(restored,L,C);local p2=f2:Profile("test")
  for _=1,10 do check(not f2:Restart("test",key),"replay accepted")end
  check(#p2.Ledger==2 and p2.WalletCents==300000 and f2:View("test").UsableCount==1,"replay duplication")
  check(not f2:TakeEvents("test"),"duplicate progression events")
  check(f2:Stats("test").Scopes[2].Life.Net==3000,"saved stats")
  restored:Audit()
 end)
 test("Failed settlement never creates fresh funds; safe retry settles remaining exposure",function()
  local e,f,p,a=fresh();check(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}),"entry")
  local submit=e.Submit;e.Submit=function()return false,"fixture unavailable"end
  check(not f:Restart("test",a.InstanceKey),"failed close accepted")
  check(#p.Ledger==1 and a.Positions.BX and not a.Retired and not p.Instances[a.InstanceKey].ResetTo,"partial reset retired risk")
  e.Submit=submit;check(f:Restart("test",a.InstanceKey),"retry")
  check(#p.Ledger==2 and not next(a.Positions),"retry settlement")
  e:Audit()
 end)
 test("No-account recovery and stale reset keys cannot produce parallel free accounts",function()
  local e,f,p,a=fresh();profit(e,a,-5000);f:Evaluate("test")
  check(f:CanRestart(p) and f:Restart("test",a.InstanceKey),"blown recovery")
  local nextAccount=e.Accounts[f:Owner("test")];profit(e,nextAccount,-5000);f:Evaluate("test")
  check(not f:Restart("test",a.InstanceKey) and #p.Ledger==2,"stale key minted another account")
  check(f:Restart("test",nextAccount.InstanceKey) and #p.Ledger==3,"latest blown restart")
  check(f:View("test").UsableCount==1,"extra free account")
  e:Audit()
 end)
 for _,name in ipairs({"PermanentShopTests","StatsTests","FundedTests","DepletionTests","ProgressionTests","TradeAmendmentTests","TradeLimitsTests","WorldTests","LeaderboardTests","MarketTests"})do
  local yes,result=pcall(function()local suite=require(server[name]);return type(suite)=="function" and suite() or suite.Run()end)
  report.Regression[name]=yes and result or {Error=tostring(result)}
 end
end)
server:Destroy()
if not ok then report.Error=tostring(err)end
h:PostAsync("http://127.0.0.1:8774/results",h:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return report
