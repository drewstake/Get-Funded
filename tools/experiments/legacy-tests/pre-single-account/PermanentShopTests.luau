-- Isolated regression fixtures. No live player data or real DataStore keys are touched.
local Tests={}
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local W=require(script.Parent.WorldService)
local Settings=require(script.Parent.WorldConfig)
local Ranking=require(script.Parent.LeaderboardRanking)
local function clone(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=clone(x) end return r end
local function equal(a,b,label) assert(a==b,(label or "value")..": "..tostring(a).." ~= "..tostring(b)) end
local function fresh(uid)
 local e=E.new(C,4821);local f=F.new(e,L,C);assert(f:Start(uid or "42"));return e,f,f:Profile(uid or "42")
end
local function profit(e,id,value)
 local a=e.Accounts[id];assert(not next(a.Positions),"Fixture needs flat account")
 local b=e.Books.BX;b.Bids={};b.Asks={};b.Last=24000;b.Reference=24000
 assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
 b.Last+=value/50/b.Spec.Tick
 assert(e:Submit(id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
 if a.Balance<=0 then a.Locked=true;a.Depleted=true end
 return a
end
local function roundtrip(e,f)
 local pop=P.new(e)
 local encoded=CP.Encode(CP.Capture(e,pop));local http=game:GetService("HttpService")
 local restored=CP.Restore(CP.Decode(http:JSONDecode(http:JSONEncode(encoded))),C)
 return restored,F.new(restored,L,C)
end
function Tests.Run()
 local report={};local function test(name,fn) local ok,detail=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=tostring(detail or "OK")}) end
 test("Fresh capital, activation and purchases are never qualifying profit or wallet income",function()
  local e,f,p=fresh();equal(p.WalletCents,0);equal(f:View("42").Next.Progress,0)
  assert(not f:Purchase("42","F5K",1));equal(#p.Ledger,1)
  profit(e,f:Owner("42"),3000);equal(p.WalletCents,300000);assert(p.Tiers.F10K)
  equal(f:View("42").Next.Progress,0);assert(f:Activate("42","F10K"));equal(p.WalletCents,300000)
  assert(f:Purchase("42","F5K",1));equal(p.WalletCents,100000);equal(f:View("42").Next.Progress,0)
  equal(f:Earned(p),3000);e:Audit()
 end)
 test("Open P&L previews then reconciles exactly once on closed fills",function()
  local e,f,p=fresh();local id=f:Owner("42");local b=e.Books.BX;b.Last=24000;b.Reference=24000
  assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}));b.Last+=240
  local v=f:View("42");equal(v.Next.Projected,3000);equal(v.Next.Progress,0);assert(not p.Tiers.F10K);equal(p.WalletCents,0)
  assert(e:Submit(id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
  v=f:View("42");assert(p.Tiers.F10K);equal(v.Next.Key,"F25K");equal(v.Next.Progress,0);equal(v.Next.Projected,0)
  f:Evaluate("42");equal(p.WalletCents,300000);e:Audit()
 end)
 test("Unlock occurs on each closed fill even before polling and never reverses after losses",function()
  local e,f,p=fresh();local id=f:Owner("42")
  profit(e,id,8000);assert(p.Tiers.F10K and p.Tiers.F25K)
  profit(e,id,-13000);f:Evaluate("42");assert(p.Tiers.F10K and p.Tiers.F25K)
  local v=f:View("42");equal(v.Next.Key,"F50K");equal(v.Next.Goal,10000);equal(v.Next.Progress,0)
  assert(f:Restart("42","F5K"));equal(f:View("42").Next.Progress,0)
  assert(not f:Restart("42","F5K"));profit(e,f:Owner("42"),500);equal(f:View("42").Next.Progress,500)
  equal(f:Earned(p),-4500);e:Audit()
 end)
 test("Requested migration: blown $5K/$10K/$25K, fresh $5K => $50K at $0 / $10,000",function()
  local e,f,p=fresh();profit(e,f:Owner("42"),8000);assert(f:Activate("42","F10K"));assert(f:Activate("42","F25K"))
  local old={};for _,entry in ipairs(f:Entries(p)) do old[entry.Tier]=entry.Account;profit(e,entry.Account,-e.Accounts[entry.Account].Balance) end
  f:Evaluate("42");assert(f:Restart("42","F5K"));local starter=f:Owner("42");local total=f:Earned(p)
  p.V=2;p.Instances=nil;p.ProgressState=nil;p.ProgressCredit=0;p.Active="F5K"
  p.Tiers.F5K={State="Active",Account=starter,Attempt=2}
  for _,tier in ipairs({"F10K","F25K"}) do p.Tiers[tier]={State="Locked",Account=old[tier],Attempt=1,Reearn={Goal=3000,Baseline={},Excluded={}},Announced=true} end
  p.Copy={Enabled=true,Leader="F10K",Followers={"F25K"},Sizing="Same"};p.WriteOffs={};p.Banked={};p.ResetV=1
  table.insert(p.Ledger,old.F10K)
  local migrated=F.new(e,L,C);local v=migrated:View("42")
  equal(v.UnlockedCount,3);equal(v.Next.Key,"F50K");equal(v.Next.Progress,0);equal(v.Next.Projected,0);equal(v.Next.Goal,10000)
  equal(#p.Ledger,4);equal(v.UsableCount,1);equal(v.BlownCount,3);equal(migrated:Earned(p),total);equal(p.WalletCents,0)
  assert(not p.Copy.Enabled);assert(not p.Tiers.F10K.Reearn)
  local e2,f2=roundtrip(e,migrated);equal(f2:View("42").Next.Key,"F50K");equal(f2:View("42").Next.Progress,0);equal(f2:Earned(f2:Profile("42")),total);e2:Audit()
 end)
 test("History alone recovers missing entitlement records and repeated migration is idempotent",function()
  local e,f,p=fresh();profit(e,f:Owner("42"),8000);assert(f:Activate("42","F25K"))
  p.Tiers.F25K=nil;p.Tiers.F10K=nil;p.V=2;p.ProgressState=nil;p.Instances=nil
  local f2=F.new(e,L,C);assert(p.Tiers.F10K and p.Tiers.F25K)
  local before=#p.Ledger;local wallet=p.WalletCents;F.new(e,L,C);equal(#p.Ledger,before);equal(p.WalletCents,wallet)
 end)
 test("Wallet rewards new closed-net highs only, never starting capital, open profit or recovered profit",function()
  local e,f,p=fresh();local id=f:Owner("42")
  profit(e,id,3000);assert(f:Purchase("42","F5K",1));equal(p.WalletCents,100000)
  profit(e,id,-1000);profit(e,id,1000);equal(p.WalletCents,100000)
  profit(e,id,500);equal(p.WalletCents,150000);equal(p.WalletEarnedCents,350000);equal(p.WalletSpentCents,200000)
  local e2,f2=roundtrip(e,f);equal(f2:Profile("42").WalletCents,150000);e2:Audit()
 end)
 test("Purchase validation, insufficient funds, invalid sequence, duplicate intent and reconnect replay",function()
  local e,f,p=fresh();assert(not f:Purchase("42","F100K",1));assert(not f:Purchase("42","F5K",0/0));assert(not f:Purchase("42","F5K",1))
  profit(e,f:Owner("42"),10000);local before=f:Earned(p);local progress=f:View("42").Next.Progress
  local ok,_,r=f:Purchase("42","F5K",1);assert(ok)
  for _=1,20 do local yes,_,duplicate=f:Purchase("42","F5K",1);assert(yes);equal(duplicate.Account,r.Account) end
  equal(#p.Ledger,2);equal(p.WalletCents,800000);assert(not f:Purchase("42","F10K",1));assert(not f:Purchase("42","F5K",3))
  equal(f:Earned(p),before);equal(f:View("42").Next.Progress,progress)
  local e2,f2=roundtrip(e,f);local q=f2:Profile("42");assert(f2:Purchase("42","F5K",1));equal(#q.Ledger,2);equal(q.WalletCents,800000)
  assert(f2:Purchase("42","F5K",2));equal(#q.Ledger,3);equal(q.WalletCents,600000);e2:Audit()
 end)
 test("Two same-tier accounts switch independently, copy exactly once and aggregate Stats once",function()
  local e,f,p=fresh();local first=f:Owner("42");profit(e,first,8000);local _,_,r=f:Purchase("42","F5K",1)
  local lead=e.Accounts[first].InstanceKey;local follow=r.Key
  assert(f:SetCopy("42",{Enabled=1,Leader=lead,Followers=follow..","..follow,Sizing="Same"}))
  local req={Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"};local plan=f:Plan("42",first);equal(#plan.Followers,1)
  local ok,res=F.Perform(e,first,req);assert(ok);local report=f:Mirror(plan,req,ok,res);equal(report.Copied,1)
  equal(e.Accounts[first].Positions.BX.Quantity,1);equal(e.Accounts[r.Account].Positions.BX.Quantity,1)
  assert(f:Select("42",follow));equal(f:Owner("42"),r.Account);assert(not f:Select("someone",follow))
  assert(not f:Select("42","L50000"));assert(not f:SetCopy("42",{Enabled=1,Leader=lead,Followers="foreign"}))
  e.Books.BX.Last+=40
  local v=f:View("42");local sv=require(game.ReplicatedStorage.MarketReign.StatsView)
  equal(sv.OpenFor({Key="F5K",Kind="Tier"},v),v.Open)
  local stats=f:Stats("42");equal(stats.Scopes[1].Life.Attempts,2);equal(stats.Scopes[1].Current.Attempts,2);equal(stats.Scopes[2].Current.Attempts,2)
  equal(stats.Scopes[1].Life.Net,8000);equal(Ranking.Row(f,"42").Cents,800000)
  assert(F.Perform(e,r.Account,{Action="Close",Contract="BX"}));assert(e.Accounts[first].Positions.BX);assert(not e.Accounts[r.Account].Positions.BX)
  e:Audit()
 end)
 test("Legacy positions/orders retire safely, cannot be selected/traded, funded history preserved",function()
  local e,f,p=fresh();local funded=f:Owner("42");profit(e,funded,1000)
  local old=e:AddAccount("player:42:50000",50000,40,.8,true)
  assert(e:Submit(old.Id,{Contract="BX",Direction=1,Quantity=2,Type="Market"}))
  assert(e:Submit(old.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=e.Books.BX.Last*e.Books.BX.Spec.Tick+100}))
  local f2=F.new(e,L,C);assert(old.LegacyRetired and old.Retired);assert(not next(old.Positions));assert(not next(old.OpenOrders))
  assert(not f2:Resolve("42","L50000"));assert(not e:Submit(old.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  equal(f2:Earned(p),1000);equal(#f2:View("42").Accounts,1);equal(f2:Stats("42").Scopes[1].Life.Attempts,1);e:Audit()
 end)
 test("Durable purchase: storage failure pauses, ambiguous commit retries once, reconnect retains account and debit",function()
  local saved={};local now=5000
  function saved:UpdateAsync(_,fn)
   if self.FailBefore then error("test storage outage") end
   local value=fn(clone(self.Value));if value then self.Value=clone(value) end
   if self.FailAfter then error("test lost commit response") end
   return clone(value)
  end
  local c=clone(C);c.WarmupSeconds=0
  local w=W.new(c,{Studio=false,PlaceId=123,JobId="shop-test",Store=saved,Now=function()return now end,CanOwn=true})
  w:Open();assert(w:CanRun());local f=F.new(w.Engine,L,c);assert(f:Start("42"));profit(w.Engine,f:Owner("42"),3000);assert(w:Save(false))
  saved.FailAfter=true;local replies=0
  assert(w:Purchase(f,"42","F5K",1,function(ok)assert(ok);replies+=1 end));assert(not w:CanRun())
  assert(not w:Purchase(f,"42","F5K",1,function()error("duplicate callback")end))
  task.wait();equal(replies,0);equal(#f:Profile("42").Ledger,2)
  saved.FailAfter=false;now+=Settings.RetrySeconds;w:Maintain();equal(replies,1);assert(w:CanRun())
  local snapshot=CP.Decode(saved.Value.Checkpoint);local e2=CP.Restore(snapshot,c);local f2=F.new(e2,L,c)
  equal(f2:Profile("42").WalletCents,100000);equal(#f2:Profile("42").Ledger,2);assert(f2:Purchase("42","F5K",1));equal(#f2:Profile("42").Ledger,2)
  equal(replies,1);e2:Audit()
 end)
 return report
end
return Tests
