local Liquidity=require(script.Parent.TestLiquidity)
-- Disposable engines, real executions and in-memory checkpoint/store roundtrips only.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Rules=require(game.ReplicatedStorage.MarketReign.ProgressionRules)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local CP=require(script.Parent.WorldCheckpoint)
local P=require(script.Parent.Participants)
local Ranking=require(script.Parent.LeaderboardRanking)
local Service=require(script.Parent.LeaderboardService)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function same(a,b)
 assert(type(a)==type(b),"Type differs")
 if type(a)~="table"then assert(a==b,tostring(a).." != "..tostring(b));return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Missing "..k)end
end
local function fresh(uid)
 local c=clone(C);c.WarmupSeconds=0;local e=E.new(c,731);local f=F.new(e,L,c)
 if uid then f:Join(uid)end;return e,f
end
local function result(e,id,amount)
 local b=e.Books.BX;b.Last=math.max(24000,math.ceil(math.abs(amount)/(b.Spec.Multiplier*b.Spec.Tick))+100);b.Reference=b.Last;b.Bids={};b.Asks={}
 assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
 b.Last+=amount/(b.Spec.Multiplier*b.Spec.Tick)
 assert(Liquidity.Submit(e,id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
 e:AdvanceClock(C.StepSeconds)
end
local function restore(e)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(731),Agents={}},P)
 local snapshot=CP.Encode(CP.Capture(e,pop));local r=CP.Restore(CP.Decode(snapshot),e.Config)
 return r,F.new(r,L,r.Config)
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,detail=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(detail)})end
 test("16 distinct titles and 8 monotonic rank gates share valid atlas cells",function()
  assert(#L.Milestones==16 and #L.Ranks==8);local seen={}
  for _,m in ipairs(L.Milestones)do assert(not seen[m.Title]and m.Badge>=1 and m.Badge<=16);seen[m.Title]=true end
  for i,r in ipairs(L.Ranks)do if i>1 then local p=L.Ranks[i-1];assert(r.Trades>p.Trades and r.Wins>=p.Wins and r.Profit>=p.Profit)end end
 end)
 test("Fresh account has rookie rank; starting cash, open profit and preferences award nothing",function()
  local e,f=fresh("101");local p=f:Profile("101");local v=f:View("101")
  assert(v.RankId=="Rookie"and v.Next.Key=="FirstTrade"and #v.Titles==0)
  assert(f:SetProtectionPreferences("101",{StopOn=true,TargetOn=false,StopDollars=500,TargetDollars=1500}))
  e.Books.BX.Last=24000;assert(Liquidity.Submit(e,p.Account,{Contract="BX",Direction=1,Quantity=1,Type="Market"}));e.Books.BX.Last+=80
  f:Evaluate("101");assert(not next(p.Awards)and p.RankId=="Rookie")
 end)
 test("Every title boundary and every combined rank gate is exact",function()
  for _,m in ipairs(L.Milestones)do
   local net,trades,wins=0,0,0
   if m.Kind=="Profit"then net=m.Goal-.01 elseif m.Kind=="Trades"then trades=m.Goal-1 else wins=m.Goal-1 end
   assert(Rules.Metric(m,net,trades,wins)<m.Goal)
   if m.Kind=="Profit"then net=m.Goal elseif m.Kind=="Trades"then trades=m.Goal else wins=m.Goal end
   assert(Rules.Metric(m,net,trades,wins)==m.Goal)
  end
  for _,r in ipairs(L.Ranks)do
   assert(Rules.Qualifies(r,r.Profit,r.Trades,r.Wins))
   if r.Trades>0 then assert(not Rules.Qualifies(r,r.Profit,r.Trades-1,r.Wins))end
   if r.Wins>0 then assert(not Rules.Qualifies(r,r.Profit,r.Trades,r.Wins-1))end
   if r.Profit>0 then assert(not Rules.Qualifies(r,r.Profit-.01,r.Trades,r.Wins))end
  end
 end)
 test("A quick $10k profit earns no titles or rank; sustained closes unlock the new gates",function()
  local e,f=fresh("101");local p=f:Profile("101")
  for _=1,10 do result(e,p.Account,1000)end
  assert(p.RankId=="Rookie"and not next(p.Awards)and f:Earned(p)==10000)
  for _=11,25 do result(e,p.Account,1000)end
  assert(p.RankId=="Apprentice"and p.Awards.FirstTrade and p.Awards.FirstWin and not p.Awards.Profit500)
  for _=26,100 do result(e,p.Account,1000)end
  assert(p.RankId=="Rising"and p.Awards.Profit500 and p.Awards.Trades5 and p.Awards.Profit2500)
  assert(p.Awards.Profit500.Goal==50000)
  local awards=clone(p.Awards);local ranks=clone(p.RankAwards)
  result(e,p.Account,-500);same(awards,p.Awards);same(ranks,p.RankAwards);assert(p.RankId=="Rising")
  for _=1,4 do f:Evaluate("101")end;same(awards,p.Awards)
  local seen={};for _,t in ipairs(p.Titles)do assert(not seen[t]);seen[t]=true end;e:Audit()
 end)
 test("All ranks and titles earned through 5000 executions survive depletion, restart and rejoin",function()
  local e,f=fresh("101");local p=f:Profile("101")
  for i=1,5000 do result(e,p.Account,i<=2500 and 2000 or 0)end
  assert(p.RankId=="Sovereign"and #p.Titles==16)
  local awards,ranks=clone(p.Awards),clone(p.RankAwards)
  result(e,p.Account,-5010000);assert(f:Restart("101",p.Account))
  assert(f:View("101").RankId=="Sovereign");e,f=restore(e);f:Join("101");p=f:Profile("101")
  same(awards,p.Awards);same(ranks,p.RankAwards);assert(#p.Titles==16 and p.RankId=="Sovereign")
  assert(e.Accounts[p.Account].Balance==260000 and f:Earned(p)==-10000);e:Audit()
 end)
 test("Legacy tier names normalize once; old awards, balances, history and protection remain intact",function()
  local e,f=fresh("101");local p=f:Profile("101");result(e,p.Account,5000)
  p.ProgressionVersion=nil;p.LegacyProgression=nil;p.RankId=nil;p.RankAwards=nil;p.Rank="Skilled Trader"
  p.Titles={"Legacy 5K Trader","10K Trader","Skilled Trader","Legacy Top Tier Complete","First Win"}
  p.Awards.Balance10K={At=123,Title="Skilled Trader",Net=5000};p.ProtectionPreferences={StopOn=false,TargetOn=true,StopDollars=200,TargetDollars=700}
  local account=clone(e.Accounts[p.Account]);local protection=clone(p.ProtectionPreferences)
  f=F.new(e,L,C);p=f:Profile("101");same(account,e.Accounts[p.Account]);same(protection,p.ProtectionPreferences)
  assert(p.Awards.Balance10K.At==123 and table.find(p.Titles,"Founding Trader")and table.find(p.Titles,"Momentum Maker"))
  for _,m in ipairs(f:View("101").Milestones)do if m.Key=="Balance10K"then assert(m.Earned and m.EarlierGoal and m.Goal==250000)end end
  for _,title in ipairs(p.Titles)do assert(not Rules.Obsolete(title))end
  assert(p.LegacyProgression.Titles[1]=="Legacy 5K Trader")
  local before=clone(p);f=F.new(e,L,C);same(before,f:Profile("101"));e,f=restore(e);same(before,f:Profile("101"))
 end)
 test("Server and Global projection preserve cents, ties, eligibility and permanent rank",function()
  local e,f=fresh("101");f:Join("102");f:Join("103")
  for _,uid in ipairs({"101","102"})do result(e,f:Owner(uid),500)end
  local rows=Ranking.Capture(f);assert(#rows==2 and rows[1].UserId==101 and rows[2].UserId==102)
  assert(rows[1].Rank==1 and rows[2].Rank==2 and rows[1].Cents==1050000 and rows[1].ProgressionRankId=="Rookie")
  local stored;local store={UpdateAsync=function(_,_,fn)stored=fn(stored);return stored end,GetAsync=function()return stored end}
  local service=Service.new({Store=store,Studio=true,Now=function()return 1000 end})
  service:Queue({WorldId="isolated",Sequence=1,SavedAt=1000,Rows=rows});assert(service:Flush())
  local global=service:Global(Ranking.Row(f,"101"));same(global.Rows,rows);assert(global.Your.Rank==1)
  local server=service:Server(f,{{UserId=101},{UserId=102},{UserId=103}},{UserId=101})
  assert(server.Rows[1].ProgressionRankId==global.Rows[1].ProgressionRankId and server.Your.Rank==1)
 end)
 test("Old and stale leaderboard snapshots retain scores without inventing progression ranks",function()
  local old={Version=1,WorldId="qa",Sequence=1,SavedAt=100,Rows={{UserId=101,Cents=90000,Eligible=true,Rank=1,Tier="10K Trader"}}}
  local service=Service.new({Store={GetAsync=function()return old end},Now=function()return 1000 end})
  local result=service:Global({UserId=101,Cents=90000,Eligible=true})
  assert(result.State=="Stale"and result.Rows[1].Cents==90000 and result.Rows[1].Rank==nil and result.Rows[1].ProgressionRankId==nil)
 end)
 return rows
end
return Tests
