local Liquidity=require(script.Parent.TestLiquidity)
-- Isolated engines and injected stores only; never accesses real player saves.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local W=require(script.Parent.WorldService)
local Command=require(script.Parent.OwnerResetCommand)
local Ranking=require(script.Parent.LeaderboardRanking)
local Leaderboards=require(script.Parent.LeaderboardService)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function same(a,b)
 assert(type(a)==type(b),"Type differs")
 if type(a)~="table"then assert(a==b,tostring(a).." ~= "..tostring(b));return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Added "..tostring(k))end
end
local function fresh()
 local e=E.new(C,412);local f=F.new(e,L,C);f:Join("101");f:Join("102")
 local p=setmetatable({Engine=e,Config=C,Random=P.RNG.new(412),Agents={}},P)
 return e,f,p
end
local function trade(e,id,pnl)
 for _,owner in ipairs(e.AccountOrder)do e:CancelAll(owner,"BX")end -- Do not orphan live reserve orders when replacing this fixture's book.
 local b=e.Books.BX;b.Last=24000;b.Reference=24000;b.Bids={};b.Asks={}
 b.FairReference=b.Last
 Liquidity.Offer(e,"BX",-1,100,b.Last*b.Spec.Tick) -- Preserve depth around the one-contract accounting fixture.
 assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
 e:CancelAll("fixture:liquidity:BX:-1","BX")
 b.Last+=pnl/(b.Spec.Multiplier*b.Spec.Tick)
 b.FairReference=b.Last;Liquidity.Offer(e,"BX",1,100,b.Last*b.Spec.Tick)
 assert(Liquidity.Submit(e,id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
 Liquidity.Offer(e,"BX",-1,100,(b.Last+1)*b.Spec.Tick)
 e:Audit()
end
local function store()
 local s={}
 function s:UpdateAsync(_,callback)
  if self.BeforeWrite then self.BeforeWrite()end
  if self.Fail then error("Injected write failure")end
  local v=callback(clone(self.Value));if v then self.Value=clone(v)end
  if self.LostReply then error("Injected lost commit response")end
  return clone(v)
 end
 function s:GetAsync()return clone(self.Value)end
 return s
end
local function world()
 local c=table.clone(C);c.WarmupSeconds=0
 local s=store();local w=W.new(c,{Studio=false,PlaceId=123,JobId="reset-test",CanOwn=true,Store=s,Now=function()return 1000 end})
 w.CaptureProjection=function(e)return Ranking.Capture(F.new(e,L,c))end
 w:Open();assert(w:CanRun(),w.LastError)
 local f=F.new(w.Engine,L,c);f:Join("101");f:Join("102");trade(w.Engine,f:Owner("101"),500)
 assert(w:Save(false));return w,s
end
local function clean(e,uid)
 local f=F.new(e,L,C);local p=f:Profile(uid);local a=e.Accounts[p.Account]
 assert(a.Balance==10000 and a.Realized==0 and a.CashFlow==0 and a.Base==10000)
 assert(a.Stats.Trades==0 and a.Stats.Wins==0 and not next(a.Stats.Days))
 assert(#a.History==0 and #a.Fills==0 and not next(a.Positions)and not next(a.OpenOrders))
 assert(#p.Ledger==1 and #p.Titles==0 and not next(p.Awards)and #p.RunHistory==0)
 assert(p.ProfitHigh==0 and p.RankId==L.Ranks[1].Id and p.Tutorial=="Pending")
 assert(not p.ProtectionPreferences and not p.LegacyProfile and not p.Migration and not p.LegacyProgression)
 assert(#p.Events==0 and not next(p.Limits));assert(not Ranking.Row(f,uid).Eligible)
 e:Audit();return f,p,a
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,detail=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(detail or "Passed")or tostring(detail)})end
 test("Exact username parser rejects multi-target and malformed commands",function()
  assert(Command.Parse("/reset Trader_123")=="Trader_123")
  assert(Command.Parse("  /RESET @Trader_123  ")=="Trader_123")
  for _,v in ipairs({"/reset","/reset *","/reset User Other","/reset Display Name","/reset <User>","/reset abc;def","/reset "..string.rep("x",21),"/restart Trader"})do assert(not Command.Parse(v),v)end
 end)
 test("Authorization trusts only creator user id or actual group owner",function()
  assert(Command.IsOwner(7,Enum.CreatorType.User,7))
  assert(not Command.IsOwner(8,Enum.CreatorType.User,7))
  assert(not Command.IsOwner(-1,Enum.CreatorType.User,7))
  assert(Command.IsOwner(7,Enum.CreatorType.Group,50,function(id)assert(id==50);return {Owner={Id=7}}end))
  assert(not Command.IsOwner(8,Enum.CreatorType.Group,50,function()return {Owner={Id=7}}end))
  assert(not Command.IsOwner(7,Enum.CreatorType.Group,50,function()error("Unavailable")end))
  assert(not Command.IsOwner(7,Enum.CreatorType.Group,50,function()return {}end))
 end)
 test("Non-owner command cannot resolve a name or mutate a profile",function()
  local notices={};local cmd=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=7,
   Notify=function(_,message)table.insert(notices,message)end,Resolve=function()error("Lookup should not run")end,
   Reset=function()error("Reset should not run")end,Ready=function()error("Ready should not run")end})
  cmd:Handle({UserId=8},"/reset Trader");assert(#notices==1 and notices[1]:find("Only the experience owner"))
 end)
 test("Offline exact username resets once, with durable result before disconnect",function()
  local seen={}local now=10;local owner={UserId=7}
  local cmd=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=7,Now=function()return now end,Ready=function()return true end,
   Notify=function(_,message)table.insert(seen,message)end,Resolve=function(name)assert(name=="Trader");return 101,"Trader"end,
   Reset=function(uid,name)assert(uid==101 and name=="Trader");table.insert(seen,"saved");return true,"success"end,
   AfterReset=function(uid)assert(uid==101 and seen[#seen]=="success");table.insert(seen,"disconnect")end})
  cmd:Handle(owner,"/reset Trader");same(seen,{"Resetting @Trader...","saved","success","disconnect"})
  cmd:Handle(owner,"/reset Trader");assert(#seen==4)
 end)
 test("Display-name mismatch and lookup failure cannot choose a target",function()
  for _,lookup in ipairs({function()return 101,"DifferentName"end,function()error("No such username")end})do
   local message;local cmd=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=7,Ready=function()return true end,
    Notify=function(_,m)message=m end,Resolve=lookup,Reset=function()error("Must not reset")end})
   cmd:Handle({UserId=7},"/reset Trader");assert(message:find("Username not found")and not cmd.Busy)
  end
 end)
 test("Saved reset removes titles, rank, all histories, preferences and counters",function()
  local e,f=fresh();trade(e,f:Owner("101"),25000)
  local old=f:Profile("101");old.ProtectionPreferences={StopOn=true};old.Tutorial="Done";old.LegacyProfile={Wallet=123};old.Migration={};old.Limits.RestartAt=999
  old.LegacyProgression={Titles={"old"}};local token=old.Account
  f:ResetPlayer("101");local _,p=clean(e,"101");assert(p.Account~=token and p.Run==old.Run+1 and not e.Accounts[token])
 end)
 test("Open positions, armed stops and working limits settle without moving the market or another player",function()
  local e,f=fresh();trade(e,f:Owner("102"),500);local otherId=f:Owner("102")
  assert(Liquidity.Submit(e,otherId,{Contract="BT",Direction=-1,Quantity=1,Type="Market",StopTicks=50}))
  local id=f:Owner("101");trade(e,id,-250)
  assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=2,Type="Market",StopTicks=10,TargetTicks=20}))
  assert(Liquidity.Submit(e,id,{Contract="BT",Direction=1,Quantity=1,Type="Limit",Price=C.Contracts.BT.Last-100}))
  assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Stop",Price=e.Books.BX.Last*e.Books.BX.Spec.Tick+100}))
  table.insert(e.PendingStops,{Owner=id,Contract="BX",Position=e.Accounts[id].Positions.BX.Id})
  local other=clone(e.Accounts[otherId]);local profile=clone(f:Profile("102"));local books=clone(e.Books)
  -- The target's resting quantity must disappear; every other quote and the tape stay intact.
  for _,book in pairs(books)do for _,side in ipairs({book.Bids,book.Asks})do for i=#side,1,-1 do
   local level=side[i];local total=0
   for j=#level.Orders,1,-1 do if level.Orders[j].Owner==id then table.remove(level.Orders,j)else total+=level.Orders[j].Remaining end end
   level.Quantity=total;if total==0 then table.remove(side,i)end
  end end end
  local total,hash=e.TotalVolume,e.TradeHash
  f:ResetPlayer("101");clean(e,"101");same(e.Accounts[otherId],other);same(f:Profile("102"),profile);same(e.Books,books)
  assert(e.TotalVolume==total and e.TradeHash==hash and #e.PendingStops==0)
  for _,o in ipairs(e.OrderArchive)do assert(o.Owner~=id)end
  for _,o in pairs(e.Orders)do assert(o.Owner~=id)end
 end)
 test("Archived depleted runs and prefix-neighbor users stay isolated",function()
  local e,f=fresh();f:Join("1010");trade(e,f:Owner("101"),-10000)
  e:AdvanceClock(C.StepSeconds);f:Evaluate("101");assert(f:Restart("101",f:Owner("101")))
  local oldIds=clone(f:Profile("101").Ledger);local neighbor=clone(f:Profile("1010"))
  assert(#oldIds==2);f:ResetPlayer("101");clean(e,"101")
  for _,id in ipairs(oldIds)do assert(not e.Accounts[id])end;same(neighbor,f:Profile("1010"))
 end)
 test("Repeated resets survive checkpoint restore and retain unique request tokens",function()
  local e,f,p=fresh();local seen={}
  for _=1,3 do
   local id=f:Owner("101");assert(not seen[id]);seen[id]=true;trade(e,id,500);f:ResetPlayer("101")
   e,p=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),C);f=clean(e,"101")
   for token in pairs(seen)do assert(not e.Accounts[token])end
  end
 end)
 test("Transaction saves new profile and projection before replacing the live engine",function()
  local w,s=world();local original=w.Engine;local other=clone(original.Profiles["102"])
  s.BeforeWrite=function()assert(w.Engine==original and not w:CanRun()and w.Busy)end
  assert(w:TransformSaved(function(e)return F.new(e,L,C):ResetPlayer("101")end))
  assert(w.Engine~=original and w:CanRun()and not w.Busy);clean(w.Engine,"101");same(w.Engine.Profiles["102"],other)
  local restored=CP.Restore(CP.Decode(s.Value.Checkpoint),w.Config);clean(restored,"101")
  assert(#w.DurableProjection.Rows==0)
 end)
 test("Validation failure keeps the original engine and saved record intact",function()
  local w,s=world();local original=w.Engine;local record=clone(s.Value)
  assert(not w:TransformSaved(function(e)F.new(e,L,C):ResetPlayer("101");error("Injected validation failure")end))
  assert(w.Engine==original and w:CanRun()and not w.Busy);same(s.Value,record)
  assert(F.new(w.Engine,L,C):Earned(w.Engine.Profiles["101"])==500)
 end)
 test("Write failure pauses and reloads durable data without overwriting it",function()
  local w,s=world();local record=clone(s.Value);s.Fail=true
  assert(not w:TransformSaved(function(e)return F.new(e,L,C):ResetPlayer("101")end))
  assert(not w.Engine and not w:CanRun()and w.Mode=="Unavailable");same(s.Value,record)
  assert(not w:Save(false));s.Fail=false;w:Open();assert(w:CanRun())
  assert(F.new(w.Engine,L,C):Earned(w.Engine.Profiles["101"])==500)
 end)
 test("Lost commit response recovers the saved wipe instead of restoring old progress",function()
  local w,s=world();s.LostReply=true
  assert(not w:TransformSaved(function(e)return F.new(e,L,C):ResetPlayer("101")end))
  assert(not w:CanRun()and not w.Engine);s.LostReply=false;w:Open();assert(w:CanRun());clean(w.Engine,"101")
 end)
 test("Busy, follower and unsaved worlds reject resets before mutation",function()
  local w=world();local function unexpected()error("Must not mutate")end
  w.Busy=true;assert(not w:TransformSaved(unexpected));w.Busy=false
  w.Mode="Following";assert(not w:TransformSaved(unexpected));w.Mode="Local";assert(not w:TransformSaved(unexpected))
 end)
 test("Leaderboard drops wiped scores immediately and persists the newer projection",function()
  local w=world();local s=store();local lb=Leaderboards.new({Store=s,Now=function()return 1000 end})
  lb:Queue(w.DurableProjection);assert(lb:Flush()and #s.Value.Rows==1)
  assert(w:TransformSaved(function(e)return F.new(e,L,C):ResetPlayer("101")end))
  lb:UseDurableProjection(w.DurableProjection);assert(#lb.Cache.Rows==0)
  s.Fail=true;lb.NextWrite=0;assert(not lb:Flush()and #lb.Cache.Rows==0)
  s.Fail=false;lb.NextWrite=0;assert(lb:Flush()and #s.Value.Rows==0)
 end)
 return rows
end
return Tests
