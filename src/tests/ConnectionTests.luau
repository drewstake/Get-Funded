-- Detached exchanges, fake clocks/transfers, and pure client state only. No real teleports or saves.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Status=require(game.ReplicatedStorage.MarketReign.ConnectionStatus)
local Client=require(game.ReplicatedStorage.MarketReign.MarketClient)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local Admission=require(script.Parent.AccountAdmission)
local Router=require(script.Parent.ExchangeRouter)
local Settings=require(script.Parent.WorldConfig)
local World=require(script.Parent.WorldService)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Participants=require(script.Parent.Participants)
local Tests={}
local function exchange()
 local e=E.new(C,991);local allowed=true
 local f=F.new(e,L,C,{Capacity=function()return allowed end})
 return e,f,function(value)allowed=value end
end
local function fixture()
 local f={Time=0,Wall=100,Mode="Following",Present={a=true,b=true},Calls={},Jobs={}}
 f.Owner={WorldId="one-world",Owner="lease-token",Generation=1,PlaceId=123,JobId="owner",LeaseUntil=10000}
 f.Options={Now=function()return f.Time end,WallTime=function()return f.Wall end,JobId="follower",Studio=false,
  Owner=function()return f.Owner end,Mode=function()return f.Mode end,Connected=function(player)return f.Present[player]==true end,
  Spawn=function(fn)table.insert(f.Jobs,fn)end,Teleport=function(player,target,attempt)table.insert(f.Calls,{Player=player,Target=target,Attempt=attempt})end}
 f.Router=Router.new(Settings,f.Options)
 function f:Flush()local jobs=self.Jobs;self.Jobs={};for _,fn in ipairs(jobs)do fn()end end
 function f:Step(player)self.Router:Step(player or "a");self:Flush()end
 function f:Fail(result,index)
  local call=self.Calls[index or #self.Calls]
  return self.Router:Failed(call.Player,result,call.Target.PlaceId,call.Target.JobId,call.Attempt)
 end
 return f
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(r)})end
 test("Rejected Join preserves the capacity reason and creates no profile, funds or journal",function()
  local e,f,allow=exchange();allow(false);local p,reason=f:Join("new")
  assert(not p and reason:find("capacity",1,true));assert(not next(e.Profiles)and #e.AccountOrder==0 and not e.RequestJournal);e:Audit()
 end)
 test("Existing players reconnect at capacity without grants or a new run",function()
  local e,f,allow=exchange();local p=f:Join("existing");local id=p.Account;allow(false)
  local state={Uid="existing"};assert(Admission.Resolve(f,state,0,Settings)==p and not state.Admission)
  assert(f:Join("existing")==p and p.Run==1 and #p.Ledger==1 and e.Accounts[id].Balance==L.StartingBalance);e:Audit()
 end)
 test("Account admission retries are bounded and repeated clicks cannot bypass cooldown",function()
  local e,f,allow=exchange();allow(false);local state={Uid="new"};local now=0
  for i=1,Settings.ConnectionAttempts do
   assert(not Admission.Resolve(f,state,now,Settings));assert(state.Admission.Attempts==i)
   for _=1,20 do assert(not Admission.Retry(state,now,Settings));Admission.Resolve(f,state,now,Settings)end
   assert(state.Admission.Attempts==i);now=state.Admission.NextAt
  end
  Admission.Resolve(f,state,now+1000,Settings);assert(state.Admission.Attempts==Settings.ConnectionAttempts)
  local info=Admission.Status(state,now,Settings);assert(info.Code=="AccountCapacity"and info.CanRetry and not info.AutoRetry)
  assert(not next(e.Profiles)and #e.AccountOrder==0 and not e.RequestJournal)
  allow(true);assert(Admission.Retry(state,now,Settings));local p=Admission.Resolve(f,state,now,Settings)
  assert(p and not state.Admission and p.Run==1 and #p.Ledger==1)
  assert(Admission.Resolve(f,state,now,Settings)==p and e.Accounts[p.Account].Balance==10000);e:Audit()
 end)
 test("Temporary account errors receive bounded neutral feedback",function()
  local state={Uid="new"};local funded={Profile=function()end,Join=function()error("internal detail")end}
  assert(not Admission.Resolve(funded,state,0,Settings));local info=Admission.Status(state,0,Settings)
  assert(info.Code=="AccountUnavailable"and info.Attention and not info.Message:find("internal",1,true))
 end)
 test("Real storage thresholds reject only new admission and recover below the boundary",function()
  for _,field in ipairs({"LastRawBytes","LastStoredBytes"})do
   local world=setmetatable({Settings=Settings},World) -- No Open, store, lease or live data.
   local e=E.new(C,992);local f=F.new(e,L,C,{Capacity=function(kind)return world:HasCapacity(kind)end})
   local existing=f:Join("existing");local limit=(field=="LastRawBytes"and Checkpoint.MaxDecodedBytes or Settings.MaxEncodedBytes)*Settings.NewAccountCapacityFraction
   world[field]=limit;local state={Uid="new"}
   assert(not Admission.Resolve(f,state,0,Settings)and Admission.Status(state,0,Settings).Code=="AccountCapacity")
   assert(not f:Profile("new")and Admission.Resolve(f,{Uid="existing"},0,Settings)==existing)
   world[field]=limit-1;assert(Admission.Retry(state,state.Admission.NextAt,Settings))
   local p=Admission.Resolve(f,state,100,Settings);assert(p and #p.Ledger==1 and p.Run==1)
   assert(e.Accounts[existing.Account].Balance==L.StartingBalance);e:Audit()
  end
 end)
 test("Account-count rejection survives checkpoint restore without granting or replacing saved accounts",function()
  local config=table.clone(C);config.BotPopulation=nil
  local limits=table.clone(L);limits.AccountLimits={MaxExchangeAccounts=1}
  local e=E.new(config,993);local f=F.new(e,limits,config);local p=f:Join("existing");local id=p.Account
  local state={Uid="new"};assert(not Admission.Resolve(f,state,0,Settings))
  local population=setmetatable({Engine=e,Config=config,Random=Participants.RNG.new(993),Agents={}},Participants)
  local restored=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(Checkpoint.Capture(e,population))),config)
  local recovered=F.new(restored,limits,config);local old=Admission.Resolve(recovered,{Uid="existing"},0,Settings)
  assert(old.Account==id and old.Run==1 and #old.Ledger==1 and restored.Accounts[id].Balance==L.StartingBalance)
  assert(not Admission.Resolve(recovered,{Uid="new"},0,Settings)and not recovered:Profile("new")and #restored.AccountOrder==1)
  restored:Audit()
 end)
 test("Only the current server-owned destination is used; in-flight retries do not duplicate it",function()
  local f=fixture();f:Step();for _=1,20 do f:Step();assert(not f.Router:Retry("a"))end
  assert(#f.Calls==1 and f.Calls[1].Target.JobId=="owner"and f.Calls[1].Target.PlaceId==123)
  assert(f.Router:Status("a").Code=="Transferring")
 end)
 test("Full server has honest limited-launch messaging, bounded backoff and manual recovery",function()
  local f=fixture()
  for i=1,Settings.ConnectionAttempts do
   f:Step();assert(#f.Calls==i);assert(f:Fail("GameFull"))
   local info=f.Router:Status("a");assert(info.Code=="ServerFull"and info.Message:find("60",1,true)and info.Attention and not info.CanRetry)
   assert(info.RetryAfter>=Settings.ConnectionFullRetrySeconds)
   for _=1,10 do assert(not f.Router:Retry("a"));f:Step()end
   assert(#f.Calls==i);f.Time=f.Router.States.a.NextAt
  end
  f.Time+=1000;f:Step();assert(#f.Calls==Settings.ConnectionAttempts)
  local info=f.Router:Status("a");assert(info.CanRetry and not info.AutoRetry and info.Detail:find("stopped",1,true))
  assert(f.Router:Retry("a"));f:Flush();assert(#f.Calls==4)
  f.Present.a=false;f.Router:Forget("a");assert(not f.Router.States.a)
 end)
 test("Thrown transfer errors back off without exposing private errors",function()
  local f=fixture();f.Options.Teleport=function()error("secret transport diagnostics")end
  f:Step();local info=f.Router:Status("a");assert(info.Code=="TransferFailed"and info.RetryAfter==15 and not info.Message:find("secret",1,true))
  f.Time=15;f:Step();assert(f.Router:Status("a").RetryAfter==30)
 end)
 test("Delayed failure events match attempt, place and job, not options object identity",function()
  local f=fixture();f:Step();local p=f.Router.States.a.Pending
  assert(not f.Router:Failed("a","GameFull",123,"owner","stale"))
  assert(not f.Router:Failed("a","GameFull",999,"owner",p.Id))
  assert(not f.Router:Failed("a","GameFull",123,"other",p.Id))
  assert(f.Router.States.a.Pending==p and f:Fail("GameFull"));assert(not f:Fail("GameFull"))
 end)
 test("Owner changes reset routing and late failures cannot cancel the new transfer",function()
  local f=fixture();f:Step();f.Owner=table.clone(f.Owner);f.Owner.Generation=2;f.Owner.JobId="new-owner";f.Time=1
  f:Step();assert(#f.Calls==2 and f.Calls[2].Target.JobId=="new-owner")
  assert(not f:Fail("GameFull",1)and f.Router:Status("a").Code=="Transferring")
 end)
 test("Expired ownership waits safely and a renewed destination can be joined",function()
  local f=fixture();f:Step();f.Owner.LeaseUntil=f.Wall;f.Time=1;f:Step()
  assert(#f.Calls==1 and f.Router:Status("a").Code=="WaitingOwner"and not f.Router.States.a.Pending)
  f.Owner.LeaseUntil=f.Wall+90;f:Step();assert(#f.Calls==2)
 end)
 test("Missing, self and malformed destinations never trigger a transfer",function()
  for _,value in ipairs({{JobId=""},{JobId="follower"},{PlaceId=0},{LeaseUntil=0/0},{LeaseUntil=math.huge},{Generation="invalid"},{WorldId=false}})do
   local f=fixture();for k,v in pairs(value)do f.Owner[k]=v end;f:Step();assert(#f.Calls==0 and f.Router:Status("a").Code=="WaitingOwner")
  end
  local f=fixture();f.Owner=nil;f:Step();assert(#f.Calls==0)
 end)
 test("Studio never teleports and explains another active test",function()
  local f=fixture();f.Options.Studio=true;f:Step();assert(#f.Calls==0 and f.Router:Status("a").Code=="StudioTransfer")
 end)
 test("Unavailable or locally owned worlds stop routing and reject old callbacks",function()
  local f=fixture();f:Step();f.Mode="Shared";f:Step();assert(not f.Router.States.a and not f:Fail("GameFull"))
  f.Mode="Unavailable";f:Step();assert(#f.Calls==1 and not f.Router.States.a)
 end)
 test("Disconnect before a scheduled transfer cancels work and releases routing state",function()
  local f=fixture();f.Router:Step("a");f.Present.a=false;f.Router:Forget("a");f:Flush()
  assert(#f.Calls==0 and not next(f.Router.States));f.Router:Step("a");assert(not next(f.Router.States))
 end)
 test("Returned transfers without completion are recovered by the timeout watchdog",function()
  local f=fixture();f:Step();f.Time=Settings.ConnectionAttemptSeconds;f:Step()
  assert(f.Router:Status("a").Code=="TransferDelayed"and not f.Router.States.a.Pending)
  f.Time=f.Router.States.a.NextAt;f:Step();assert(#f.Calls==2)
 end)
 test("Already-teleporting signals wait for completion instead of starting another transfer",function()
  local f=fixture();f:Step();assert(f:Fail("IsTeleporting"));f.Time=20;f:Step()
  assert(#f.Calls==1 and f.Router.States.a.Pending and f.Router:Status("a").Code=="Transferring")
 end)
 test("A yielding transfer never overlaps another call or accepts a manual retry",function()
  local f=fixture();f.Options.Teleport=function()coroutine.yield()end
  f.Router:Step("a");local thread=coroutine.create(table.remove(f.Jobs,1));assert(coroutine.resume(thread))
  f.Time=100;f.Router:Step("a");assert(f.Router:Status("a").Code=="TransferDelayed"and not f.Router:Retry("a")and #f.Jobs==0)
  assert(coroutine.resume(thread));f.Router:Step("a");assert(not f.Router.States.a.Pending)
 end)
 test("A failure event during a yielding transfer cannot release its in-flight guard",function()
  local f=fixture();f.Options.Teleport=function(player,target,attempt)
   table.insert(f.Calls,{Player=player,Target=target,Attempt=attempt});coroutine.yield()
  end
  f.Router:Step("a");local thread=coroutine.create(table.remove(f.Jobs,1));assert(coroutine.resume(thread))
  assert(f:Fail("GameFull"));f.Time=1000;f.Router:Step("a")
  assert(#f.Jobs==0 and #f.Calls==1 and not f.Router:Retry("a"),'Failure event started an overlapping transfer')
  assert(not f.Router:Status("a").CanRetry)
  assert(coroutine.resume(thread));assert(f.Router:Status("a").Code=="ServerFull")
  f.Time=f.Router.States.a.NextAt;f.Router:Step("a");assert(#f.Jobs==1)
 end)
 test("Temporary ownership-mode changes retain a yielding transfer's guard",function()
  local f=fixture();f.Options.Teleport=function()coroutine.yield()end
  f.Router:Step("a");local thread=coroutine.create(table.remove(f.Jobs,1));assert(coroutine.resume(thread))
  f.Mode="Unavailable";f.Router:Step("a")
  f.Mode="Following";f.Time=1000;f.Router:Step("a")
  assert(#f.Jobs==0 and not f.Router:Retry("a"),'Mode change started an overlapping transfer')
  assert(coroutine.resume(thread));f.Router:Step("a");assert(not f.Router.States.a.Pending)
 end)
 test("Follower-wide dispatch pacing prevents a burst from many players",function()
  local f=fixture();f.Router:Step("a");f.Router:Step("b");f:Flush();assert(#f.Calls==1)
  f.Time=Settings.ConnectionRouteSpacingSeconds;f:Step("b");assert(#f.Calls==2)
 end)
 test("Unauthorized destinations stop automatic retries until an explicit retry",function()
  local f=fixture();f:Step();assert(f:Fail("Unauthorized"));f.Time=1000;f:Step()
  local info=f.Router:Status("a");assert(#f.Calls==1 and info.Code=="TransferUnavailable"and info.CanRetry and not info.AutoRetry)
 end)
 test("Account-less status clears stale balances, permissions, tokens and pending requests",function()
  local s={Ready=true,CanTrade=true,NextId=10,AccountToken="old",AccountKey="old",Portfolio={},Positions={BX={}},Orders={1},History={1},Fills={1},RequestSession=2,Capacity={BX={Buy=10}},Pending={[1]=0},PreferencesPending={}}
  Status.Apply(s,{StatusOnly=true,NoAccount=true,CanTrade=true,ConnectionInfo={Code="AccountCapacity"},ConnectionStatus="At capacity"})
  assert(not s.Ready and not s.CanTrade and not s.AccountToken and not s.Portfolio and not s.RequestSession and not s.Capacity)
  assert(not next(s.Positions)and not next(s.Orders)and not next(s.Pending)and s.SummaryData.Balance==0)
  Status.Apply(s,{CanTrade=true,RequestSession=3,RequestHigh=11});assert(s.CanTrade and s.RequestSession==3 and s.NextId==11 and not s.ConnectionInfo)
 end)
 test("Retry is allowed while trading is disabled, but trading requests stay blocked",function()
  local s=Client.New(10000,true);s.Preview=false;s.CanTrade=false;s.Remote={FireServer=function(_,request)s.LastSent=request end}
  assert(not s:Send("Place",{Contract="BX",Quantity=1,Direction=1,Type="Market"}))
  assert(s:RetryConnection()and s.LastSent.Action=="RetryConnection");assert(not s:RetryConnection());s:Destroy()
 end)
 test("Waiting UI distinguishes automatic checks from manual retry and fits small screens",function()
  local a=Status.View({Title="The trading server is full",RetryAfter=30,CanRetry=false,AutoRetry=true,Attention=true})
  assert(a.Attention and not a.Enabled and a.Button=="Checking again in 30s")
  assert(Status.View({CanRetry=true,RetryAfter=0}).Enabled)
  for _,size in ipairs({{320,568},{360,640},{667,280},{1920,1080}})do
   local box=Status.Layout(size[1],size[2]);assert(box.X>=0 and box.X+box.Width<=size[1])
   assert(box.Top>=0 and box.Top+312<=box.ContentHeight and box.ContentHeight>=size[2])
  end
 end)
 return rows
end
return Tests
