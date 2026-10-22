-- Detached fixtures only: no Players, real DataStores, remotes or active exchange.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local W=require(script.Parent.WorldService)
local Refresh=require(script.Parent.BotRefresh)
local Command=require(script.Parent.OwnerBotsCommand)
local RetryTests=require(script.Parent.BotExitRetryTests)
local Scheduler=require(script.Parent.SimulationScheduler)
local Tests={}
local function copy(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b,path)
 path=path or "state";assert(type(a)==type(b),path.." type")
 if type(a)~="table"then assert(a==b,path.." value");return end
 for k,v in pairs(a)do equal(v,b[k],path.."."..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path.." extra "..tostring(k))end
end
local function near(a,b)assert(math.abs(a-b)<.001,tostring(a).." ~= "..tostring(b))end
local function config()
 local c=copy(C);c.ContractOrder={"BX"};c.PlayerExecution=nil;c.WarmupSeconds=0
 c.Contracts.BX.Last=5000;c.Contracts.BX.Margin=1
 c.MakersPerInstrument=0;c.ParticipantsPerInstrument=0;c.WhalesPerInstrument=0;c.ScalpersPerInstrument=0;c.Reserve.Count=0
 for k in pairs(c.BotPopulation.Counts)do c.BotPopulation.Counts[k]=0 end
 return c
end
local function fixture(base,quantity,side)
 local c=config();local e=E.new(c,731)
 local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(731),Agents={},PolicyVersion=c.BotPopulation.Version},P)
 local a=e:AddAccount("bot:BX:Maker:1",base or 100000,100,.8,false)
 a.StartingCapital=a.Base;a.NetCapitalAdjustments=0;a.PolicyCapitalTarget=c.BotPopulation.Capital.Maker
 table.insert(p.Agents,{Id=a.Id,Kind="Maker",Key="BX",Budget=a.PolicyCapitalTarget,Next=99,Quotes={}})
 c.BotPopulation.Counts.Maker=1
 e:AddAccount("player",10000000,100,.8,true)
 if quantity then
  assert(e:Submit("player",{Contract="BX",Direction=-(side or 1),Quantity=quantity,Type="Limit",Price=5000}))
  local ok,r=e:Submit(a.Id,{Contract="BX",Direction=side or 1,Quantity=quantity,Type="Market"});assert(ok and r.Filled==quantity)
 end
 return e,p,a,c
end
local function refresh(e,p,sequence)
 local plan=Refresh.Prepare(e,p,sequence or 1,1);local r=Refresh.Apply(e,p,plan);e:Audit();return r
end
local function close(e,a,quantity,price)
 local pos=a.Positions.BX
 assert(e:Submit("player",{Contract="BX",Direction=pos.Direction,Quantity=quantity,Type="Limit",Price=price}))
 local ok,r=e:Submit(a.Id,{Contract="BX",Direction=-pos.Direction,Quantity=quantity,Type="Market",ReduceOnly=true})
 assert(ok and r.Filled==quantity);e:Audit()
end
local function world()
 local store={}
 function store:UpdateAsync(_,fn)
  if self.BeforeWrite then self.BeforeWrite()end
  if self.Fail then error("Injected failure")end
  local r=fn(copy(self.Value));if r then self.Value=copy(r)end
  if self.LostReply then error("Injected lost confirmation")end
  return copy(r)
 end
 function store:GetAsync()return copy(self.Value)end
 local c=config();local w=W.new(c,{Studio=false,PlaceId=123,JobId="bot-refresh-fixture",CanOwn=true,Store=store,Now=function()return 1000 end})
 w:Open();assert(w:CanRun(),w.LastError)
 local e,p=fixture(100000,3);w.Config=e.Config;w.Engine=e;w.Population=p
 assert(w:Save(false));return w,store
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Open long and short winners/losers reset to allocation; flat-price closes earn zero",function()
  for _,side in ipairs({1,-1})do for _,mark in ipairs({4990,5010})do
   local e,p,a=fixture(100000,3,side);e.Books.BX.Last=mark/e.Books.BX.Spec.Tick
   local before=e:Summary(a);local player=copy(e.Accounts.player);local pos=a.Positions.BX;local entry=pos.Entry
   local receipt=refresh(e,p);near(receipt.Amount,750000-before.Equity)
   near(a.Balance,750000);near(a.Realized,0);near(e:Summary(a).Unrealized,0);near(e:Summary(a).Session,0)
   assert(a.Positions.BX==pos and pos.Entry==entry);equal(player,e.Accounts.player)
   local row=a.CapitalAdjustments[1];near(row.CashAdjustment,row.Amount+row.UnrealizedSettled)
   close(e,a,3,mark);near(a.Realized,0);near(a.Balance,750000)
  end end
 end)
 test("Partial closes release only post-refresh P&L, including after checkpoint restore",function()
  local e,p,a,c=fixture(100000,3);e.Books.BX.Last=5010/.25;refresh(e,p)
  close(e,a,1,5012);near(a.Realized,100);assert(a.Positions.BX.Quantity==2)
  local r,rp=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),c);a=r.Accounts[a.Id]
  close(r,a,2,5009);near(a.Realized,0);near(a.Balance,750000)
  equal(p.BotRefreshReceipt,rp.BotRefreshReceipt)
 end)
 test("A partially filled entry keeps its order and averages the new accounting basis",function()
  local e,p,a=fixture()
  local ok,order=e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=4,Type="Limit",Price=5000});assert(ok)
  assert(e:Submit("player",{Contract="BX",Direction=-1,Quantity=2,Type="Market"}))
  local working=e.Orders[order.Id];assert(working.Filled==2 and working.Remaining==2)
  e.Books.BX.Last=5010/.25;local saved=copy(working);refresh(e,p)
  assert(e.Orders[order.Id]==working);equal(saved,working)
  assert(e:Submit("player",{Contract="BX",Direction=-1,Quantity=2,Type="Market"}))
  near(a.Positions.BX.Entry,5000);near(a.Positions.BX.PnlEntry,5005)
  close(e,a,4,5005);near(a.Realized,0)
 end)
 test("Scaling and reversal use independent cost bases without leaking old unrealized P&L",function()
  local e,p,a=fixture(100000,2);e.Books.BX.Last=5010/.25;refresh(e,p)
  assert(e:Submit("player",{Contract="BX",Direction=1,Quantity=3,Type="Limit",Price=5012}))
  assert(e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=3,Type="Market"}))
  near(a.Realized,200);assert(a.Positions.BX.Direction==-1 and a.Positions.BX.Quantity==1)
  assert(a.Positions.BX.PnlEntry==nil and a.Positions.BX.Entry==5012)
  close(e,a,1,5011);near(a.Realized,250)
 end)
 test("Working protections, stops, queued exits and retry deadlines retain identity and priority",function()
  local e,c=RetryTests.Fixture(1);local a=e.Accounts["short:1"];local pos=a.Positions.BX
  pos.Triggered="Take profit";pos.Target=5290;e:AdvanceClock(.25)
  assert(pos.ExitOrder and e.Orders[pos.ExitOrder].Queued)
  c.BotPopulation=copy(C.BotPopulation)
  local p={Agents={{Id=a.Id,Kind="Scalper",Key="BX",Next=91,ExitPending=true}}}
  local position,orders,pending,agent,books=copy(pos),copy(e.Orders),copy(e.PendingStops),copy(p.Agents),copy(e.Books)
  local n=e.NextOrder;refresh(e,p);position.PnlEntry=pos.PnlEntry
  equal(position,pos);equal(orders,e.Orders);equal(pending,e.PendingStops);equal(agent,p.Agents);equal(books,e.Books);assert(n==e.NextOrder)
  e.Books.BX.FairReference=5280/e.Books.BX.Spec.Tick;e:AdvanceClock(.25);e:ProcessPlayerOrders();e:Audit()
  assert(not a.Positions.BX);near(a.Realized,(5230.25-5282.5)*10*50)
 end)
 test("Negative equity is recapitalized without dropping pending liquidation exposure",function()
  local e,p,a=fixture(1000,1);e.Books.BX.Last=4900/.25
  a.Locked=true;a.Liquidating=true;a.Positions.BX.Triggered="Account depleted"
  assert(e:Summary(a).Equity<0);local r=refresh(e,p)
  near(r.Amount,754000);assert(not a.Locked and a.Liquidating and a.Positions.BX.Triggered=="Account depleted")
  close(e,a,1,4900);near(a.Realized,0);near(a.Balance,750000)
 end)
 test("Retiring bots and closed markets receive no funding; players and clearing excluded",function()
  local e,p,a,c=fixture()
  for _,kind in ipairs(c.BotPopulation.Order)do if kind~="Maker"then
   local id="retired:"..kind;local other=e:AddAccount(id,1000,10,.8,false)
   table.insert(p.Agents,{Id=id,Kind=kind,Key="BX",Retiring=true,Budget=7})
   other.StartingCapital=1000;other.NetCapitalAdjustments=0
  end end
  local legacy=copy(c.LegacyContracts.RTY);legacy.CloseOnly=nil;c.Contracts.RTY=legacy;table.insert(c.ContractOrder,"RTY")
  local temp=E.new(c,1);e.Books.RTY=temp.Books.RTY
  assert(e:Submit("player",{Contract="RTY",Direction=-1,Quantity=1,Type="Limit",Price=legacy.Last}))
  assert(e:Submit(a.Id,{Contract="RTY",Direction=1,Quantity=1,Type="Market"}))
  legacy.CloseOnly=true;p.Agents[1].Key="RTY";p.Agents[1].Retiring=true;e.Books.RTY.Last+=10
  local house=e:AddAccount("house",123456,100,.8,false);house.House=true
  table.insert(p.Agents,{Id=house.Id,Kind="Maker"});table.insert(p.Agents,{Id="player",Kind="Maker"})
  local accounts=copy(e.Accounts);local before=copy(c);local r=refresh(e,p)
  assert(r.Count==0);equal(accounts,e.Accounts);equal(before,c)
 end)
 test("Repeat receipts are idempotent forever; deliberate later refresh creates a new baseline",function()
  local e,p,a=fixture(100000,3);e.Books.BX.Last=5010/.25;refresh(e,p)
  local before=CP.Capture(e,p);refresh(e,p,1);equal(before,CP.Capture(e,p))
  close(e,a,1,5012);local receipt=refresh(e,p,2);near(receipt.Amount,-300)
  near(a.Realized,0);near(e:Summary(a).Session,0);assert(#a.CapitalAdjustments==2)
  before=CP.Capture(e,p);assert(not pcall(refresh,e,p,1));equal(before,CP.Capture(e,p))
  close(e,a,2,5012);near(a.Realized,0)
 end)
 test("Invalid allocation fails before touching any bot or market",function()
  local e,p=fixture();table.insert(p.Agents,{Id="player",Kind="Unknown"})
  local bad=e:AddAccount("bad",100,1,.8,false);table.insert(p.Agents,{Id=bad.Id,Kind="Unknown"})
  local before=CP.Capture(e,p);assert(not pcall(refresh,e,p));equal(before,CP.Capture(e,p))
 end)
 test("Owner-only parsing and queued boundary reject unauthorized and duplicate callbacks",function()
  assert(Command.Parse(" /BOTS REFRESH "))
  for _,text in ipairs({"/bots","/bots refresh all","/bots reset","bots refresh"})do assert(not Command.Parse(text))end
  local now=1;local calls=0;local notices={};local owner={UserId=1};local held
  local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,Now=function()return now end,
   Ready=function()return true end,NextSequence=function()return 1 end,Notify=function(_,m)table.insert(notices,m)end,
   Spawn=function(fn)held=fn end,Refresh=function(seq,actor)assert(seq==1 and actor==1);calls+=1;return true,{Count=9,Amount=-123}end})
  command:Handle({UserId=2},"/bots refresh");assert(not command.Pending and notices[1]:find("Only the experience owner"))
  command:Handle(owner,"/bots refresh");command:Handle(owner,"/bots refresh");assert(calls==0 and command.Pending)
  now+=3;command:Handle(owner,"/bots refresh");assert(command:AtBoundary()and not command:AtBoundary())
  command:Handle({UserId=1},"/bots refresh");assert(calls==0 and command.Busy)
  held();assert(calls==1 and not command.Busy and notices[#notices]:find("9 bots")and notices[#notices]:find("%-\$123.00"))
 end)
 test("Group ownership fails closed and an unavailable world never queues a refresh",function()
  local command=Command.new({CreatorType=Enum.CreatorType.Group,CreatorId=77,GroupLookup=function()return {Owner={Id=1}}end,
   Ready=function()return false end,NextSequence=function()error("Must not queue")end,Notify=function()end})
  command:Handle({UserId=2},"/bots refresh");command:Handle({UserId=1},"/bots refresh");assert(not command.Pending)
  command.Options.Ready=function()return true end;command.Options.NextSequence=function()return 1 end
  command:Handle({UserId=1},"/bots refresh");assert(command.Pending.Actor==1)
  command.Pending=nil;command.Busy=false;command.Options.GroupLookup=function()error("Unavailable")end
  command:Handle({UserId=1},"/bots refresh");assert(not command.Pending)
 end)
 test("Queued chat applies at one scheduler boundary and holds the step until saving finishes",function()
  local w,s=world();local e=w.Engine;local step=e.Step;local thread;local notice
  s.BeforeWrite=function()coroutine.yield()end
  local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,
   Ready=function()return not w.Busy and w:CanRun()end,NextSequence=function()return 1 end,
   Notify=function(_,m)notice=m end,Refresh=function(seq,actor)return w:RefreshBots(seq,actor)end,
   Spawn=function(fn)thread=coroutine.create(fn);assert(coroutine.resume(thread))end})
  command:Handle({UserId=1},"/bots refresh");assert(not w.Population.BotRefreshReceipt and e.Step==step)
  local backlog,steps=Scheduler.Advance(e.Config.StepSeconds,e.Config,function()
   if command:AtBoundary()then return false end
   error("A simulation step ran during the refresh")
  end)
  assert(steps==0 and backlog==e.Config.StepSeconds and not w:CanRun()and w.BotRefreshSaving and command.Busy and not notice)
  assert(coroutine.resume(thread));assert(w:CanRun()and not w.BotRefreshSaving and not command.Busy and notice:find("Saved"))
  assert(w.Population.BotRefreshReceipt.Step==step and e.Step==step)
  backlog,steps=Scheduler.Advance(backlog,e.Config,function()
   assert(not command:AtBoundary());e:AdvanceClock(e.Config.StepSeconds)
  end)
  assert(steps==1 and backlog==0 and e.Step==step+1);e:Audit()
 end)
 test("Durable commit is atomic, excludes overlaps, preserves live identity and restores exactly",function()
  local w,s=world();local e,p=w.Engine,w.Population;local a=e.Accounts["bot:BX:Maker:1"];local pos=a.Positions.BX
  e.Books.BX.Last=5010/.25;local player=copy(e.Accounts.player);local before=a.Balance;local epoch=w.Epoch
  s.BeforeWrite=function()
   assert(not w:CanRun()and w.Busy and a.Balance==before)
   assert(not w:RefreshBots(1,1));assert(not w:Save(false))
  end
  local ok,r=w:RefreshBots(1,1);assert(ok,tostring(r));assert(r.Count==1)
  assert(w.Engine==e and w.Population==p and a==e.Accounts[a.Id]and a.Positions.BX==pos and w.Epoch==epoch)
  equal(player,e.Accounts.player);near(a.Balance,750000)
  local restored,rp=CP.Restore(CP.Decode(s.Value.Checkpoint),w.Config)
  equal(CP.Capture(e,p),CP.Capture(restored,rp));assert(CP.Version==23)
  close(restored,restored.Accounts[a.Id],3,5010);near(restored.Accounts[a.Id].Realized,0)
  s.BeforeWrite=function()error("Duplicate must not write")end;assert(w:RefreshBots(1,1))
 end)
 test("Encode rejection leaves the original world untouched and runnable",function()
  local w=world();local before=CP.Capture(w.Engine,w.Population)
  w._encode=function()error("Injected size refusal")end
  assert(not w:RefreshBots(1,1));assert(w:CanRun()and not w.Busy and not w.Transaction)
  equal(before,CP.Capture(w.Engine,w.Population))
 end)
 test("Failed or ambiguous saves pause, reload the durable outcome and never double-apply",function()
  for _,lost in ipairs({false,true})do
   local w,s=world();local original=w.Engine;local before=original.Accounts["bot:BX:Maker:1"].Balance
   if lost then s.LostReply=true else s.Fail=true end
   assert(not w:RefreshBots(1,1));assert(not w:CanRun()and not w.Engine)
   near(original.Accounts["bot:BX:Maker:1"].Balance,before)
   s.Fail=nil;s.LostReply=nil;w:Open();assert(w:CanRun(),w.LastError)
   assert((w.Population.BotRefreshReceipt~=nil)==lost)
   assert(w:RefreshBots(1,1));local a=w.Engine.Accounts["bot:BX:Maker:1"]
   near(a.Balance,750000);assert(#a.CapitalAdjustments==1);w.Engine:Audit()
  end
 end)
 return rows
end
function Tests.Captured(snapshot,steps,yieldStep)
 local e,p=CP.Restore(snapshot,C)
 local before=CP.Capture(e,p);local players={};local seen={}
 for _,agent in ipairs(p.Agents)do seen[agent.Id]=true end
 for id,a in pairs(e.Accounts)do
  if a.Player or a.House or a.Archive then players[id]=copy(a)
  else assert(seen[id],"Unregistered bot in captured world: "..id)end
 end
 local initialAudit=e:Audit();local started=os.clock();local r=refresh(e,p)
 local milliseconds=(os.clock()-started)*1000;local after=CP.Capture(e,p)
 equal(before.Config,after.Config);equal(before.Engine.Books,after.Engine.Books)
 equal(before.Engine.Orders,after.Engine.Orders);equal(before.Engine.PendingStops,after.Engine.PendingStops)
 for id,a in pairs(players)do equal(a,e.Accounts[id],id)end
 local population=copy(after.Population);population.BotRefreshReceipt=before.Population.BotRefreshReceipt
 equal(before.Population,population)
 for _,key in ipairs({"Time","Step","NextOrder","NextTrade","NextPriority","TotalVolume","TradeHash","Execution","RequestJournal"})do
  equal(before.Engine[key],after.Engine[key],key)
 end
 local count,held,retired=0,0,0
 for _,agent in ipairs(p.Agents)do local a=e.Accounts[agent.Id]
  if not a.Player and not a.House and not a.Archive then
   count+=1;near(e:Summary(a).Equity,C.BotPopulation.Capital[agent.Kind]);near(a.Realized,0);near(e:Summary(a).Unrealized,0);near(e:Summary(a).Session,0)
   if agent.Retiring or e.Books[agent.Key].Spec.CloseOnly then retired+=1 end
   for _ in pairs(a.Positions)do held+=1 end
  end
 end
 assert(count==r.Count)
 local encoded=CP.Encode(after);local re,rp=CP.Restore(CP.Decode(encoded),C)
 equal(after,CP.Capture(re,rp));refresh(re,rp,r.Sequence);equal(after,CP.Capture(re,rp))
 local orders,trades=e.NextOrder,e.NextTrade;local costs={}
 for i=1,steps or 64 do
  local at=os.clock();p:Step();table.insert(costs,(os.clock()-at)*1000);rp:Step()
  e:Audit();re:Audit();if yieldStep then yieldStep()end
 end
 equal(CP.Capture(e,p),CP.Capture(re,rp));table.sort(costs)
 return {SourceStep=before.Engine.Step,Count=count,Positions=held,Retired=retired,Amount=r.Amount,RefreshMs=milliseconds,
  CheckpointVersion=encoded.Version,RawBytes=encoded.RawBytes,Steps=#costs,P95StepMs=costs[math.ceil(#costs*.95)],
  MaxStepMs=costs[#costs],NewOrders=e.NextOrder-orders,NewTrades=e.NextTrade-trades,AuditBefore=initialAudit,AuditAfter=e:Audit(),Deterministic=true}
end
return Tests

