-- Edit-only install. No play/stop action, checkpoint write, local save, or publication.
assert(not game:GetService("RunService"):IsRunning(),"Stop Play safely before installing /bots refresh.")
local Encoding=game:GetService("EncodingService")
local function hash(s)local b=Encoding:ComputeStringHash(s:gsub("\r\n","\n"),Enum.HashAlgorithm.Sha256);return(b:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end
local release={}
release[([====[!ServerScriptService.MarketReign.BotRefresh]====]):sub(2)]={Source=([====[!-- Accounting-only maintenance. No matching, clock advancement, strategy changes or storage.
local Refresh={}
local function finite(n)return type(n)=="number"and n==n and math.abs(n)<1e15 end
function Refresh.Prepare(engine,population,sequence,actor)
 assert(type(sequence)=="number"and sequence%1==0 and sequence>0,"Invalid refresh sequence")
 local previous=population.BotRefreshReceipt
 if previous and sequence==previous.Sequence then
  assert(actor==previous.Actor,"Refresh receipt actor mismatch")
  return {Receipt=previous,Duplicate=true}
 end
 assert(sequence==(previous and previous.Sequence or 0)+1,"Stale or out-of-order bot refresh")
 local capital=assert(engine.Config.BotPopulation and engine.Config.BotPopulation.Capital,"Bot capital policy required")
 local receipt={Sequence=sequence,Actor=actor,Step=engine.Step,Time=engine.Time,Count=0,Amount=0}
 local plan={Receipt=receipt,Rows={}};local seen={}
 for _,agent in ipairs(population.Agents)do
  local a=assert(engine.Accounts[agent.Id],"Bot account missing")
  assert(not seen[a.Id],"Duplicate bot participant");seen[a.Id]=true
  -- Include retiring agents and close-only books, but never fund clearing/player accounts.
  if a.Player or a.House or a.Archive then continue end
  local target=capital[agent.Kind]
  assert(finite(target)and target>0,"Unknown bot capital allocation: "..tostring(agent.Kind))
  local s=engine:Summary(a);local amount=target-s.Equity
  assert(finite(amount)and finite(a.Realized)and finite(s.Unrealized),"Invalid bot accounting")
  local marks={}
  for key,p in pairs(a.Positions)do
   local b=assert(engine.Books[key],"Missing bot position market")
   local mark=(b.Last or b.Reference)*b.Spec.Tick
   assert(finite(mark)and mark>0 and p.Quantity>0,"Invalid bot mark")
   marks[key]=mark
  end
  local row={Id=a.Id,Marks=marks,Target=target,Amount=amount,Realized=a.Realized,
   Unrealized=s.Unrealized,EquityBefore=s.Equity,BalanceBefore=a.Balance,
   Base=a.Base+amount,Baseline=(a.PnlBaseline or 0)+a.Realized+s.Unrealized}
  table.insert(plan.Rows,row);receipt.Count+=1;receipt.Amount+=amount
 end
 return plan
end
function Refresh.Apply(engine,population,plan)
 if plan.Duplicate then return plan.Receipt end
 local r=plan.Receipt
 for _,row in ipairs(plan.Rows)do
  local a=engine.Accounts[row.Id]
  a.StartingCapital=a.StartingCapital or a.Base
  a.NetCapitalAdjustments=(a.NetCapitalAdjustments or 0)+row.Amount
  a.CapitalAdjustments=a.CapitalAdjustments or {}
  table.insert(a.CapitalAdjustments,{Reason="Owner bot refresh",Sequence=r.Sequence,Actor=r.Actor,Step=r.Step,Time=r.Time,
   Amount=row.Amount,EquityBefore=row.EquityBefore,TargetEquity=row.Target,BalanceBefore=row.BalanceBefore,
   RealizedBefore=row.Realized,UnrealizedSettled=row.Unrealized,CashAdjustment=row.Target-row.BalanceBefore,
   PnlBaseline=row.Baseline})
  -- Base remains contributed capital. Frozen prior P&L reconciles it to spendable cash.
  -- Entry remains the strategy/execution price; only accounting uses PnlEntry.
  a.Base=row.Base;a.PnlBaseline=row.Baseline;a.Realized=0;a.Balance=row.Target
  for key,mark in pairs(row.Marks)do a.Positions[key].PnlEntry=mark end
  a.LossLimit=a.Base;a.Locked=false;a.Revision+=1
 end
 -- Funding can make resting liquidity eligible. Wake exits through their existing
 -- revision check; keep retry deadlines, attempt caps and all order priorities.
 engine.EligibilityRevision=(engine.EligibilityRevision or 0)+1
 population.BotRefreshReceipt=r
 return r
end
-- Copy just the records Apply writes; every other execution/strategy field is read-only.
function Refresh.Preview(engine,population,plan)
 local e=setmetatable(table.clone(engine),getmetatable(engine));e.Accounts=table.clone(engine.Accounts)
 local p=setmetatable(table.clone(population),getmetatable(population));p.Engine=e
 for _,row in ipairs(plan.Rows)do
  local old=engine.Accounts[row.Id];local a=table.clone(old);e.Accounts[row.Id]=a
  a.CapitalAdjustments=table.clone(old.CapitalAdjustments or {});a.Positions={}
  for key,pos in pairs(old.Positions)do a.Positions[key]=table.clone(pos)end
 end
 Refresh.Apply(e,p,plan)
 return e,p
end
return Refresh
]====]):sub(2),Hash=([====[!15047b97d27f2f681a0edac26de86db47ad82643aa028a30544c5060838d6287]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.OwnerBotsCommand]====]):sub(2)]={Source=([====[!-- Server-only owner policy; enqueue here and consume only at the scheduler boundary.
local Owner=require(script.Parent.OwnerResetCommand)
local Command={} Command.__index=Command
function Command.Parse(text)
 return type(text)=="string"and #text<=80 and text:lower():match("^%s*/bots%s+refresh%s*$")~=nil
end
function Command.new(options)
 return setmetatable({Options=options,Busy=false,LastAt=setmetatable({},{__mode="k"})},Command)
end
function Command:Handle(player,text)
 local o=self.Options;local now=(o.Now or os.clock)()
 if now-(self.LastAt[player]or -math.huge)<2 then return end;self.LastAt[player]=now
 if not Owner.IsOwner(player.UserId,o.CreatorType,o.CreatorId,o.GroupLookup)then
  o.Notify(player,"Only the experience owner can use /bots refresh.");return
 end
 if not Command.Parse(text)then o.Notify(player,"Usage: /bots refresh");return end
 if self.Busy then o.Notify(player,"A bot refresh is already pending or saving.");return end
 if not o.Ready()then o.Notify(player,"The saved exchange is busy or unavailable. Try /bots refresh shortly.");return end
 self.Busy=true;self.Pending={Player=player,Actor=player.UserId,Sequence=o.NextSequence()}
end
function Command:AtBoundary()
 local item=self.Pending;local o=self.Options
 if not item or not o.Ready()then return false end
 self.Pending=nil
 -- Spawn starts the transaction synchronously, then yields only for the fenced store write.
 local spawn=o.Spawn or task.spawn
 spawn(function()
  local ok,saved,result=pcall(o.Refresh,item.Sequence,item.Actor)
  self.Busy=false
  if ok and saved then
   o.Notify(item.Player,string.format("Refreshed %d bots. Total capital adjustment: %s$%.2f. Saved.",
    result.Count,result.Amount<0 and "-"or "+",math.abs(result.Amount)))
  else
   o.Notify(item.Player,"Bot refresh was not confirmed. Check saved exchange status before retrying.")
   warn("[Get Funded!] Bot refresh: "..tostring(ok and result or saved))
  end
 end)
 return true
end
return Command
]====]):sub(2),Hash=([====[!c903691b074ca1a80d902bca05678d6f45eb46705b0174b4f907622596f670c5]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotRefreshTests]====]):sub(2)]={Source=([====[!-- Detached fixtures only: no Players, real DataStores, remotes or active exchange.
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
 test("All configured bot categories and retired obligations included; players and clearing excluded",function()
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
  local player,clearing=copy(e.Accounts.player),copy(house);local before=copy(c);local r=refresh(e,p)
  assert(r.Count==9);equal(player,e.Accounts.player);equal(clearing,house);equal(before,c)
  for _,agent in ipairs(p.Agents)do local account=e.Accounts[agent.Id]
   if not account.Player and not account.House then near(e:Summary(account).Equity,c.BotPopulation.Capital[agent.Kind]);near(e:Summary(account).Session,0)end
  end
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
  equal(CP.Capture(e,p),CP.Capture(restored,rp));assert(CP.Version==17)
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
]====]):sub(2),Hash=([====[!5f31eda6ec35ba1cc1ba8a91748e7ce497f3e95fba234018bca9fb079b23a4ba]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.MarketEngine]====]):sub(2)]={Source=([====[!-- Deterministic, server-only price/time priority exchange. Prices are integer ticks internally.
local Engine = {}
Engine.__index = Engine
local TradeStats=require(script.Parent.TradeStats)
local Protection=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local ContractLimits=require(game.ReplicatedStorage.MarketReign.ContractLimits)
local PlayerExecution=require(script.Parent.PlayerExecution)
local Protective=require(script.Parent.ProtectiveOrders)
local BotExitRetry=require(script.Parent.BotExitRetry)
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function integer(n) return finite(n) and n%1==0 end
local function sortedKeys(t)
 local keys={} for k in pairs(t) do table.insert(keys,k) end table.sort(keys) return keys
end
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
function Engine.new(config, seed)
 local self=setmetatable({Config=config,Seed=seed,Time=0,Step=0,Books={},Accounts={},AccountOrder={},Orders={},OrderArchive={},
  NextOrder=0,NextPriority=0,NextTrade=0,Trades={},PendingStops={},TotalVolume=0,TradeHash=0},Engine)
 for _,key in ipairs(config.ContractOrder) do
  local c=config.Contracts[key]
  local candles={} for _,tf in ipairs(config.Timeframes) do candles[tf[1]]={} end
  self.Books[key]={Key=key,Spec=c,Bids={},Asks={},Last=nil,Open=nil,Reference=math.round(c.Last/c.Tick),Volume=0,
   Candles=candles,CandleVolume={},Recent={},Up=0,Down=0,Volatility=1}
 end
 return self
end
function Engine:AddAccount(id,base,limit,risk,isPlayer)
 if self.Accounts[id] then return self.Accounts[id] end
 local a={Id=id,Base=base,Balance=base,Realized=0,CashFlow=0,Positions={},OpenOrders={},History={},Fills={},
  Limit=limit,Risk=risk,Player=isPlayer==true,Revision=0,Locked=false,LossLimit=base}
 -- Player accounts carry lifetime trading statistics from their first execution.
 if a.Player then a.Stats=TradeStats.New("Live");self:ContractLimit(a) end
 self.Accounts[id]=a table.insert(self.AccountOrder,id) return a
end
-- Recalculate from closed balance on every capacity read, including restored accounts.
-- Limit remains a cached field for checkpoint compatibility, never an authority for players.
function Engine:ContractLimit(a)
 if a.Player then a.Limit=ContractLimits.ForBalance(a.Balance) end
 return a.Limit
end
function Engine:Summary(a)
 local unrealized,count,margin=0,0,0
 for _,key in ipairs(self.Config.ContractOrder) do
  local b=self.Books[key] local p=a.Positions[key]
  if p then
   unrealized+=((b.Last or b.Reference)*b.Spec.Tick-(p.PnlEntry or p.Entry))*p.Quantity*p.Direction*b.Spec.Multiplier
   count+=1 margin+=p.Quantity*b.Spec.Margin
  end
 end
 -- Funded accounts liquidate on equity depletion; margin limits apply to new exposure.
 return {Balance=a.Balance,Equity=a.Balance+unrealized,Unrealized=unrealized,Session=a.Balance+unrealized-a.Base-(a.PnlBaseline or 0),
  Allowance=math.max(0,a.Balance+unrealized),Count=count,Margin=margin}
end
function Engine:Exposure(a,key,side,qty,summary)
 local limit=self:ContractLimit(a)
 local used,total=0,0
 local pending={}
 for id in pairs(a.OpenOrders)do
  local o=self.Orders[id]
  if o and not o.ReduceOnly then
   local held=pending[o.Contract]or {0,0};pending[o.Contract]=held
   local index=o.Direction==1 and 1 or 2;held[index]+=o.Remaining
  end
 end
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol] local net=p and p.Quantity*p.Direction or 0
  local held=pending[symbol];local buy,sell=held and held[1]or 0,held and held[2]or 0
  if symbol==key then if side==1 then buy+=qty else sell+=qty end end
  local worst=math.max(math.abs(net+buy),math.abs(net-sell))
  if worst>limit then return false end
  total+=worst
  used+=worst*self.Books[symbol].Spec.Margin
 end
 return (not a.Player or total<=limit) and used<=math.max(0,(summary or self:Summary(a)).Equity)*a.Risk
end
-- Maximum additional order in this direction, reserving worst-case independent entry fills.
-- Reduce-only exits cannot create exposure and do not consume entry capacity.
-- Players receive one contract per full $1,000 of closed balance, with a minimum of five.
-- Positions and working entries share that total across instruments. Open P&L and simulated
-- margin do not change it. Depleted accounts still cannot open new exposure.
function Engine:OrderCapacity(a,key,side,stopTicks,excludeOrder,summary)
 if a.Resetting then return 0,"Account reset is liquidating positions."end
 if (summary or self:Summary(a)).Equity<=0 then return 0,"Account equity reached $0." end -- failure rule: depletes on the next step
 local otherCount,net,same,opposite=0,0,0,0
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol] local position=p and p.Quantity*p.Direction or 0
  local buy,sell=0,0
  for id in pairs(a.OpenOrders) do
   local o=self.Orders[id]
   if id~=excludeOrder and o and not o.ReduceOnly and o.Contract==symbol then
    if o.Direction==1 then buy+=o.Remaining else sell+=o.Remaining end
   end
  end
  if symbol==key then net=position;same=side==1 and buy or sell;opposite=side==1 and sell or buy
  else otherCount+=math.max(math.abs(position+buy),math.abs(position-sell)) end
 end
 local limit=self:ContractLimit(a)
 local allowed=limit-otherCount
 local reason="Account contract limit ("..limit.." total), including working orders."
 if math.abs(net-side*opposite)>allowed then return 0,reason end
 local maximum=math.max(0,math.floor(allowed-side*net-same))
 return maximum,reason
end
function Engine:CapacityMessage(a,key,side,stopTicks)
 local maximum,reason=self:OrderCapacity(a,key,side,stopTicks)
 return reason.." Maximum currently available: "..maximum.." "..key.."."
end
-- Armed stop entries by contract. Derived from Orders (never saved), so a restored world rebuilds it.
function Engine:_stopIndex()
 if not self.Stops then
  self.Stops={}
  for id,o in pairs(self.Orders) do
   if o.Type=="Stop" then self.Stops[o.Contract]=self.Stops[o.Contract] or {} self.Stops[o.Contract][id]=true end
  end
 end
 return self.Stops
end
function Engine:_retire(o,status)
 if o.Type=="Limit"then local b=self.Books[o.Contract];b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1 end
 if o.Type=="Stop" and self.Stops and self.Stops[o.Contract] then self.Stops[o.Contract][o.Id]=nil end
 o.Status=status self.Accounts[o.Owner].OpenOrders[o.Id]=nil
 o.StatusHistory=o.StatusHistory or {}
 table.insert(o.StatusHistory,{Step=self.Step,Time=self.Time,Status=status,Reason=o.BlockedReason or status})
 if #o.StatusHistory>16 then table.remove(o.StatusHistory,1)end
 self.Orders[o.Id]=nil
 if o.Protection then Protective.Mark(self,self.Accounts[o.Owner],o.Contract)end
 table.insert(self.OrderArchive,o)
 if #self.OrderArchive>self.Config.MaxOrderHistory then table.remove(self.OrderArchive,1) end
end
function Engine:Cancel(owner,id)
 local o=self.Orders[id]
 if not o or o.Owner~=owner then return false,"Order is no longer working." end
 local p=self.Accounts[owner].Positions[o.Contract]
 if o.ReduceOnly and p and p.ExitOrder==o.Id and p.Triggered=="Player close"then p.ExitOrder=nil;p.Triggered=nil end
 self:_unrest(self.Books[o.Contract],o)
 o.Cancelled+=o.Remaining o.Remaining=0 self:_retire(o,"Cancelled")
 self.Accounts[owner].Revision+=1
 return true,"Order cancelled."
end
function Engine:CancelAll(owner,key)
 local a=self.Accounts[owner]
 for _,id in ipairs(sortedKeys(a.OpenOrders)) do
  local o=self.Orders[id] if o and (not key or o.Contract==key) then self:Cancel(owner,id) end
 end
end
function Engine:_cleanBook(b)
 for _,side in ipairs({b.Bids,b.Asks}) do
  for i=#side,1,-1 do
   local level=side[i] local quantity=0
   for j=#level.Orders,1,-1 do
    local o=level.Orders[j]
    if o.Remaining<=0 then table.remove(level.Orders,j) else quantity+=o.Remaining end
   end
   level.Quantity=quantity if quantity==0 then table.remove(side,i) end
  end
 end
end
function Engine:_rest(b,o)
 o.Queued=nil
 self:_blocked(o,not PlayerExecution.Allows(self,b,o.Price,-o.Direction)and "Waiting · price safeguard"or nil)
 b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
 local levels=o.Direction==1 and b.Bids or b.Asks
 -- Price levels are sorted; binary search avoids scanning every level on entry.
 local lo,hi=1,#levels
 while lo<=hi do
  local mid=math.floor((lo+hi)/2);local l=levels[mid]
  if l.Price==o.Price then
   local index=#l.Orders+1
   if l.Orders[#l.Orders]and (o.Priority or o.Id)<(l.Orders[#l.Orders].Priority or l.Orders[#l.Orders].Id)then
    local first,last=1,#l.Orders
    while first<=last do local mid=math.floor((first+last)/2);local held=l.Orders[mid]
     if (o.Priority or o.Id)<(held.Priority or held.Id)then last=mid-1 else first=mid+1 end
    end
    index=first
   end
   table.insert(l.Orders,index,o);l.Quantity+=o.Remaining;return
  end
  if (o.Price-l.Price)*o.Direction>0 then hi=mid-1 else lo=mid+1 end
 end
 table.insert(levels,lo,{Price=o.Price,Quantity=o.Remaining,Orders={o}})
end
function Engine:_fillAccount(o,price,qty,tradeId)
 self.EligibilityRevision=(self.EligibilityRevision or 0)+1
 self.ReductionDirty=self.ReductionDirty or {};self.ReductionDirty[o.Owner]=true
 local a=self.Accounts[o.Owner] local b=self.Books[o.Contract] local p=a.Positions[o.Contract]
 local side=o.Direction local oldNet=p and p.Quantity*p.Direction or 0 local delta=side*qty
 if o.Protection=="Take profit"and p then
  p.Triggered="Take profit";p.ExitOrder=o.Id;p.TargetFilled=(p.TargetFilled or 0)+qty
  table.insert(self.PendingStops,{Owner=a.Id,Contract=o.Contract,Position=p.Id})
 end
 a.CashFlow-=price*delta*b.Spec.Multiplier -- double-entry notional audit ledger; not spendable futures cash
 local realized=0 local closedRow
 if p and oldNet*delta<0 then
  local closed=math.min(math.abs(oldNet),qty)
  -- A saved account from before lifetime stats is migrated before this execution changes its ledger.
  if a.Player and (type(a.Stats)~="table" or a.Stats.V~=TradeStats.Version or a.Stats.DayV~=1) then TradeStats.Reconcile(self,a,os.time()) end
  realized=(price-(p.PnlEntry or p.Entry))*closed*p.Direction*b.Spec.Multiplier
  a.Realized+=realized;a.Balance=a.Base+(a.PnlBaseline or 0)+a.Realized
  self:ContractLimit(a)
  -- Persist eligibility independently of the bounded display history, including break-even closes.
  a.CompletedTrades=(a.CompletedTrades or #a.History)+1
  table.insert(a.History,1,{PositionId=p.Id,Contract=o.Contract,Direction=p.Direction,Quantity=closed,Entry=p.Entry,PnlEntry=p.PnlEntry,Exit=price,Pnl=realized,
   Time=string.format("%02d:%02d:%02d",math.floor(self.Time/3600)%24,math.floor(self.Time/60)%60,math.floor(self.Time)%60),ClosedAt=os.time(),TradeId=tradeId,
   Reason=o.Protection or p.Triggered or "Trade"})
  -- Lifetime counters update on the same execution; trimming the display history below never changes them.
  if a.Player then TradeStats.Add(a.Stats,a.History[1]) end
  closedRow=a.History[1]
  if #a.History>self.Config.MaxAccountHistory then table.remove(a.History) end
 end
 local net=oldNet+delta
 if net==0 then a.Positions[o.Contract]=nil
 elseif not p or oldNet*net<0 then
  p={Id=o.Id,Contract=o.Contract,Direction=net>0 and 1 or -1,Quantity=math.abs(net),Entry=price}
  a.Positions[o.Contract]=p
 else
  if oldNet*delta>0 then
   if p.PnlEntry then p.PnlEntry=(p.PnlEntry*math.abs(oldNet)+price*qty)/math.abs(net)end
   p.Entry=(p.Entry*math.abs(oldNet)+price*qty)/math.abs(net)
  end
  p.Quantity=math.abs(net)
 end
 p=a.Positions[o.Contract]
 if p and not o.ReduceOnly and p.Direction==side then
  -- Existing player protections keep their exact prices through every scale-in fill.
  -- Only absent levels initialize from the ticket; both cover the updated full quantity.
  if o.StopTicks and not p.ManualStop and (not a.Player or p.Stop==nil)then p.Stop=math.round((p.Entry-side*o.StopTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick end
  if o.TargetTicks and not p.ManualTarget and (not a.Player or p.Target==nil)then p.Target=math.round((p.Entry+side*o.TargetTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick end
 end
 o.Remaining-=qty o.Filled+=qty o.Notional+=price*qty
 a.Revision+=1
 Protective.Mark(self,a,o.Contract)
 if a.Player then
  table.insert(a.Fills,1,{TradeId=tradeId,OrderId=o.Id,Contract=o.Contract,Direction=side,Quantity=qty,Price=price,
   Slippage=(price-o.Reference*b.Spec.Tick)*side,Time=self.Time})
  if #a.Fills>40 then table.remove(a.Fills) end
 end
 return closedRow
end
-- Notifications run only after BOTH ledger entries and tape/candle totals commit.
-- A UI/progression callback must not interrupt settlement between counterparties.
function Engine:_notifyClose(owner,row)
 if row and self.OnFundedClose then
  local ok,err=pcall(self.OnFundedClose,self.Accounts[owner],row)
  if not ok then
   self.CloseNotificationErrors=(self.CloseNotificationErrors or 0)+1
   self.LastCloseNotificationError={TradeId=row.TradeId,Owner=owner,Message=tostring(err)}
  end
 end
end
-- The historical house ledger is retained ONLY for atomic administrative migrations/resets.
-- Ordinary player orders use the same finite, executable book as participants.
Engine.HouseId="house:player-fills"
function Engine:_house()
 local h=self.Accounts[Engine.HouseId]
 if not h then h=self:AddAccount(Engine.HouseId,0,1e9,1,false) h.House=true end
 return h
end
function Engine:_touch(b,side)
 local level=(side==1 and b.Asks or b.Bids)[1]
 if level then return level.Price end
 -- The requested side is empty: fall back to the last trade/reference, but never through the opposite
 -- quote. A buy fallback is at least the best bid and a sell fallback at most the best ask, so the
 -- effective spread can never cross and an immediate round trip cannot profit from the fallback alone.
 -- Only trusted administrative settlement uses this fallback; ordinary closes/liquidations need liquidity.
 local fallback=b.Last or b.Reference
 local opposite=(side==1 and b.Bids or b.Asks)[1]
 if opposite and (opposite.Price-fallback)*side>0 then fallback=opposite.Price end
 return fallback
end
function Engine:_playerFill(o,ticks,qty)
 local b=self.Books[o.Contract]
 self.NextTrade+=1 -- fill ids share the trade sequence so history/stats ids stay monotonic; no tape entry
 local price=ticks*b.Spec.Tick
 local house=self:_house()
 local mirror={Id=o.Id,Owner=house.Id,Contract=o.Contract,Direction=-o.Direction,Remaining=qty,Filled=0,Notional=0,Reference=o.Reference}
 local own=self:_fillAccount(o,price,qty,self.NextTrade)
 local other=self:_fillAccount(mirror,price,qty,self.NextTrade)
 self.PlayerFills=(self.PlayerFills or 0)+1
 self:_notifyClose(o.Owner,own);self:_notifyClose(mirror.Owner,other)
end
-- Arrival priority is separate from the stable order id: repricing loses time priority.
function Engine:_priority()
 self.NextPriority=math.max(self.NextPriority or 0,self.NextOrder)+1
 return self.NextPriority
end
function Engine:_unrest(b,o)
 local levels=o.Direction==1 and b.Bids or b.Asks
 if o.Type~="Limit"then return end
 local lo,hi=1,#levels
 while lo<=hi do
  local mid=math.floor((lo+hi)/2);local level=levels[mid]
  if level.Price==o.Price then
   local index=table.find(level.Orders,o)
   if index then
    table.remove(level.Orders,index);level.Quantity-=o.Remaining
    if #level.Orders==0 then table.remove(levels,mid)end
    b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
   end
   return
  end
  if (o.Price-level.Price)*o.Direction>0 then hi=mid-1 else lo=mid+1 end
 end
end
function Engine:_available(o,resting,summaries)
 local a=self.Accounts[o.Owner]
 if not a or self.Orders[o.Id]~=o or o.Remaining<=0 then return 0,"Order is not active"end
 if o.Expires and o.Expires<=self.Time then return 0,"Order expired"end
 if a.Retired or a.LegacyRetired then return 0,"Account retired"end
 if o.ProtectivePosition and not Protective.Valid(self,a,o)then return 0,"Protective position changed"end
 if a.Player and self.ConnectedOwners and not self.ConnectedOwners[a.Id]and (resting or not o.ReduceOnly)then return 0,"Owner disconnected"end
 if o.ReduceOnly then
  local p=a.Positions[o.Contract]
  if o.ReductionPosition and (not p or p.Id~=o.ReductionPosition)then return 0,"Reducing position changed"end
  return p and p.Direction~=o.Direction and math.min(o.Remaining,p.Quantity)or 0,"No position to reduce"
 end
 if a.Locked or a.Liquidating then return 0,"Account is closing positions"end
 local summary=summaries and summaries[a.Id]
 if not summary then summary=self:Summary(a);if summaries then summaries[a.Id]=summary end end
 if summary.Equity<=0 then return 0,"Account equity depleted"end
 if a.Player and self:OrderCapacity(a,o.Contract,o.Direction,o.StopTicks,o.Id,summary)<o.Remaining then return 0,"Account contract limit changed"end
 if not a.Player then
  if summary.OrdersEligible==nil then summary.OrdersEligible=self:Exposure(a,o.Contract,o.Direction,0,summary)end
  if not summary.OrdersEligible then return 0,"Insufficient margin or inventory capacity"end
 end
 return o.Remaining
end
function Engine:_syncReductions()
 local dirty=self.ReductionDirty;self.ReductionDirty=nil
 if not dirty then return end
 for _,owner in ipairs(sortedKeys(dirty))do
  local a=self.Accounts[owner]
  for _,id in ipairs(sortedKeys(a.OpenOrders))do
   local o=self.Orders[id]
   if o and o.ReduceOnly and o.Remaining>0 then
    local p=a.Positions[o.Contract]
    if not p or p.Direction==o.Direction or o.ReductionPosition and o.ReductionPosition~=p.Id then
     self:Cancel(owner,id)
    elseif o.Remaining>p.Quantity then
     o.Cancelled+=o.Remaining-p.Quantity;o.Remaining=p.Quantity
     self:_cleanBook(self.Books[o.Contract]);a.Revision+=1
     local b=self.Books[o.Contract];b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
    end
   end
  end
 end
end
-- Record transitions, not a row on every retry. The bounded order-local history is checkpointed.
function Engine:_blocked(o,reason)
 local status=reason and "Blocked"or o.Queued and "Waiting for matching"or "Working"
 if o.BlockedReason==reason and o.Status==status then return end
 o.BlockedReason=reason;o.Status=status
 o.StatusHistory=o.StatusHistory or {}
 table.insert(o.StatusHistory,{Step=self.Step,Time=self.Time,Reason=reason or "Eligible",Status=o.Status})
 if #o.StatusHistory>16 then table.remove(o.StatusHistory,1)end
 self.Accounts[o.Owner].Revision+=1
end
function Engine:OrderBlockReason(o)
 local available,reason=self:_available(o,not o.Queued)
 if available<=0 then return reason end
 if o.Type=="Limit"and not o.Queued then
  return not PlayerExecution.Allows(self,self.Books[o.Contract],o.Price,-o.Direction)and "Waiting · price safeguard"or nil
 end
 return o.BlockedReason
end
function Engine:_pruneBook(b)
 -- Eligibility cannot change during this non-yielding scan. Reuse each account's
 -- mark calculation only for this scan; no stale cache survives a fill or request.
 local summaries={}
 for _,side in ipairs({b.Bids,b.Asks})do for _,level in ipairs(side)do for _,o in ipairs(level.Orders)do
  if o.Remaining>0 then
   local available,reason=self:_available(o,true,summaries)
   if available<o.Remaining then
    o.Cancelled+=o.Remaining-available;o.Remaining=available;self.Accounts[o.Owner].Revision+=1
    if available==0 then self:_blocked(o,reason);self:_retire(o,"No longer eligible")end
   end
   if available>0 then self:_blocked(o,not PlayerExecution.Allows(self,b,o.Price,-o.Direction)and "Waiting · price safeguard"or nil)end
  end
 end end end
 self:_cleanBook(b)
end
-- A live server supplies connected owners. Offline positions keep protection, but their
-- resting orders are cancelled so they cannot appear as another connected player's liquidity.
function Engine:SetConnectedOwners(owners)
 self.ConnectedOwners=table.clone(owners)
 for _,id in ipairs(self.AccountOrder)do
  local a=self.Accounts[id]
  if a.Player and not owners[id]then self:CancelAll(id)end
  if a.Player then for key in pairs(a.Positions)do Protective.Mark(self,a,key)end end
 end
 Protective.Sync(self,true)
end
function Engine:SetConnected(owner,connected)
 if not self.ConnectedOwners then return end
 self.ConnectedOwners[owner]=connected and true or nil
 if not connected and self.Accounts[owner]then self:CancelAll(owner)end
 local a=self.Accounts[owner];if a then for key in pairs(a.Positions)do Protective.Mark(self,a,key)end end
 Protective.Sync(self,true)
end
function Engine:_trade(b,incoming,resting,qty)
 b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
 local tick=resting.Price local price=tick*b.Spec.Tick
 self.NextTrade+=1
 local trade={Id=self.NextTrade,Time=self.Time,Step=self.Step,Contract=b.Key,Price=price,Ticks=tick,Quantity=qty,
  IncomingOrder=incoming.Id,RestingOrder=resting.Id,Aggressor=incoming.Direction,FairReference=b.FairReference,
  RestingPriority=resting.Priority,IncomingPriority=incoming.Priority,
  Buyer=incoming.Direction==1 and incoming.Owner or resting.Owner,Seller=incoming.Direction==-1 and incoming.Owner or resting.Owner}
 local incomingClose=self:_fillAccount(incoming,price,qty,trade.Id)
 local restingClose=self:_fillAccount(resting,price,qty,trade.Id)
 PlayerExecution.Record(self,self.Accounts[incoming.Owner],b,incoming.Direction,qty,incoming)
 local prior=b.Last
 if prior then
  if tick>prior then b.Up+=1 elseif tick<prior then b.Down+=1 end
  b.Volatility=b.Volatility*0.96+math.abs(tick-prior)*0.04
 end
 -- Sole writer of last price. Quotes, regimes and news never set this field.
 b.Last=tick b.Open=b.Open or tick b.Volume+=qty self.TotalVolume+=qty
 table.insert(b.Recent,tick) if #b.Recent>64 then table.remove(b.Recent,1) end
 -- Stop entries latch on the execution that reaches them; ProcessStops submits them at market.
 local armed=self:_stopIndex()[b.Key]
 if armed and next(armed) then
  for id in pairs(armed) do
   local o=self.Orders[id]
   if o and not o.Triggered and (tick-o.Price)*o.Direction>=0 then o.Triggered=self.Time end
  end
 end
 table.insert(self.Trades,trade) if #self.Trades>self.Config.MaxTradeHistory then table.remove(self.Trades,1) end
 self.TradeHash=(self.TradeHash*31+tick*7+qty*13+trade.Id+self.Step)%2147483647
 for _,tf in ipairs(self.Config.Timeframes) do
  local series=b.Candles[tf[1]] local bucket=math.floor(self.Time/tf[2])*tf[2] local candle=series[#series]
  if not candle or candle.Time~=bucket then
   candle={Time=bucket,Open=price,High=price,Low=price,Close=price,Volume=0}
   table.insert(series,candle) if #series>self.Config.MaxCandles then table.remove(series,1) end
  end
  candle.High=math.max(candle.High,price) candle.Low=math.min(candle.Low,price) candle.Close=price candle.Volume+=qty
  b.CandleVolume[tf[1]]=(b.CandleVolume[tf[1]] or 0)+qty
 end
 -- Latch on each execution so an intrastep crossing cannot be missed.
 for _,id in ipairs(self.AccountOrder) do
  local account=self.Accounts[id]
  if account.Player and not account.Locked and self:Summary(account).Equity<=0 then
   account.Locked=true account.Liquidating=true account.Revision+=1
   -- One depletion per attempt: the marker is saved with the account and never re-counted.
   account.Depleted=true account.DepletedAt=account.DepletedAt or self.Time
   for symbol,position in pairs(account.Positions) do
    position.Triggered=account.Resetting and "Account reset"or "Account depleted" position.Stop=nil position.Target=nil
    table.insert(self.PendingStops,{Owner=id,Contract=symbol,Position=position.Id})
   end
  end
  local p=account.Positions[b.Key]
  if p and (not p.Triggered or account.Player and p.Triggered=="Take profit")then
   local reason
   if p.Stop and (price-p.Stop)*p.Direction<=0 then reason="Stop loss"
   elseif not p.Triggered and p.Target and (price-p.Target)*p.Direction>=0 then reason="Take profit" end
   if reason then
    p.Triggered=reason
    if reason=="Stop loss" then p.Target=nil elseif not account.Player then p.Stop=nil end
    account.Revision+=1;Protective.Mark(self,account,b.Key)
    table.insert(self.PendingStops,{Owner=id,Contract=b.Key,Position=p.Id})
   end
  end
 end
 self:_notifyClose(incoming.Owner,incomingClose);self:_notifyClose(resting.Owner,restingClose)
end
-- `internal` is engine-only; administrative settlement is never accepted from order requests.
function Engine:Submit(owner,request,internal)
 local ok,result=self:_submit(owner,request,internal)
 if not ok then
  self.ExecutionDiagnostics=self.ExecutionDiagnostics or {RejectedCount=0,RecentRejections={}}
  local diagnostics=self.ExecutionDiagnostics;diagnostics.RejectedCount+=1
  local row={Owner=owner,Step=self.Step,Time=self.Time,Reason=tostring(result)}
  if type(request)=="table"then row.Contract=request.Contract;row.Type=request.Type;row.Quantity=request.Quantity end
  table.insert(diagnostics.RecentRejections,row)
  if #diagnostics.RecentRejections>64 then table.remove(diagnostics.RecentRejections,1)end
 end
 return ok,result
end
function Engine:_submit(owner,request,internal)
 local a=self.Accounts[owner]
 if not a or type(request)~="table" then return false,"Unknown account." end
 if a.Resetting and not internal then return false,"Reset in progress. Wait for positions to finish liquidating."end
 if (a.LegacyRetired or a.Retired) and not internal then return false,"This account is archived and cannot trade." end
 local b=self.Books[request.Contract]
 local side,qty,kind=request.Direction,request.Quantity,request.Type
 if not b or (side~=1 and side~=-1) or not integer(qty) or qty<1 then return false,"Choose a market, Buy or Sell, and a whole number of contracts starting at 1." end
 if not a.Player and qty>(a.LiquidityProvider and 100000000 or 10000) then return false,"Invalid quantity." end
 if kind~="Market" and kind~="Limit" and kind~="Stop" then return false,"Use Market, Limit or Stop." end
 local execution=request.Execution or (request.ReduceOnly==true and "Sliced" or "Immediate")
 if execution~="Immediate"and execution~="Sliced"then return false,"Choose immediate or sliced execution."end
 local p=a.Positions[b.Key]
 local reducing=request.ReduceOnly==true
 local protection=internal and internal.Protection
 if protection and (not reducing or not p or internal.PositionId~=p.Id or side~=-p.Direction
  or not(protection=="Take profit"and p.Target==request.Price and kind=="Limit"and(not p.Triggered or p.Triggered==protection)
   or protection==p.Triggered and(protection=="Stop loss"or protection=="Account depleted"or protection=="Margin liquidation"or protection=="Account reset"and a.Resetting)))then
  return false,"Protective exit no longer matches its position."
 end
 if reducing and (not p or p.Direction==side or qty>p.Quantity) then return false,"No matching position to reduce." end
 if a.Player and self.ConnectedOwners and not self.ConnectedOwners[owner]and not reducing then return false,"Player is no longer connected."end
 if a.Locked and not reducing then return false,"Account failed. Maximum currently available: 0 "..b.Key..". Close positions only." end
 if a.Player and b.Spec.CloseOnly and not reducing then return false,b.Key.." is a retired market and is close-only. Choose an available market for new trades." end
 if a.Liquidating and not reducing then return false,"Closing failed account positions. Maximum currently available: 0 "..b.Key..". Wait for positions to close." end
 local price=request.Price
 if kind=="Limit" or kind=="Stop" then
  if not finite(price) or price<=0 or math.abs(price/b.Spec.Tick-math.round(price/b.Spec.Tick))>0.00001 then return false,kind.." price must match the market's price increments (ticks)." end
  price=math.round(price/b.Spec.Tick)
  if not protection and math.abs(price-(b.Last or b.Reference))>(b.Last or b.Reference)*self.Config.PriceBandFraction then return false,kind.." is outside the price band." end
 end
 -- Stop entries wait off-book and become market orders when a trade reaches the stop price.
 -- A buy stop sits above the last trade and a sell stop below it; exits use SL/TP instead.
 if kind=="Stop" then
  if reducing or not a.Player then return false,"Stop orders are entry orders for player accounts. Use SL/TP to protect a position." end
  local last=b.Last or b.Reference
  if (price-last)*side<=0 then return false,side==1 and "Stop buy must be above the current price." or "Stop sell must be below the current price." end
 end
 -- Normalize once on the server; callers cannot smuggle conflicting distances.
 request=copy(request)
 for _,field in ipairs({"Stop","Target"}) do
  if request[field.."Dollars"]~=nil then
   if request[field.."Ticks"]~=nil then return false,"Use dollars or ticks, not both." end
   local resolved,err=Protection.Resolve(b.Spec,qty,request[field.."Dollars"])
   if not resolved then return false,err end
   request[field.."Ticks"]=resolved.Ticks
  end
 end
 for _,field in ipairs({"StopTicks","TargetTicks"}) do
  local v=request[field]
  if v~=nil and (not integer(v) or v<1 or v>Protection.MaximumTicks(b.Spec,qty))then
   return false,"Protection must use positive whole ticks within the $1,000,000,000 amount limit."
  end
 end
 if a.Player then
  local n=0 for id in pairs(a.OpenOrders) do if not self.Orders[id].Protection then n+=1 end end
  if n>=self.Config.MaxPlayerOrders and not reducing then return false,"Too many working orders. Maximum currently available: 0 "..b.Key..". Cancel an order first." end
  if not reducing then
   local maximum=self:OrderCapacity(a,b.Key,side,request.StopTicks)
   if qty>maximum then return false,self:CapacityMessage(a,b.Key,side,request.StopTicks) end
  end
 end
 if not a.Player and not reducing and not self:Exposure(a,b.Key,side,qty) then return false,"Insufficient margin or inventory capacity." end
 if kind=="Limit"and execution=="Immediate"and not PlayerExecution.StandardLimitAllowed(self,a,b,{Direction=side,Contract=b.Key},price,qty)then
  return false,"Limit order exceeds current execution safeguards. Choose a non-marketable price or reduce quantity. No order placed."
 end
 self:_pruneBook(b)
 local opposing=side==1 and b.Asks or b.Bids
 self.NextOrder+=1
 local o={Id=self.NextOrder,Priority=self:_priority(),Owner=owner,Contract=b.Key,Direction=side,Original=qty,Remaining=qty,Filled=0,Cancelled=0,Notional=0,
  Price=price,Type=kind,Status="Working",Time=self.Time,Reference=opposing[1] and opposing[1].Price or b.Last or b.Reference,
  SubmittedStep=self.Step,RequestSequence=self.RequestContext and self.RequestContext.Sequence,
  StopTicks=request.StopTicks,TargetTicks=request.TargetTicks,ReduceOnly=reducing,Expires=request.Expires,
  ReductionPosition=reducing and p.Id or nil,
  Execution=execution,Immediate=internal and internal.Immediate or nil,
  Protection=protection,ProtectivePosition=protection and p.Id or nil,
  Link=integer(request.Link) and request.Link or nil} -- server-set lead order id for copied orders
 self.Orders[o.Id]=o a.OpenOrders[o.Id]=true
 if protection=="Take profit"then p.TargetOrder=o.Id;if p.Triggered==protection then p.ExitOrder=o.Id end end
 if protection and internal.DeferProtection then
  local crossed=opposing[1]and(opposing[1].Price-price)*side<=0
  if crossed or self.ConnectedOwners and not self.ConnectedOwners[owner]or not PlayerExecution.Allows(self,b,price,side)then
   o.Queued=true;o.Status="Waiting for matching"
  else self:_rest(b,o)end
  return true,{Id=o.Id,Filled=0,Remaining=qty,Cancelled=0,Status=o.Status}
 end
 if kind=="Stop" then
  -- Armed, not matched: the order reserves capacity like a working limit until it triggers.
  o.Status="Armed" local index=self:_stopIndex() index[b.Key]=index[b.Key] or {} index[b.Key][o.Id]=true
  a.Revision+=1
  return true,{Id=o.Id,Filled=0,Remaining=o.Remaining,Cancelled=0,Average=nil,Status="Stop armed",Slippage=0}
 end
 if internal and internal.AdministrativeSettlement and a.Player and reducing then
  self:_playerFill(o,self:_touch(b,side),qty);self:_retire(o,"Filled")
  return true,{Id=o.Id,Filled=o.Filled,Remaining=0,Cancelled=0,Average=o.Notional/o.Filled,Status=o.Status}
 end
 return self:_match(a,b,o)
end
function Engine:_match(a,b,o)
 -- Check only orders reached by this match. Whole-book maintenance runs once at
 -- a simulation boundary; client snapshots never retire orders or affect replay.
 local wasQueued=o.Queued;o.Queued=nil
 local side=o.Direction;local reducing=o.ReduceOnly
 local managed=a.Player and self.Config.PlayerExecution
 local protected=Protective.Valid(self,a,o)
 local sliced=o.Execution=="Sliced"or wasQueued and o.Execution==nil
 local allowance=protected and math.huge or managed and math.min(sliced and self.Config.PlayerExecution.SliceContracts or math.huge,PlayerExecution.Budget(self,a,b,o))or math.huge
 local limited=false
 if not reducing and o.Type=="Limit"and not PlayerExecution.Allows(self,b,o.Price,side)then
  limited=true;self:_blocked(o,"Waiting · price safeguard")
 end
 local opposing=side==1 and b.Asks or b.Bids
 for _,level in ipairs(opposing)do
  if o.Remaining<=0 or self:_available(o,false)<=0 then break end
  if o.Type=="Limit"and (level.Price-o.Price)*side>0 then break end
  if allowance<=0 or not PlayerExecution.Allows(self,b,level.Price,side)then
   limited=true;self:_blocked(o,allowance<=0 and "Waiting · execution allowance"or "Waiting · price safeguard");break
  end
  for _,resting in ipairs(level.Orders)do
   local incoming=self:_available(o,false)
   if o.Remaining<=0 or incoming<=0 then break end
   if resting.Remaining>0 then
    local ra=self.Accounts[resting.Owner]
    if resting.Owner==o.Owner or (a.Group and ra.Group==a.Group)or (a.ProfileId and ra.ProfileId==a.ProfileId)then
     resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"Self-trade prevented");ra.Revision+=1
    else
     local available,reason=self:_available(resting,true)
     if available<=0 then
      self:_blocked(resting,reason);resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"No longer eligible");ra.Revision+=1
     else
      local quantity=math.min(incoming,available,allowance)
      if quantity<=0 then limited=true;break end
      self:_blocked(o,nil)
      self:_trade(b,o,resting,quantity);allowance-=quantity
      if allowance<=0 and o.Remaining>0 then limited=true end
      if resting.Remaining==0 then self:_retire(resting,"Filled")end
     end
    end
   end
  end
 end
 local available,unavailableReason=self:_available(o,false)
 if o.Remaining>0 and available<=0 then self:_blocked(o,unavailableReason)end
 self:_cleanBook(b)
 if o.Remaining==0 then if self.Orders[o.Id]then self:_retire(o,"Filled")end
 elseif not a.Player and reducing and o.Type=="Limit"and limited and self:_available(o,false)>0 then
  -- Keep a blocked bot TP's identity. The existing queue retries it without
  -- creating another order on every step, and it can never reduce a new position.
  o.Queued=true;o.Status="Waiting for matching"
 elseif protected and self:_available(o,false)>0 and (limited or o.Type=="Market"or self:_available(o,true)<=0)then
  o.Queued=true;o.Status="Waiting for matching";o.BlockedReason=o.BlockedReason or "Waiting for liquidity"
 elseif self:_available(o,true)>0 and managed and sliced and not o.Immediate
  and (o.Type=="Market"
   or o.Type=="Limit" and limited)then
  o.Queued=true;o.Status="Executing in slices"
 elseif o.Type=="Market"or self:_available(o,true)<=0 or limited and not(o.Type=="Limit"and o.Execution=="Immediate")then
  o.Cancelled+=o.Remaining;o.Remaining=0;self:_retire(o,o.Filled>0 and "Partial / IOC"or "No liquidity")
 elseif o.Type=="Limit"and opposing[1]and(opposing[1].Price-o.Price)*side<=0 then
  -- A guard-blocked crossing cannot leave a crossed resting book, for any owner.
  o.Cancelled+=o.Remaining;o.Remaining=0;self:_retire(o,"Price safeguard")
 else self:_rest(b,o)end
 a.Revision+=1
 self:_syncReductions()
 Protective.Sync(self)
 local average=o.Filled>0 and o.Notional/o.Filled or nil
 return true,{Id=o.Id,Filled=o.Filled,Remaining=o.Remaining,Cancelled=o.Cancelled,Average=average,Status=o.Status,Queued=o.Queued,
  Slippage=average and (average-o.Reference*b.Spec.Tick)*side or 0}
end
function Engine:ProcessPlayerOrders()PlayerExecution.Process(self)end
function Engine:ProcessStops()
 Protective.Sync(self)
 -- Bounded queue also handles cascades; deferred tails continue next scheduler step.
 local processed=0
 while #self.PendingStops>0 and processed<200 do
  local item=table.remove(self.PendingStops,1) local a=self.Accounts[item.Owner] local p=a and a.Positions[item.Contract]
  processed+=1
  if p and p.Id==item.Position and p.Triggered then
   if a.Player and p.Triggered=="Take profit"then
    -- Keep the residual TP and SL; cancel only competing entry/voluntary orders.
    for _,id in ipairs(sortedKeys(a.OpenOrders))do
     local o=self.Orders[id];if o and o.Contract==item.Contract and id~=p.TargetOrder then self:Cancel(a.Id,id)end
    end
    p.ExitOrder=p.TargetOrder
    local target=p.TargetOrder and self.Orders[p.TargetOrder]
    if target and target.Queued then self:_match(a,self.Books[item.Contract],target)end
    continue
   end
   local exit=p.ExitOrder and self.Orders[p.ExitOrder]
   if exit and exit.Protection and exit.Protection~=p.Triggered then self:Cancel(a.Id,exit.Id);exit=nil end
   if exit and exit.Protection and exit.Queued then self:_match(a,self.Books[item.Contract],exit)end
   if not exit then
    self:CancelAll(a.Id,item.Contract)
    if not BotExitRetry.Ready(self,a,item.Contract,p)then continue end
    local target=p.Triggered=="Take profit"and p.Target
    local ok,result=self:Submit(a.Id,{Contract=item.Contract,Direction=-p.Direction,
     Quantity=a.Player and self.Config.PlayerExecution and p.Quantity or math.min(p.Quantity,a.Player and self.Config.MaxPlayerQuantity or 10000),
     Type=target and "Limit"or "Market",Price=target,ReduceOnly=true},a.Player and p.Triggered~="Player close"and {Protection=p.Triggered,PositionId=p.Id}or nil)
    BotExitRetry.Attempted(self,a,item.Contract,p)
    if ok and result.Remaining>0 then p.ExitOrder=result.Id end
   end
  end
 end
 self:_triggerStops()
end
-- Triggered stop entries become ordinary market orders, in order-id sequence. While its market order is
-- checked the stop stops reserving capacity, so Submit applies every current rule once (contract cap, buying
-- power, depletion, order limits): a stop can never fill past the cap. A rejection ends the stop. If the
-- Explicit sliced stops retain their remainder in the execution queue. Standard stops cancel
-- unfilled quantity after their immediate attempt; the short retry path supports legacy orders.
Engine.StopRetrySeconds=5
function Engine:_triggerStops()
 local ready={}
 for _,ids in pairs(self:_stopIndex()) do for id in pairs(ids) do local o=self.Orders[id] if o and o.Triggered then table.insert(ready,id) end end end
 if #ready==0 then return end
 table.sort(ready)
 for _,id in ipairs(ready) do
  local o=self.Orders[id]
  if o then
   local a=self.Accounts[o.Owner] local b=self.Books[o.Contract]
   if self.Config.PlayerExecution and o.Execution=="Sliced"then
    local triggerPrice=o.Price*b.Spec.Tick
    self:_stopIndex()[o.Contract][o.Id]=nil
    o.Type="Market";o.Price=nil;o.Triggered=nil
    local _,result=self:_match(a,b,o)
    a.Triggers=a.Triggers or {}
    table.insert(a.Triggers,1,{Id=o.Id,Contract=o.Contract,Direction=o.Direction,Quantity=o.Original,Price=triggerPrice,
     Ok=result.Filled>0 or result.Queued==true,Filled=result.Filled,Average=result.Average,Queued=result.Queued,Remaining=result.Remaining,Time=self.Time})
    if #a.Triggers>8 then table.remove(a.Triggers)end
    continue
   end
   a.OpenOrders[o.Id]=nil
   local ok,result=self:Submit(o.Owner,{Contract=o.Contract,Direction=o.Direction,Quantity=o.Remaining,Type="Market",
    StopTicks=o.StopTicks,TargetTicks=o.TargetTicks,Link=o.Link},{Immediate=true})
   local filled=ok and result.Filled or 0
   if filled>0 then
    o.Remaining-=filled o.Cancelled+=filled -- converted into the child market order that holds the fill
    o.Converted=(o.Converted or 0)+filled o.ConvertedNotional=(o.ConvertedNotional or 0)+result.Average*filled
   end
   local waiting=ok and o.Execution~="Immediate"and o.Remaining>0 and self.Time-o.Triggered<Engine.StopRetrySeconds and not a.Locked
   if waiting then a.OpenOrders[o.Id]=true
   else
    local status=not ok and "Rejected" or o.Remaining>0 and (filled>0 or o.Converted) and "Partial / IOC" or o.Remaining>0 and "No liquidity" or "Triggered"
    local unfilled=o.Remaining o.Cancelled+=unfilled o.Remaining=0
    a.OpenOrders[o.Id]=true self:_retire(o,status)
    local done=o.Converted or 0
    a.Triggers=a.Triggers or {}
    table.insert(a.Triggers,1,{Id=o.Id,Contract=o.Contract,Direction=o.Direction,Quantity=o.Original,Price=o.Price*b.Spec.Tick,Ok=done>0,
     Filled=done,Average=done>0 and o.ConvertedNotional/done or nil,Message=not ok and result or unfilled>0 and ("No liquidity for "..unfilled) or nil,Time=self.Time})
    if #a.Triggers>8 then table.remove(a.Triggers) end
   end
   a.Revision+=1
  end
 end
end
function Engine:AdvanceClock(dt)
 self.Time+=dt self.Step+=1
 for _,id in ipairs(sortedKeys(self.Orders)) do
  local o=self.Orders[id] if o.Expires and o.Expires<=self.Time then self:Cancel(o.Owner,id) end
 end
 for _,id in ipairs(self.AccountOrder) do
  local a=self.Accounts[id]
  if a.House then continue end -- counterparty of player fills; it has no risk limits and never trades
  if a.Archive then continue end -- folded finished attempts: flat, retired ledger totals only
  local summary=self:Summary(a)
  if not next(a.Positions) then a.Liquidating=nil end
  if summary.Equity<=0 or (not a.Player and summary.Margin>math.max(0,summary.Equity)*1.05) then
   if summary.Equity<=0 then a.Locked=true if a.Player and not a.Depleted then a.Depleted=true a.DepletedAt=self.Time end end
   a.Liquidating=true self:CancelAll(id)
   for _,key in ipairs(self.Config.ContractOrder) do local p=a.Positions[key] if p then p.Triggered=a.Resetting and "Account reset"or a.Locked and "Account depleted" or "Margin liquidation" p.Stop=nil p.Target=nil end end
  end
  for _,key in ipairs(self.Config.ContractOrder) do
   local p=a.Positions[key] if p and p.Triggered then table.insert(self.PendingStops,{Owner=id,Contract=key,Position=p.Id}) end
  end
 end
 self:ProcessStops()
end
-- Atomic amendment: validate before touching the working order. Preserve its identity, quantity,
-- attached protection and copy links. A newly marketable price follows normal player-limit fills.
function Engine:AmendOrder(owner,request)
 local a=self.Accounts[owner]
 local o=type(request)=="table" and self.Orders[request.OrderId]
 if not a or not a.Player or not o or o.Protection or o.Owner~=owner or o.Contract~=request.Contract or o.Type~="Limit" or o.Remaining<=0 then
  return false,"Limit order is no longer working."
 end
 if a.Locked or a.Liquidating then return false,"Account failed. This limit order cannot be changed." end
 local b=self.Books[o.Contract] local tick=b.Spec.Tick
 if not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-o.Price*tick)>tick*.00001 or request.ExpectedQuantity~=o.Remaining then
  return false,"Limit order changed while dragging. Please try again."
 end
 local price=request.Price
 if not finite(price) or price<=0 or math.abs(price/tick-math.round(price/tick))>.00001 then return false,"Limit price must match the market's price increments (ticks)." end
 local ticks=math.round(price/tick) local last=b.Last or b.Reference
 local quantity=request.Quantity or o.Remaining
 if not integer(quantity)or quantity<1 then return false,"Amended remaining quantity must be a positive whole number."end
 if o.ReduceOnly then local p=a.Positions[o.Contract]
  if not p or p.Direction==o.Direction or quantity>p.Quantity then return false,"No matching position to reduce."end
 end
 if math.abs(ticks-last)>last*self.Config.PriceBandFraction then return false,"Limit is outside the price band." end
 if not o.ReduceOnly and self:OrderCapacity(a,o.Contract,o.Direction,o.StopTicks,o.Id)<quantity then return false,"Account contract limit changed. Cancel another order first." end
 if ticks==o.Price and quantity==o.Remaining then return true,"Limit price is unchanged."end
 if ticks==o.Price and quantity<o.Remaining then
  local removed=o.Remaining-quantity;o.Cancelled+=removed;o.Remaining=quantity;self:_cleanBook(b);a.Revision+=1
  b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
  return true,{Id=o.Id,Amended=true,Filled=0,Cancelled=removed,Remaining=quantity,Status=o.Status,Direction=o.Direction,Price=price}
 end
 if o.Execution=="Immediate"and not PlayerExecution.StandardLimitAllowed(self,a,b,o,ticks,quantity)then
  return false,"Move rejected by current execution safeguards. Your original limit order is unchanged. Try a non-marketable price or wait for capacity."
 end
 self:_unrest(b,o)
 if quantity>o.Remaining then o.Original+=quantity-o.Remaining else o.Cancelled+=o.Remaining-quantity end
 o.Remaining=quantity
 o.Price=ticks;o.Time=self.Time;o.Priority=self:_priority()
 local filled,notional,cancelled=o.Filled,o.Notional,o.Cancelled
 local ok,result=self:_match(a,b,o)
 -- Report only this amendment's executions, not fills from before the drag.
 -- Zero remaining can also mean cancellation; it does not prove a full fill.
 result.Filled=o.Filled-filled;result.Cancelled=o.Cancelled-cancelled
 result.Average=result.Filled>0 and (o.Notional-notional)/result.Filled or nil
 result.Amended=true;result.Direction=o.Direction;result.Price=price
 return ok,result
end
function Engine:AmendProtection(owner,request)
 local a=self.Accounts[owner]
 if not a or type(request)~="table" then return false,"Unknown account." end
 local field=request.Protection
 if field~="Stop" and field~="Target" then return false,"Invalid protection." end
 local b=self.Books[request.Contract] local p=a.Positions[request.Contract]
 if not b or not p or p.Id~=request.OrderId or p.Triggered or a.Locked then
  return false,"Protection already triggered, cancelled or position closed."
 end
 local creating=request.Create==true
 if request.ExpectedQuantity~=nil and request.ExpectedQuantity~=p.Quantity then return false,"Position size changed while dragging. Please try again."end
 if creating and (p[field]~=nil or request.ExpectedPrice~=nil or request.ExpectedQuantity~=p.Quantity)then return false,"Position or protection changed. Please try again."end
 if not creating and (not p[field] or not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-p[field])>b.Spec.Tick*0.00001) then
  return false,"Protection changed while dragging. Please try again."
 end
 local price=request.Price local tick=b.Spec.Tick
 if not finite(price) or price<=0 or math.abs(price/tick-math.round(price/tick))>0.00001 then
  return false,"Protection price must match the market's price increments (ticks)."
 end
 price=math.round(price/tick)*tick
 local last=(b.Last or b.Reference)*tick
 -- SL/TP close an existing position. Ticket protections can already lie beyond
 -- the entry-order price band, so do not apply that band when creating or moving them.
 if creating then
  local fromEntry=(price-p.Entry)*p.Direction
  if field=="Stop" and fromEntry>=0 or field=="Target" and fromEntry<=0 then return false,"Choose the correct side of the entry price."end
 end
 local distance=(price-last)*p.Direction
 if (field=="Stop" and distance>=0) or (field=="Target" and distance<=0) then
  return false,field=="Stop" and "Place stop loss beyond the current price in the losing direction." or "Place take profit beyond the current price in the winning direction."
 end
 -- A valid stop may sit beyond the account's equity. Depletion is enforced from
 -- actual execution prices, independently of the configured protection level.
 p[field]=price p["Manual"..field]=true a.Revision+=1
 Protective.Mark(self,a,b.Key);Protective.Sync(self)
 return true,string.format("%s moved to %.2f.",field=="Stop" and "Stop loss" or "Take profit",price)
end
function Engine:CancelProtection(owner,id,field)
 if field~="Stop" and field~="Target" then return false,"Invalid protection." end
 for _,key in ipairs(self.Config.ContractOrder) do
  local p=self.Accounts[owner].Positions[key]
  if p and p.Id==id and not p.Triggered then
   p[field]=nil;p["Manual"..field]=nil;self.Accounts[owner].Revision+=1
   Protective.Mark(self,self.Accounts[owner],key);Protective.Sync(self)
   return true,"Protection cancelled."
  end
 end
 return false,"Protection already triggered or position closed."
end
function Engine:Snapshot(owner,key,timeframe,full)
 local a=self.Accounts[owner] local positions,orders={},{}
 local protectiveExits={}
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol]
  if p then
   positions[symbol]=copy(p)
   positions[symbol].Unrealized=((self.Books[symbol].Last or self.Books[symbol].Reference)*self.Books[symbol].Spec.Tick-(p.PnlEntry or p.Entry))*p.Quantity*p.Direction*self.Books[symbol].Spec.Multiplier
   for _,field in ipairs({"Stop","Target"}) do if p[field] then
    local kind=field=="Stop"and "Stop loss"or "Take profit"
    local closing=p.Triggered==kind
    local exit=self.Orders[field=="Target"and p.TargetOrder or p.ExitOrder]
    if exit and exit.ReduceOnly and exit.Contract==symbol and (closing or field=="Target")then protectiveExits[exit.Id]=true end
    local status,filled=Protective.Status(self,a,p,field)
    table.insert(orders,{Id=p.Id,Contract=symbol,Quantity=p.Quantity,Filled=filled,
     Kind=kind..(closing and (p.Direction==-1 and " · closing short"or " · closing long")or ""),Price=p[field],Protection=field,
     Closing=closing,Status=status})
   end end
  end
 end
 for _,id in ipairs(sortedKeys(a.OpenOrders)) do
  local o=self.Orders[id] if o and not protectiveExits[id]then local blocked=self:OrderBlockReason(o);table.insert(orders,{Id=id,Contract=o.Contract,Quantity=o.Remaining,Original=o.Original,Filled=o.Filled,
   Kind=(o.Protection=="Account reset"and "Reset liquidation · "or "")..(o.Type=="Stop" and "Stop " or o.Type=="Market" and "Market " or "Limit ")..(o.Direction==1 and "Buy" or "Sell"),Type=o.Type,Direction=o.Direction,Queued=o.Queued,Execution=o.Execution,
   Price=o.Price and o.Price*self.Books[o.Contract].Spec.Tick or nil,BlockedReason=blocked,Status=o.Protection=="Account reset"and (o.Filled.." filled · "..o.Remaining.." remaining · "..(blocked or "Liquidating"))or blocked or o.Queued and "Executing in slices"or o.Type=="Stop" and (o.Triggered and "Triggered" or "Armed") or o.Filled>0 and "Partial" or "Working"}) end
 end
 local quotes={};local dayStart=math.floor(self.Time/86400)*86400
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local b=self.Books[symbol] local tick=b.Spec.Tick
  if b.Spec.CloseOnly and not a.Positions[symbol] then continue end
  -- Read-only executable depth. Invalid/blocked quotes remain diagnosable in the
  -- owner's order status but are never advertised as available liquidity.
  local depth={Bids={},Asks={}};local summaries={}
  for _,side in ipairs({"Bids","Asks"})do
   local direction=side=="Asks"and 1 or -1
   for _,level in ipairs(b[side])do
    if not PlayerExecution.Allows(self,b,level.Price,direction)then break end
    local quantity=0;for _,o in ipairs(level.Orders)do quantity+=self:_available(o,true,summaries)end
    if quantity>0 then table.insert(depth[side],{Price=level.Price*tick,Quantity=quantity})end
    if #depth[side]>=(self.Config.DepthLevels or 5)then break end
   end
  end
  local bid=depth.Bids[1]and depth.Bids[1].Price local ask=depth.Asks[1]and depth.Asks[1].Price
  -- Use the executed daily candle, independent of the subscribed chart timeframe.
  -- Before today's first trade, the unchanged last price represents a flat day.
  local daily=b.Candles["1D"];local today=daily and daily[#daily]
  local dayOpen=today and today.Time==dayStart and today.Open or (b.Last and b.Last*tick)
  quotes[symbol]={Last=b.Last and b.Last*tick,Open=b.Open and b.Open*tick,Bid=bid,Ask=ask,Spread=bid and ask and ask-bid,
   DayOpen=dayOpen,DayStart=dayStart,
   Volume=b.Volume,TradeCount=b.Up+b.Down,Recent={},Depth=depth}
  for i=math.max(1,#b.Recent-15),#b.Recent do table.insert(quotes[symbol].Recent,b.Recent[i]*tick) end
 end
 local series=self.Books[key].Candles[timeframe] local candles={}
 for i=full and 1 or math.max(1,#series-1),#series do table.insert(candles,copy(series[i])) end
 -- Current maximum new order per instrument and side (the same rule Submit enforces), for the ticket and chart menu.
 local capacity
 if a.Player then
  capacity={}
  for _,symbol in ipairs(self.Config.ContractOrder) do
   if not self.Books[symbol].Spec.CloseOnly then
    local buy=a.Locked and 0 or (self:OrderCapacity(a,symbol,1)) local sell=a.Locked and 0 or (self:OrderCapacity(a,symbol,-1))
    capacity[symbol]={Buy=buy,Sell=sell}
   end
  end
 end
 return {Seed=self.Seed,Time=self.Time,Step=self.Step,Quotes=quotes,Positions=positions,Orders=orders,History=a.History,Fills=a.Fills,
  Base=a.Base,Summary=self:Summary(a),Contract=key,Timeframe=timeframe,Candles=candles,Full=full,Revision=a.Revision,Locked=a.Locked,
  Capacity=capacity,Limit=a.Player and self:ContractLimit(a) or nil,Triggers=a.Triggers}
end
function Engine:Audit()
 local cash,equity,inventory,volume=0,0,{},0
 for _,key in ipairs(self.Config.ContractOrder) do inventory[key]=0 end
 for _,id in ipairs(self.AccountOrder) do
  local a=self.Accounts[id] cash+=a.CashFlow equity+=self:Summary(a).Equity-a.Base
  assert(math.abs(a.Balance-a.Base-(a.PnlBaseline or 0)-a.Realized)<0.001,"Balance / realized reconciliation")
  if a.PnlBaseline then
   assert(not a.Player and not a.House and not a.Archive,"Invalid bot accounting baseline")
   assert(math.abs(a.Base-a.StartingCapital-a.NetCapitalAdjustments)<0.001,"Bot capital reconciliation")
   local marked=a.CashFlow
   for key,p in pairs(a.Positions)do local b=self.Books[key]
    marked+=(b.Last or b.Reference)*b.Spec.Tick*p.Quantity*p.Direction*b.Spec.Multiplier
   end
   assert(math.abs(self:Summary(a).Equity-a.Base-marked)<0.01,"Bot cash / marked equity reconciliation")
  end
  local st=a.Stats
  if a.Player and type(st)=="table" then
   assert(math.abs(a.Realized-(st.Gains-st.Loss+st.UntrackedNet))<0.01,"Lifetime stats / realized reconciliation")
   assert(st.Trades==st.Wins+st.Losses+st.Even,"Lifetime stats trade classification")
  end
  for key,p in pairs(a.Positions) do inventory[key]+=p.Quantity*p.Direction end
 end
 assert(math.abs(cash)<0.01,"Notional cash is not conserved") assert(math.abs(equity)<0.01,"Total marked P&L is not zero")
 for _,key in ipairs(self.Config.ContractOrder) do
  assert(inventory[key]==0,"Inventory is not conserved") local b=self.Books[key] volume+=b.Volume
  for _,tf in ipairs(self.Config.Timeframes) do assert((b.CandleVolume[tf[1]] or 0)==b.Volume,"Candle volume mismatch") end
  for _,side in ipairs({b.Bids,b.Asks}) do
   for _,l in ipairs(side) do local total=0 local arrival=0 for _,o in ipairs(l.Orders) do
    assert(o.Remaining>0 and self.Orders[o.Id]==o,"Stale resting order") assert((o.Priority or o.Id)>arrival,"FIFO violated") arrival=o.Priority or o.Id total+=o.Remaining
   end assert(total==l.Quantity,"Level quantity mismatch") end
  end
  assert(not b.Bids[1] or not b.Asks[1] or b.Bids[1].Price<b.Asks[1].Price,"Crossed resting book")
 end
 for _,list in ipairs({self.Orders,self.OrderArchive}) do for _,o in pairs(list) do assert(o.Original==o.Filled+o.Remaining+o.Cancelled,"Order quantity mismatch") end end
 assert(volume==self.TotalVolume,"Total volume mismatch")
 return {CashError=cash,EquityError=equity,Inventory=inventory,Volume=volume,Trades=self.NextTrade,Hash=self.TradeHash}
end
return Engine
]====]):sub(2),Hash=([====[!c21290936a7bd58a805119e3f5e14259349a79598730d41ae35cb6d6c85a88c0]====]):sub(2),ExpectedHash=([====[!89be02e0df95783388b0510ba8e4efa3e71c89e6a049ce8ae07dbcac9c2f9f4d]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotPopulation]====]):sub(2)]={Source=([====[!-- Versioned bot funding and behavioral policy. No storage or network access.
local Policy={}
local function active(p,a)return not p.Engine.Books[a.Key].Spec.CloseOnly and not a.Retiring end
function Policy.Configure(p,a)
 local c=p.Config.BotPopulation;if not c or p.Engine.Books[a.Key].Spec.CloseOnly then return end
 local r=p.Random;local spec=p.Engine.Books[a.Key].Spec
 a.Budget=assert(c.Capital[a.Kind]);a.PolicyVersion=c.Version
 -- Scale by the generator's tick volatility in dollars; actual margin remains authoritative.
 local scale=math.clamp(c.ReferenceDollarVolatility/(spec.Tick*spec.Multiplier*spec.Scale),0.25,1)
 if a.Kind~='Reserve'then a.Size=math.max(1,math.floor(a.Size*scale))end
 a.Limit=math.max(a.Size,math.floor(a.Limit*scale))
 a.Lookback=r:Int(8,60);a.EntryThreshold=r:Range(.5,1.2)
 a.SignalWeight=r:Range(.6,1.5);a.ValueOffset=r:Noise()*3*spec.Scale
 a.BeliefHalfLife=r:Range(c.ValueHalfLife[1],c.ValueHalfLife[2])
 a.ObservationSeconds=r:Range(c.ValueObservationSeconds[1],c.ValueObservationSeconds[2])
 a.ObservationNoise=r:Range(c.ValueNoiseTicks[1],c.ValueNoiseTicks[2])*spec.Scale
 a.ObservedAt=p.Engine.Time;a.NextObservation=p.Engine.Time+r:Range(.25,a.ObservationSeconds)
 a.EntryBuffer=r:Range(2,6);a.MinMove=r:Range(c.ScalperMinMoveTicks[1],c.ScalperMinMoveTicks[2])
 if a.Kind=='Maker'then a.Speed*=c.MakerActivityScale
 elseif a.Kind=='Whale'then a.Speed*=c.WhaleActivityScale
 elseif a.Kind=='Reserve'then a.Limit=p.Config.Reserve.InventoryLimit
 elseif a.Kind=='Scalper'then a.Limit=a.Size;a.Lookback=r:Int(8,35)
 else a.Speed*=c.TraderActivityScale end
 a.Limit=math.min(a.Limit,math.floor(a.Budget*a.Risk*c.MarginFraction/spec.Margin))
 assert(a.Limit>=1 and a.Size>=1,'Bot funding cannot support a contract')
 a.Size=math.min(a.Size,a.Limit)
end
function Policy.Validate(p)
 local c=p.Config.BotPopulation;if not c then return end
 local seen,counts={},{}
 for _,a in ipairs(p.Agents)do
  assert(not seen[a.Id],'Duplicate participant id');seen[a.Id]=true
  assert(p.Engine.Accounts[a.Id] and not p.Engine.Accounts[a.Id].Player,'Invalid bot account')
  if active(p,a)then
   assert(c.Counts[a.Kind],'Unknown active bot group')
   local ac=p.Engine.Accounts[a.Id]
   assert(ac.StartingCapital and math.abs(ac.Base-ac.StartingCapital-(ac.NetCapitalAdjustments or 0))<.001,'Bot capital ledger differs')
   assert(ac.PolicyCapitalTarget==c.Capital[a.Kind]and a.Budget==c.Capital[a.Kind],'Bot funding policy differs')
   counts[a.Key]=counts[a.Key]or {};counts[a.Key][a.Kind]=(counts[a.Key][a.Kind]or 0)+1
  end
 end
 for _,key in ipairs(p.Config.ContractOrder)do if not p.Engine.Books[key].Spec.CloseOnly then
  for _,kind in ipairs(c.Order)do assert((counts[key]and counts[key][kind]or 0)==c.Counts[kind],key..' '..kind..' population differs')end
 end end
end
-- Pure inspection. Existing accounts are retained in sorted id order, including opaque renamed ids.
function Policy.Plan(p)
 local c=assert(p.Config.BotPopulation);local report={Version=c.Version,FromVersion=p.PolicyVersion or 0,
  Needed=(p.PolicyVersion or 0)<c.Version,Markets={},Accounts={},Add={},Retire={},FundingAdjustment=0}
 if not report.Needed then Policy.Validate(p);return report end
 local seen={}
 for _,a in ipairs(p.Agents)do assert(not seen[a.Id],'Duplicate participant id');seen[a.Id]=true end
 for _,key in ipairs(p.Config.ContractOrder)do if not p.Engine.Books[key].Spec.CloseOnly then
  local groups={};report.Markets[key]=groups
  for _,kind in ipairs(c.Order)do
   local list={};for _,a in ipairs(p.Agents)do if a.Key==key and a.Kind==kind and not a.Retiring then table.insert(list,a)end end
   table.sort(list,function(a,b)return a.Id<b.Id end)
   groups[kind]={Before=#list,Target=c.Counts[kind],TargetCapital=c.Counts[kind]*c.Capital[kind]}
   for i,a in ipairs(list)do
    local ac=p.Engine.Accounts[a.Id];assert(ac and not ac.Player,'Invalid migration account')
    local keep=i<=c.Counts[kind];local s=p.Engine:Summary(ac)
    local delta=keep and math.round((c.Capital[kind]-s.Equity)*100)/100 or 0
    local cancel,exits={},{}
    for id in pairs(ac.OpenOrders)do local o=p.Engine.Orders[id];table.insert(o.ReduceOnly and exits or cancel,id)end
    table.sort(cancel);table.sort(exits)
    local positions={};for symbol,pos in pairs(ac.Positions)do table.insert(positions,{Market=symbol,Quantity=pos.Quantity,Direction=pos.Direction,Entry=pos.Entry})end
    table.sort(positions,function(a,b)return a.Market<b.Market end)
    table.insert(report.Accounts,{Id=a.Id,Key=key,Kind=kind,Keep=keep,EquityBefore=s.Equity,BaseBefore=ac.Base,
     Realized=ac.Realized,Unrealized=s.Unrealized,FundingAdjustment=delta,TargetEquity=keep and c.Capital[kind]or nil,
     CancelEntryOrders=cancel,PreserveExitOrders=exits,Positions=positions})
    report.FundingAdjustment+=delta
    if not keep then table.insert(report.Retire,a.Id)end
   end
   local missing=math.max(0,c.Counts[kind]-#list)
   if missing>0 then table.insert(report.Add,{Key=key,Kind=kind,Count=missing,CapitalEach=c.Capital[kind]})end
  end
 end end
 return report
end
function Policy.Apply(p)
 local c=p.Config.BotPopulation;if not c then return end
 assert((p.PolicyVersion or 0)<=c.Version,'Cannot downgrade bot population policy')
 local report=Policy.Plan(p);if not report.Needed then return report end
 local byId={};for _,a in ipairs(p.Agents)do byId[a.Id]=a end
 for index,row in ipairs(report.Accounts)do
  local a,ac=byId[row.Id],p.Engine.Accounts[row.Id]
  for _,id in ipairs(row.CancelEntryOrders)do p.Engine:Cancel(a.Id,id)end
  a.Quotes={};a.ReplenishAt={};a.Parent=0
  if row.Keep then
   -- Refresh the profile from current ranges, preserving identity and live exit state.
   local fresh=p:_profile(a.Key,a.Kind,index)
   for key,value in pairs(fresh)do if key~='Id' and key~='Next' then a[key]=value end end
   a.Next=p.Engine.Time+p.Random:Range(.25,18)
   ac.StartingCapital=ac.StartingCapital or ac.Base
   ac.NetCapitalAdjustments=(ac.NetCapitalAdjustments or 0)+row.FundingAdjustment
   ac.CapitalAdjustments=ac.CapitalAdjustments or {}
   table.insert(ac.CapitalAdjustments,{Version=c.Version,Time=p.Engine.Time,Amount=row.FundingAdjustment,
    EquityBefore=row.EquityBefore,TargetEquity=row.TargetEquity,Reason='Bot population migration'})
   ac.Base=ac.StartingCapital+ac.NetCapitalAdjustments;ac.Balance=ac.Base+(ac.PnlBaseline or 0)+ac.Realized
   ac.PolicyCapitalTarget=c.Capital[a.Kind];ac.Limit=a.Limit;ac.Risk=a.Risk;ac.LossLimit=ac.Base
   ac.Locked=false;ac.Revision+=1
   -- Existing triggered liquidations and positions are preserved; repair happens through matching.
  else
   a.Retiring=true;a.Next=p.Engine.Time+p.Random:Range(.25,18)
  end
 end
 for _,row in ipairs(report.Add)do p:_ensurePopulation({row.Key},row.Kind,c.Counts[row.Kind])end
 -- Exactly half of every active market's scalpers use each style, including renamed old ids.
 for _,key in ipairs(p.Config.ContractOrder)do
  local scalpers={};for _,a in ipairs(p.Agents)do if a.Key==key and a.Kind=='Scalper' and active(p,a)then table.insert(scalpers,a)end end
  table.sort(scalpers,function(a,b)return a.Id<b.Id end)
  for i,a in ipairs(scalpers)do a.Style=i%2==0 and 'Momentum'or 'Reversion'end
 end
 p.PolicyVersion=c.Version;p.MigrationReport=report
 Policy.Validate(p)
 return report
end
return Policy
]====]):sub(2),Hash=([====[!7513b696867a2a7593d732f1a7a974d8f229a707710dca29bbbdb58798a25b30]====]):sub(2),ExpectedHash=([====[!660e6e1d7d85c778b9f70d911620193dd11ac7a537ff2650d0317a88759813b1]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.WorldService]====]):sub(2)]={Source=([====[!-- A single shared exchange. Follower servers route players to its owner instead of creating another tape.
local RunService=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Lease=require(script.Parent.WorldLease)
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local BotRefresh=require(script.Parent.BotRefresh)
local Settings=require(script.Parent.WorldConfig)
local World={} World.__index=World
function World.new(config,options)
 options=options or {}
 local studio=options.Studio if studio==nil then studio=RunService:IsStudio()end
 local self=setmetatable({Config=config,Settings=options.Settings or Settings,Studio=studio,
  PlaceId=options.PlaceId or game.PlaceId,JobId=options.JobId or game.JobId,Now=options.Now or os.time,
  Mode="Connecting",Status="Connecting to the shared exchange",Busy=false,Closing=false,
  Healthy=false,NextSave=0,NextAttempt=0,Epoch=0,Store=options.Store},World)
 self.Identity={Token=Http:GenerateGUID(false),WorldId=Http:GenerateGUID(false),JobId=self.JobId,PlaceId=self.PlaceId}
 -- Private servers cannot be public teleport destinations. They only act as entry lobbies.
 self.CanOwn=options.CanOwn if self.CanOwn==nil then self.CanOwn=studio or game.PrivateServerId==""end
 return self
end
function World:_fresh()
 local seed=self.Studio and self.Settings.StudioReplaySeed or 0
 seed=seed or 0
 if seed==0 then seed=tonumber(Http:GenerateGUID(false):sub(1,8),16)%2147483646+1 end
 local engine=Engine.new(self.Config,seed) local population=Participants.new(engine)
 for i=1,math.floor(self.Config.WarmupSeconds/self.Config.StepSeconds)do
  population:Step() if i%200==0 then task.wait()end
 end
 return engine,population
end
function World:_encode(engine,population)
 engine=engine or self.Engine;population=population or self.Population
 local projection
 if self.CaptureProjection then
  -- Optional read model failures must never prevent an exchange save or trading.
  local ok,result=pcall(self.CaptureProjection,engine)
  if ok then projection=result else warn("[Get Funded!] Leaderboard projection unavailable: "..tostring(result)) end
 end
 -- Raw size is refused by Encode (before compression) with exactly the bound the reader enforces.
 local record=Checkpoint.EncodeWorld(engine,population,Checkpoint.MaxDecodedBytes)
 -- Measure the complete value UpdateAsync will store: lease fields plus this checkpoint, with headroom.
 local stored=self:_storedBytes(record,engine.Step)
 assert(stored+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Exchange checkpoint is too large; trading paused to protect saved state")
 self.LastRawBytes=record.RawBytes self.LastStoredBytes=stored
 return record,engine.Step,projection
end
function World:_storedBytes(record,step)
 local lease=self.Lease and self.Lease.Record
 local shell=lease and table.clone(lease) or {Version=1,WorldId=self.Identity.WorldId,Generation=1,SaveSequence=0}
 local now=self.Now()
 shell.Owner=self.Identity.Token shell.JobId=self.Identity.JobId shell.PlaceId=self.Identity.PlaceId
 shell.Checkpoint=record shell.SavedStep=step or self.Engine.Step shell.SavedAt=now
 shell.SaveSequence=(shell.SaveSequence or 0)+1 shell.LeaseUntil=now+self.Settings.LeaseSeconds
 return #Http:JSONEncode(shell)
end
-- False once the last saved checkpoint used the configured fraction of either size limit. Only new accounts
-- wait; trading and saving continue, and the unused room absorbs growth of the accounts that already exist.
-- kind "Start"/"Activate" (a first account or an earned tier) may use the band up to NewAccountCapacityFraction.
function World:HasCapacity(kind)
 local fraction=self.Settings.CapacityFraction or 0.8
 if kind=="Start" then fraction=math.max(fraction,self.Settings.NewAccountCapacityFraction or fraction) end
 if (self.LastRawBytes or 0)>=Checkpoint.MaxDecodedBytes*fraction then return false end
 if (self.LastStoredBytes or 0)>=self.Settings.MaxEncodedBytes*fraction then return false end
 return true
end
function World:_committed(rows)
 if not rows then return end
 local r=self.Lease.Record
 self.DurableProjection={Rows=rows,WorldId=r.WorldId,Sequence=r.SaveSequence,SavedAt=r.SavedAt}
end
function World:_sandbox(reason)
 self.Engine,self.Population=self:_fresh()
 self.Mode="Local" self.Status="LOCAL · NOT SAVED" self.Healthy=true self.Epoch+=1
 warn("[Get Funded!] Unsaved Studio sandbox: "..reason.." Publish a test experience and enable Studio API access for restart continuity.")
end
function World:Open()
 if self.Closing or self.Busy then return end
 self.Busy=true
 local ok,err=pcall(function()
  if not self.Settings.Enabled or self.PlaceId==0 then
   assert(self.Studio and self.Settings.AllowUnsavedStudio,"Persistent storage is required for the live exchange")
   self:_sandbox(self.PlaceId==0 and "This place is unpublished." or "Persistence is disabled.") return
  end
  if not self.Store then
   self.Store=game:GetService("DataStoreService"):GetDataStore(self.Settings.StoreName,self.Studio and "Studio" or "Live")
  end
  self.Lease=self.Lease or Lease.new(self.Store,self.Settings,self.Identity,self.Now)
  local owned,record
  if self.CanOwn then owned,record=self.Lease:Claim()
  else owned=false record=self.Store:GetAsync(self.Settings.WorldKey)end
  if not owned then
   self.Owner=record self.Mode="Following" self.Healthy=false
   self.Status=self.Studio and "Shared Studio exchange is active in another test; stop it before restarting here" or "Joining the shared exchange"
   return
  end
  self.Mode="Loading" self.Status="Restoring the saved exchange"
  -- Everything restored from the store is durable; no in-memory receipt or transaction from a previous engine survives.
  if record.Checkpoint then
   self.Engine,self.Population=Checkpoint.Restore(Checkpoint.Decode(record.Checkpoint),self.Config)
   assert(self.Engine.Step==record.SavedStep,"Checkpoint step does not match ownership record")
  else
   assert(record.SavedStep==0,"Saved exchange checkpoint is missing")
   self.Engine,self.Population=self:_fresh()
  end
  -- No client trades until the initial/loaded state has a confirmed durable checkpoint.
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,false)
  self:_committed(projection)
  self.Mode="Shared" self.Status="SHARED · SAVED" self.Healthy=true self.Epoch+=1
  self.NextSave=self.Now()+self.Settings.SaveSeconds
 end)
 self.Busy=false self.NextAttempt=self.Now()+self.Settings.RetrySeconds
 if not ok then
  -- Transient storage failures or corrupt checkpoints must never silently reset an existing market.
  self.Healthy=false self.Mode="Unavailable" self.Status="Saved exchange unavailable · retrying safely"
  self.LastError=tostring(err) warn("[Get Funded!] "..self.LastError)
 end
end
function World:CanRun()
 if self.Closing or self.Transaction or not self.Healthy or not self.Engine then return false end
 return self.Mode=="Local" or (self.Mode=="Shared" and self.Lease:Valid())
end
function World:Label()
 if self.Mode=="Shared" and not self:CanRun()then return "PAUSED · WAITING FOR SAVED EXCHANGE"end
 return self.Status
end
function World:Save(release)
 if self.Busy or not self.Engine or self.Mode~="Shared" then return false end
 self.Busy=true
 local ok,err=pcall(function()
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,release)
  self:_committed(projection)
 end)
 self.Busy=false self.NextSave=self.Now()+(ok and self.Settings.SaveSeconds or self.Settings.RetrySeconds)
 self.Healthy=ok and not release
 if not ok then self.LastError=tostring(err) warn("[Get Funded!] Save failed; exchange paused: "..self.LastError)end
 return ok
end
-- Freeze execution, transform a detached copy, then swap only after the fenced save confirms it.
-- A timed-out write may have committed: reload durable storage instead of overwriting it with old data.
function World:TransformSaved(transform)
 if self.Busy or self.Mode~="Shared" or not self:CanRun()then return false,"Exchange is not ready."end
 self.Busy=true;self.Transaction=true
 local rawBytes,storedBytes=self.LastRawBytes,self.LastStoredBytes
 local attemptedCommit=false local result
 local ok,err=pcall(function()
  local engine,population=Checkpoint.Restore(Checkpoint.Capture(self.Engine,self.Population),self.Config)
  result=transform(engine,population);engine:Audit()
  local encoded,step,projection=self:_encode(engine,population)
  assert(not self.CaptureProjection or projection,"Cannot transform saved data without its leaderboard projection")
  attemptedCommit=true;self.Lease:Commit(encoded,step,false)
  self.Engine=engine;self.Population=population;self.Epoch+=1
  self:_committed(projection)
 end)
 self.Busy=false;self.Transaction=false
 self.NextSave=self.Now()+self.Settings.SaveSeconds
 if not ok then
  self.LastRawBytes=rawBytes;self.LastStoredBytes=storedBytes
  self.LastError=tostring(err)
  if attemptedCommit then
   self.Healthy=false;self.Mode="Unavailable";self.Status="Verifying the saved exchange"
   self.Engine=nil;self.Population=nil;self.Epoch+=1
   self.NextAttempt=self.Now()+self.Settings.RetrySeconds
  end
  warn("[Get Funded!] Saved transformation failed: "..self.LastError)
 end
 return ok,ok and result or tostring(err)
end
-- Called only at the server scheduler boundary. Preview/encode do not yield or write
-- live accounts; the lease commit freezes simulation until its outcome is known.
function World:RefreshBots(sequence,actor)
 if self.Busy or self.Mode~="Shared"or not self:CanRun()then return false,"Exchange is not ready."end
 self.Busy=true;self.Transaction=true;self.BotRefreshSaving=true
 local attempted=false;local result
 local rawBytes,storedBytes=self.LastRawBytes,self.LastStoredBytes
 local ok,err=pcall(function()
  local plan=BotRefresh.Prepare(self.Engine,self.Population,sequence,actor)
  result=plan.Receipt
  if plan.Duplicate then return end
  local engine,population=BotRefresh.Preview(self.Engine,self.Population,plan)
  engine:Audit()
  local encoded,step,projection=self:_encode(engine,population)
  assert(not self.CaptureProjection or projection,"Cannot refresh without leaderboard projection")
  attempted=true;self.Lease:Commit(encoded,step,false)
  -- No epoch swap: preserve live objects, callbacks, pending requests and FIFO identity.
  BotRefresh.Apply(self.Engine,self.Population,plan)
  self:_committed(projection)
 end)
 self.Busy=false;self.Transaction=false;self.BotRefreshSaving=false;self.NextSave=self.Now()+self.Settings.SaveSeconds
 if not ok then
  self.LastRawBytes=rawBytes;self.LastStoredBytes=storedBytes;self.LastError=tostring(err)
  if attempted then
   self.Healthy=false;self.Mode="Unavailable";self.Status="Verifying the saved exchange"
   self.Engine=nil;self.Population=nil;self.Epoch+=1;self.NextAttempt=self.Now()+self.Settings.RetrySeconds
  end
  warn("[Get Funded!] Bot refresh failed: "..tostring(err))
 end
 return ok,ok and result or tostring(err)
end
function World:Maintain()
 if self.Closing or self.Busy or self.Mode=="Local"then return end
 local now=self.Now()
 if self.Mode=="Shared"then
  if not self.Lease.Owned or now>=self.Lease.Record.LeaseUntil then
   -- Discard unsaved state after loss of authority. Reacquire and restore the durable record.
   self.Healthy=false self.Mode="Unavailable" self.Status="Reconnecting to the saved exchange"
   self.Engine=nil self.Population=nil self.Epoch+=1 self.NextAttempt=now
  elseif now>=self.NextSave then self:Save(false) return end
 end
 if self.Mode~="Shared" and now>=self.NextAttempt then self:Open()end
end
function World:Close()
 self.Closing=true
 -- A save already in flight finishes before the final frozen checkpoint and lease release.
 local deadline=os.clock()+24
 while self.Busy and os.clock()<deadline do task.wait(0.05)end
 if not self.Busy and self.Mode=="Shared" and self.Lease.Owned then
  repeat
   if self:Save(true)then return true end
   if not self.Lease.Owned or self.Now()>=self.Lease.Record.LeaseUntil then break end
   task.wait(1)
  until os.clock()>=deadline
 end
 return self.Mode=="Local"
end
return World
]====]):sub(2),Hash=([====[!4d0c09207c2b4884e8a0d997c88a4b0a81a61b9126226d7bd52b4ad6d5c6de0b]====]):sub(2),ExpectedHash=([====[!665bb3ab92a3db33a85176ef0a157f6298d1e893d5c9b318cbe159e2342fc649]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.WorldCheckpoint]====]):sub(2)]={Source=([====[!-- Lossless execution state, including FIFO identity and the participants' next random draw.
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local TradeStats=require(script.Parent.TradeStats)
local Http=game:GetService("HttpService")
local Encoding=game:GetService("EncodingService")
-- Version 3 introduces E-minis, retained close-only micro books and equity-only failure.
-- Version 4 adds armed stop entry orders, which wait off the order book. An older build would
-- rest them as limits, so it must fail closed on V4. V1-V3 are read unchanged.
-- Version 5 executes player orders off the order book against a saved house counterparty account. An older
-- build would rest player limits in the book again and liquidate the house as a bot, so it fails closed on V5.
-- V5 originally moved V1-V4 player limits off-book; V9 now cancels pre-V9 player limits on migration.
-- V6 permanently separates tier access, account instances and Shop receipts. Older writers must
-- refuse it, otherwise they could reset permanent entitlements or spend the wallet twice.
-- V7 renames ES/NQ to BX/BT, keeps RTY/YM only as retired close-only books and adds BG. Older builds
-- cannot map those markets, so they must refuse V7. V1-V6 saves migrate on restore (see plan and rename).
-- V8 adds the single-account profile. Older writers must fail closed.
-- V9 makes player limits executable book liquidity and persists amendment priority.
-- Pre-V9 pending player limits are cancelled during migration rather than retroactively matched.
-- V10 adds permanent reward grants, player resets and disconnect accounting. Older writers
-- must fail closed so they cannot discard an acknowledged summary or reset a granted bonus.
-- V11 adds scalpers with their own entry/exit state. Older writers must not resume them as generic traders.
-- V12 persists queued market/limit execution and aggregate budgets. Older matching engines must fail closed.
-- V13 adds position-linked working targets and keeps stops on partially closed positions.
-- Older engines must not resume these orders with the old OCO and entry-budget rules.
-- V14 persists pending resets that must liquidate before granting a new account.
-- Older builds must not discard this exposure or allow trading during liquidation.
-- V15 records bot capital adjustments, exact populations and retiring obligations. Older writers fail closed.
-- V16 applies one execution collar to all participants and persists request deduplication.
-- Older writers must not restore a market and resume asymmetric executions.
-- V17 persists bot P&L baselines and refresh receipts. Older engines must not settle
-- refreshed positions against their strategy entries or discard the frozen P&L ledger.
local Checkpoint={Version=17,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true,[17]=true}}
local function digest(raw)
 local bytes=Encoding:ComputeStringHash(raw,Enum.HashAlgorithm.Sha256)
 return (bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))
end
local function clone(value)
 if type(value)~="table"then return value end
 local result={} for key,v in pairs(value)do result[key]=clone(v)end return result
end
-- Maps each saved market to its current symbol (config.Renamed) and checks its economics: every saved market
-- must still exist as a current or retired (close-only) contract with the same tick and multiplier. The
-- restored order is every current market, then the retired markets the save held. A current market the
-- save lacks opens as a new book after restore (`added`).
local function plan(saved,current)
 assert(saved.StepSeconds==current.StepSeconds,"Saved market step size differs from configuration")
 local renamed,held,map=current.Renamed or {},{},{}
 for _,key in ipairs(saved.ContractOrder)do
  local name=renamed[key] or key
  local a,b=saved.Contracts[key],current.Contracts[name] or current.LegacyContracts[name]
  assert(a and b and not held[name] and a.Tick==b.Tick and a.Multiplier==b.Multiplier,"Saved contract specification changed: "..key)
  held[name]=true map[key]=name
 end
 local order,added={},{}
 for _,key in ipairs(current.ContractOrder)do table.insert(order,key) if not held[key] then added[key]=true end end
 for _,key in ipairs(current.LegacyOrder)do if held[key] and not current.Contracts[key] then table.insert(order,key) end end
 assert(#saved.Timeframes==#current.Timeframes,"Saved timeframes differ")
 for i,tf in ipairs(current.Timeframes)do assert(saved.Timeframes[i][1]==tf[1]and saved.Timeframes[i][2]==tf[2],"Saved timeframe changed")end
 return map,order,added
end
-- Moves renamed markets in saved state: table keys and the fields that name a market (Contract, Key) take the
-- current symbol. Saved ids stay opaque and unchanged (for example participant accounts "bot:ES:Maker:1").
local function rename(value,map,field)
 if type(value)=="string"then return (field=="Contract"or field=="Key")and map[value]or value end
 if type(value)~="table"then return value end
 local result={}
 for key,v in pairs(value)do result[type(key)=="string"and map[key]or key]=rename(v,map,key)end
 return result
end
local function capture(engine,population,borrow)
 local function take(value)return borrow and value or clone(value)end
 local e={Accounts={},Books={},Orders={},Profiles=take(engine.Profiles or {})}
 for _,key in ipairs({"Seed","Time","Step","NextOrder","NextPriority","NextTrade","TotalVolume","TradeHash","PendingStops","Execution","EligibilityRevision","RequestJournal","ExecutionDiagnostics","CloseNotificationErrors","LastCloseNotificationError"})do e[key]=take(engine[key])end
 for _,id in ipairs(engine.AccountOrder)do
  local a=borrow and table.clone(engine.Accounts[id])or clone(engine.Accounts[id]);a.OpenOrders=nil
  -- Bot histories are display-only; balances, cash ledger and inventory are retained exactly.
  if not a.Player then a.History={} a.Fills={}end
  table.insert(e.Accounts,a)
 end
 for _,key in ipairs(engine.Config.ContractOrder)do
  local book={}
  for field,value in pairs(engine.Books[key])do if field~="Bids"and field~="Asks"and field~="Spec"then book[field]=take(value)end end
  e.Books[key]=book
 end
 local ids={}for id in pairs(engine.Orders)do table.insert(ids,id)end table.sort(ids)
 for _,id in ipairs(ids)do table.insert(e.Orders,take(engine.Orders[id]))end
 local p={RandomState=population.Random.State}
 for key,value in pairs(population)do if key~="Engine"and key~="Config"and key~="Random"then p[key]=take(value)end end
 return {Version=Checkpoint.Version,Config=take(engine.Config),Engine=e,Population=p}
end
function Checkpoint.Capture(engine,population)
 return capture(engine,population,false) -- Independently mutable fixture/checkpoint copy.
end
function Checkpoint.Restore(snapshot,currentConfig)
 assert(type(snapshot)=="table"and Checkpoint.Readable[snapshot.Version],"Unsupported saved market format")
 local map,order,added=plan(snapshot.Config,currentConfig)
 for old,name in pairs(map)do if old~=name then snapshot=rename(snapshot,map) break end end
 -- Preserve saved behavior except explicit, versioned migrations; presentation cadence may change.
 local config=clone(snapshot.Config)
 local savedPolicy=snapshot.Population.PolicyVersion or 0
 if savedPolicy>0 then
  assert(config.BotPopulation and config.BotPopulation.Version==savedPolicy,"Inconsistent saved bot policy")
  if currentConfig.BotPopulation and savedPolicy==currentConfig.BotPopulation.Version then
   for _,kind in ipairs(currentConfig.BotPopulation.Order)do
    assert(config.BotPopulation.Counts[kind]==currentConfig.BotPopulation.Counts[kind]
     and config.BotPopulation.Capital[kind]==currentConfig.BotPopulation.Capital[kind],"Bot allocation changes require a policy version bump")
   end
  end
 end
 local upgradeBots=(snapshot.Population.PolicyVersion or 0)<(currentConfig.BotPopulation and currentConfig.BotPopulation.Version or 0)
 assert((snapshot.Population.PolicyVersion or 0)<=(currentConfig.BotPopulation and currentConfig.BotPopulation.Version or 0),"Cannot downgrade bot population policy")
 if upgradeBots then
  for _,key in ipairs({"BotPopulation","MakersPerInstrument","ParticipantsPerInstrument","WhalesPerInstrument","ScalpersPerInstrument","Scalper","Reserve"})do config[key]=clone(currentConfig[key])end
 end
 local upgradeReserves=(config.ReservePopulationVersion or 0)<(currentConfig.ReservePopulationVersion or 0)
 if upgradeReserves then config.Reserve=clone(currentConfig.Reserve);config.ReservePopulationVersion=currentConfig.ReservePopulationVersion end
 config.PlayerExecution=clone(currentConfig.PlayerExecution)
 config.BotExitRetrySeconds=currentConfig.BotExitRetrySeconds
 config.SimulationFrameBudgetMs=currentConfig.SimulationFrameBudgetMs
 local upgradeScalpers=(config.ScalperPopulationVersion or 0)<(currentConfig.ScalperPopulationVersion or 0)
 if upgradeScalpers then
  config.ScalpersPerInstrument=currentConfig.ScalpersPerInstrument
  config.ScalperPopulationVersion=currentConfig.ScalperPopulationVersion
  config.Scalper=clone(currentConfig.Scalper)
 end
 local upgradeMakers=(config.MakerPopulationVersion or 0)<(currentConfig.MakerPopulationVersion or 0)
 if upgradeMakers then
  config.MakersPerInstrument=currentConfig.MakersPerInstrument
  config.MakerPopulationVersion=currentConfig.MakerPopulationVersion
 end
 config.DailyLossLimit=nil
 for _,key in ipairs({"LegacyOrder","LegacyContracts","LegacyToCurrent","Renamed"})do config[key]=clone(currentConfig[key])end
 config.ContractOrder=order
 local retiring={}
 for _,key in ipairs(order)do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  local spec=config.Contracts[key]
  if added[key] then
   spec=clone(current) config.Contracts[key]=spec
   -- A new book starts near the saved market it succeeds, without relabelling historical executions or volume.
   for old,successor in pairs(currentConfig.LegacyToCurrent)do
    local b=successor==key and snapshot.Engine.Books[old]
    if b then spec.Last=(b.Last or b.Reference)*config.Contracts[old].Tick end
   end
  else
   -- Saved economics stay exact (checked in plan); names and the close-only rule follow this build.
   if current.CloseOnly and not spec.CloseOnly then retiring[key]=true end
   spec.Name=current.Name spec.Short=current.Short spec.CloseOnly=current.CloseOnly
  end
 end
 -- MaxCandles only bounds chart history (matching never reads candles), so a restored world adopts the current limit.
 for _,key in ipairs({"BroadcastSeconds","SimulationSpeed","MaxCatchupSteps","MaxCandles","MaxPlayerQuantity","MaxPlayerInventory","MaxPlayerOrders","DepthLevels","MakerQuotePolicyVersion","MakerMinRestSeconds","MakerRepriceTicks","MakerQuoteSizeMultiplier","MakerReplenishSeconds","MakerDecisionMultiplier"})do config[key]=currentConfig[key]end
 -- Simulated margin is buying-power policy; contract economics and all saved ledgers stay intact.
 for key,spec in pairs(config.Contracts) do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  if current then spec.Margin=current.Margin end
 end
 local data=snapshot.Engine local engine=Engine.new(config,data.Seed)
 for _,key in ipairs({"Time","Step","NextOrder","NextTrade","TotalVolume","TradeHash","PendingStops","Execution","EligibilityRevision","RequestJournal","ExecutionDiagnostics","CloseNotificationErrors","LastCloseNotificationError"})do engine[key]=clone(data[key])end
 engine.NextPriority=data.NextPriority or data.NextOrder
 for _,a in ipairs(data.Accounts)do
  local account=clone(a);account.OpenOrders={}
  account.LossLimit=account.Base
  assert(not engine.Accounts[a.Id],"Duplicate saved account")
  engine.Accounts[a.Id]=account table.insert(engine.AccountOrder,a.Id)
 end
 for key,fields in pairs(data.Books)do for name,value in pairs(fields)do engine.Books[key][name]=clone(value)end end
 engine.Profiles=clone(data.Profiles or {})
 for uid,profile in pairs(engine.Profiles)do
  assert(type(uid)=="string"and type(profile)=="table"and type(profile.Tiers)=="table"and type(profile.Ledger)=="table","Invalid saved funded profile")
  for _,id in ipairs(profile.Ledger)do assert(engine.Accounts[id],"Saved funded account missing")end
 end
 local prior=0
 for _,order in ipairs(data.Orders)do
  local o=clone(order)
  -- Preserve execution behavior for orders placed before the explicit choice existed.
  o.Execution=o.Execution or "Sliced"
  assert(o.Id>prior and o.Remaining>0 and engine.Accounts[o.Owner]and engine.Books[o.Contract],"Invalid saved resting order")
  prior=o.Id engine.Orders[o.Id]=o engine.Accounts[o.Owner].OpenOrders[o.Id]=true
  o.Priority=o.Priority or o.Id
  engine.NextPriority=math.max(engine.NextPriority,o.Priority)
  if o.Type=="Limit"and not o.Queued and not(engine.Accounts[o.Owner].Player and snapshot.Version<9)then engine:_rest(engine.Books[o.Contract],o)end
 end
 local population=setmetatable({Engine=engine,Config=config},Participants)
 -- Rebuilding FIFO is not a liquidity change. Keep saved retry deadlines valid;
 -- subsequent migrations/protection repairs still invalidate affected books.
 for key,fields in pairs(data.Books)do engine.Books[key].ExitLiquidityRevision=fields.ExitLiquidityRevision end
 for key,value in pairs(snapshot.Population)do if key~="RandomState"then population[key]=clone(value)end end
 population.Random=Participants.RNG.new(1);population.Random.State=snapshot.Population.RandomState
 assert(type(population.Random.State)=="number"and population.Random.State>0 and population.Random.State<2147483647,"Invalid saved random state")
 for _,agent in ipairs(population.Agents)do assert(engine.Accounts[agent.Id],"Saved participant account missing")end
 if snapshot.Version<3 then
  local currentAccounts={}
  for _,profile in pairs(engine.Profiles) do for _,entry in pairs(profile.Tiers) do if entry.Account then currentAccounts[entry.Account]=true end end end
  for _,profile in pairs(engine.Profiles) do for _,id in ipairs(profile.Ledger) do if not currentAccounts[id] then engine.Accounts[id].Retired=true end end end
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player and not a.Retired and engine:Summary(a).Equity>0 then
    a.Locked=false a.Liquidating=nil
    for _,p in pairs(a.Positions) do if p.Triggered=="Risk liquidation" then p.Triggered=nil end end
   end
   if a.Player then
    for orderId in pairs(clone(a.OpenOrders)) do
     local o=engine.Orders[orderId]
     if config.Contracts[o.Contract].CloseOnly and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 -- A market that became close-only keeps its positions, SL/TP and closing orders. Its entry orders could only
 -- open new exposure there, so they are cancelled (the order history records it).
 if next(retiring) then
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player then
    local ids={} for orderId in pairs(a.OpenOrders) do table.insert(ids,orderId) end table.sort(ids)
    for _,orderId in ipairs(ids) do
     local o=engine.Orders[orderId]
     if o and retiring[o.Contract] and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 for _,key in ipairs(order) do if added[key] then population:AddMarket(key) end end
 if not upgradeBots then
  if upgradeMakers then population:EnsureMakers(currentConfig.ContractOrder,config.MakersPerInstrument) end
  if upgradeScalpers then population:EnsureScalpers(currentConfig.ContractOrder,config.ScalpersPerInstrument) end
  if upgradeReserves then population:EnsureReserves(currentConfig.ContractOrder);population:RefreshReservePolicy()end
 end
 -- Lifetime trading stats (no format change): rebuilt once from saved history for older accounts,
 -- reconciled against the ledger for all others. Idempotent across repeated restores.
 local now=os.time()
 -- Older settlement added every fill separately to large balances, accumulating sub-cent
 -- floating-point drift. Rebuild only tiny discrepancies from the existing capital/P&L ledger;
 -- larger differences still fail Audit. New settlement derives Balance from that ledger.
 for _,id in ipairs(engine.AccountOrder)do local a=engine.Accounts[id]
  local gap=a.Balance-a.Base-(a.PnlBaseline or 0)-a.Realized
  if a.Base>=1e9 and math.abs(gap)<.005 then a.Balance=a.Base+(a.PnlBaseline or 0)+a.Realized end
 end
 require(script.Parent.BotPopulation).Apply(population)
 for _,id in ipairs(engine.AccountOrder) do local a=engine.Accounts[id] if a.Player then TradeStats.Reconcile(engine,a,now) end end
 -- Required migration, not optional leaderboard work: any failure aborts restore before saving.
 require(script.Parent.FundedAccounts).new(engine,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),currentConfig)
 -- Archive legacy profile evidence first; then cancel remaining off-book limits without a trade.
 if snapshot.Version<9 then
  local pending={};for id,o in pairs(engine.Orders)do if o.Type=="Limit"and engine.Accounts[o.Owner].Player then table.insert(pending,id)end end
  table.sort(pending);for _,id in ipairs(pending)do local o=engine.Orders[id];engine:Cancel(o.Owner,id)end
 end
 -- Rebuild missing targets/adopt legacy closing limits without executing trades during restore.
 local Protective=require(script.Parent.ProtectiveOrders)
 for _,id in ipairs(engine.AccountOrder)do local a=engine.Accounts[id]
  if a.Player then for key in pairs(a.Positions)do Protective.Mark(engine,a,key)end end
 end
 Protective.Sync(engine,true)
 engine:Audit()
 return engine,population
end
-- The reader's decompressed-size bound. It is unchanged, so every checkpoint that opened before still opens.
-- Encode refuses anything larger before compressing, so the writer and the reader enforce one bound: every
-- checkpoint the writer accepts decodes, and every save that decodes today can be written again.
Checkpoint.MaxDecodedBytes=32000000
-- The reader's header rules, shared by Encode (before a commit) and Decode (on restore).
function Checkpoint.Check(record,maxDecodedBytes)
 assert(type(record)=="table" and Checkpoint.Readable[record.Version] and record.Codec=="zstd-base64" and type(record.Payload)=="string","Invalid checkpoint encoding")
 local compressed=Encoding:Base64Decode(buffer.fromstring(record.Payload))
 local bytes=Encoding:GetDecompressedBufferSize(compressed,Enum.CompressionAlgorithm.Zstd)
 assert(bytes and bytes==record.RawBytes and bytes<=math.min(maxDecodedBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes),"Invalid checkpoint length")
 return compressed,bytes
end
function Checkpoint.Encode(snapshot,maxRawBytes)
 local raw=Http:JSONEncode(snapshot)
 local limit=math.min(maxRawBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes)
 if #raw>limit then error(string.format("Exchange checkpoint is too large (%d raw bytes, limit %d); trading paused to protect saved state",#raw,limit),2) end
 local compressed=Encoding:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd,3)
 local record={Version=Checkpoint.Version,Codec="zstd-base64",RawBytes=#raw,
  Digest=digest(raw),
  Payload=buffer.tostring(Encoding:Base64Encode(compressed))}
 Checkpoint.Check(record,limit)
 return record
end
function Checkpoint.Decode(record,maxDecodedBytes)
 local compressed=Checkpoint.Check(record,maxDecodedBytes)
 local raw=buffer.tostring(Encoding:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))
 assert(digest(raw)==record.Digest,"Checkpoint checksum failed")
 return Http:JSONDecode(raw)
end
function Checkpoint.EncodeWorld(engine,population,maxRawBytes)
 -- No borrowed table escapes this non-yielding call. EncodingService and JSON
 -- encoding are synchronous; the engine cannot advance between capture and
 -- serialization. Public Capture remains a deep copy for asynchronous consumers.
 return Checkpoint.Encode(capture(engine,population,true),maxRawBytes)
end
return Checkpoint
]====]):sub(2),Hash=([====[!1500dbb050c321c4f17d4bb9649dbee902f9ea79e6439058aa5ea072aa55bd82]====]):sub(2),ExpectedHash=([====[!3b8e1ab2c532853a8ed6606ff58280bf0da5d2d6993ffa116c62d02c569028db]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.MarketServer]====]):sub(2)]={Source=([====[!local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local root=ReplicatedStorage:WaitForChild("MarketReign")
local Config=require(root.MarketConfig)
local Progression=require(root.ProgressionConfig)
local World=require(script.Parent.WorldService)
local Funded=require(script.Parent.FundedAccounts)
local Leaderboards=require(script.Parent.LeaderboardService)
local Ranking=require(script.Parent.LeaderboardRanking)
local ReplyBuffer=require(script.Parent.ReplyBuffer)
local WorldSettings=require(script.Parent.WorldConfig)
local SimulationScheduler=require(script.Parent.SimulationScheduler)
local RequestJournal=require(script.Parent.RequestJournal)
local RequestQueue=require(script.Parent.RequestQueue)
local OwnerResetCommand=require(script.Parent.OwnerResetCommand)
local OwnerGiveCommand=require(script.Parent.OwnerGiveCommand)
local OwnerBotsCommand=require(script.Parent.OwnerBotsCommand)
local DepthAccess=require(script.Parent.MarketDepthAccess)
local depthAccess=DepthAccess.new()
Funded.Validate(Progression) -- Fail closed on invalid progression configuration.
local function remote(name)
 local old=root:FindFirstChild(name) if old then old:Destroy() end
 local r=Instance.new("RemoteEvent") r.Name=name r.Parent=root return r
end
local requestRemote=remote("OrderRequest") local updateRemote=remote("MarketUpdate")
local ownerNotice=remote("OwnerNotice")
local world=World.new(Config)
local leaderboard=Leaderboards.new({Studio=world.Studio})
world.CaptureProjection=function(engine)return Ranking.Capture(Funded.new(engine,Progression,Config))end
local oldLeaderboard=root:FindFirstChild("LeaderboardRequest") if oldLeaderboard then oldLeaderboard:Destroy() end
local leaderboardRemote=Instance.new("RemoteFunction") leaderboardRemote.Name="LeaderboardRequest" leaderboardRemote.Parent=root
local market,population,funded local epoch=-1
root:SetAttribute("SessionSeed",nil) root:SetAttribute("Ready",false)
local clients={} local queue={} local sequence=0 local actionLog={}
local resettingUid
-- Acknowledgements are bounded per connection by count and age (see ReplyBuffer).
local replies=ReplyBuffer.new(WorldSettings.MaxQueuedReplies,WorldSettings.ReplyMaxAgeSeconds)
-- Joining idempotently creates one $10,000 account for a new player.
local function resolve(player,state)
 if not funded or not world:CanRun() or state.ResetPending then return end
 funded:Join(state.Uid) funded:Return(state.Uid) funded:Evaluate(state.Uid)
 local p=funded:Profile(state.Uid)
 if p then
  p.PlayerName=player.Name;p.DisplayName=player.DisplayName
  -- A join restores history without replaying sounds for old/offline executions.
  local events={};for _,event in ipairs(p.Events or {})do if event.Kind~="TradeClosed"then table.insert(events,event)end end;p.Events=events
 end
 state.Owner=funded:Owner(state.Uid) state.Full=true state.PortfolioRevision=nil
 if state.RequestEngine~=market then
  state.RequestEngine=market;state.RequestSession=RequestJournal.Open(market,state.Uid)
 end
 if state.Owner then market:SetConnected(state.Owner,true)end
end
local function add(player)
 if clients[player] then return end
 clients[player]={Uid=Funded.Key(player.UserId),Contract=Config.ContractOrder[1],Timeframe="1m",Full=true,Tokens=20,TokenTime=os.clock(),
  Seen={},SeenOrder={},Replies={},ReplyTimes={},Subscribed=false,PortfolioAt=0,ResetPending=tostring(player.UserId)==resettingUid}
 depthAccess:Refresh(player)
 resolve(player,clients[player])
end
Players.PlayerAdded:Connect(add) for _,p in ipairs(Players:GetPlayers()) do add(p) end
-- The purchase event only triggers a fresh ownership query. Its boolean never grants access.
game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player,passId)
 if clients[player]and passId==depthAccess.PassId then depthAccess:Refresh(player,true)end
end)
leaderboardRemote.OnServerInvoke=function(player,tab)
 local state=clients[player]
 if not state or (tab~="Global" and tab~="Server") then return nil end
 -- Read-only endpoint; rate limits are independent of order traffic. No scores/ids accepted.
 local now=os.clock()
 if now<(state.LeaderboardAt or 0) then return {Tab=tab,State="Throttled"} end
 state.LeaderboardAt=now+2
 if not funded or not world:CanRun() then return {Tab=tab,State="Loading",Rows={},Studio=world.Studio} end
 if tab=="Server" then return leaderboard:Server(funded,Players:GetPlayers(),player) end
 local own=Ranking.Row(funded,state.Uid,player)
 return leaderboard:Global(own)
end
-- Portfolio + projection accompany each price batch. Closed and open amounts are one snapshot.
local function attachPortfolio(state,packet)
 if not funded then return end
 packet.Events=funded:TakeEvents(state.Uid)
 local profile=funded:Profile(state.Uid)
 local revision=profile and profile.Revision or 0 local now=os.clock()
 packet.Portfolio=funded:View(state.Uid) state.PortfolioRevision=revision state.PortfolioAt=now
 -- Lifetime stats: sent on join/refresh and whenever a counted value changes (a close, a depletion,
 -- a restart). A failure here is isolated from trading and reported to the Stats page.
 local key=funded:StatsKey(state.Uid)
 if state.Full or key~=state.StatsKey then
  local ok,stats=pcall(funded.Stats,funded,state.Uid)
  if not ok then warn("[Get Funded!] Stats unavailable: "..tostring(stats)) end
  packet.Stats=ok and stats or {Error="Stats are temporarily unavailable. Your trades and saved results are not affected."}
  state.StatsKey=key
 end
end
local function emit(player,state)
 depthAccess:Refresh(player)
 if funded and world:CanRun() and not funded:Owner(state.Uid) and os.clock()>=(state.JoinRetryAt or 0) then
  state.JoinRetryAt=os.clock()+5;resolve(player,state)
 end
 if funded then
  local owner=funded:Owner(state.Uid)
  if state.Owner~=owner then state.Owner=owner;state.Full=true;if owner then market:SetConnected(owner,true)end end
 end
 local unavailable=not market or world.Transaction or state.ResetPending or world.Mode=="Unavailable" or world.Mode=="Following" or world.Mode=="Loading"
 if unavailable or not state.Owner or not market.Accounts[state.Owner] then
  -- No trading account yet (first join) or the exchange is not ready: send status and portfolio only.
  local queued,dropped=replies:Take(state)
  local packet={StatusOnly=true,CanTrade=not unavailable and world:CanRun(),ConnectionStatus=world:Label(),Replies=queued,RepliesDropped=dropped,NoAccount=not unavailable or nil,RequestSession=state.RequestSession,RequestHigh=state.LastRequestId}
  if not unavailable then attachPortfolio(state,packet) state.Full=false end
  depthAccess:Apply(packet,player,state.Contract)
  updateRemote:FireClient(player,packet)
  return
 end
 local packet=market:Snapshot(state.Owner,state.Contract,state.Timeframe,state.Full)
 packet.Seed=nil -- The server's future random stream is private.
 packet.CanTrade=world:CanRun() packet.ConnectionStatus=world:Label() packet.PersistenceMode=world.Mode
 if market.Accounts[state.Owner].Resetting then
  packet.CanTrade=false;packet.ConnectionStatus="Resetting account · liquidating positions…"
 end
 -- Quotes/candles/P&L are frequent; unchanged order and trade histories are not resent.
 local orderParts={}
 for _,order in ipairs(packet.Orders)do
  table.insert(orderParts,table.concat({order.Id,order.Contract,order.Protection or "",order.Quantity,order.Price or "Market",order.Status},":"))
 end
 local orderSignature=table.concat(orderParts,"|")
 if not state.Full and state.SentRevision==packet.Revision and state.SentOwner==state.Owner then
  packet.History=nil packet.Fills=nil
 end
 -- OCO/trigger status can change before a closing execution changes the account revision.
 if not state.Full and state.SentOwner==state.Owner and state.SentOrders==orderSignature then
  packet.Orders=nil
 end
 depthAccess:Apply(packet,player,state.Contract)
 state.SentRevision=packet.Revision state.SentOwner=state.Owner state.SentOrders=orderSignature
 packet.Regime=population.Regime.Name packet.News=market.Time<population.NewsUntil and population.News or nil
 packet.Speed=Config.SimulationSpeed packet.Replies,packet.RepliesDropped=replies:Take(state)
 packet.AccountKey=(funded:Profile(state.Uid) or {}).Active
 packet.AccountToken=state.Owner -- identifies the exact attempt; checked, never used to choose an owner
 packet.RequestSession=state.RequestSession
 packet.RequestHigh=state.LastRequestId
 attachPortfolio(state,packet)
 updateRemote:FireClient(player,packet) state.Full=false
end
-- A packet failure for one connection must not stop every other player's feed.
local function safeEmit(player,state)
 local ok,err=pcall(emit,player,state)
 if not ok then
  state.Full=true
  local now=os.clock()
  if now>=(state.EmitWarningAt or 0)then
   state.EmitWarningAt=now+5;warn("[Get Funded!] Market update failed; retrying: "..tostring(err))
  end
 end
end
local function reply(state,id,ok,message,result,extra)
 local r={RequestId=id,Ok=ok,Message=message,Result=result}
 for k,v in pairs(extra or {})do r[k]=v end
 local active=state.ActiveJournal
 if active and active.Id==id then RequestJournal.Finish(market,state.Uid,active.Session,id,r)end
 replies:Push(state,r,os.clock())
end
local allowed={Place=true,Cancel=true,Close=true,Subscribe=true,AmendProtection=true,AmendOrder=true,
 Start=true,Restart=true,ResetAccount=true,AcknowledgeAway=true,Flag=true,Stats=true,ProtectionPreferences=true}
local fields={"RequestSession","ExpectedAccount","Contract","Timeframe","Direction","Quantity","Type","Price","StopTicks","TargetTicks","StopDollars","TargetDollars","ExpectedQuantity","OrderId","Protection","ExpectedPrice",
 "Stage","StopOn","TargetOn","Create","SummaryId","Execution"}
requestRemote.OnServerEvent:Connect(function(player,request)
 local state=clients[player]
 if not state or state.ResetPending or type(request)~="table" then return end
 local now=os.clock()
 -- Subscription recovery has its own allowance, so order spam cannot starve the feed.
 if request.Action=="Subscribe"or request.Action=="Stats"then
  state.ReadTokens=math.min(4,(state.ReadTokens or 4)+(now-(state.ReadTokenTime or now))*2);state.ReadTokenTime=now
  if state.ReadTokens<1 then return end;state.ReadTokens-=1
 else
  state.Tokens=math.min(20,state.Tokens+(now-state.TokenTime)*6);state.TokenTime=now
  if state.Tokens<1 then return end;state.Tokens-=1
 end
 if type(request.Id)~="number" or request.Id%1~=0 or request.Id<1 or request.Id>1e9 then return end
 if state.Seen[request.Id]then
  local cached=RequestJournal.Cached(market,state.Uid,request.RequestSession,request.Id)
  if cached then replies:Push(state,cached,now)else state.Full=true end
  return
 end
 if not allowed[request.Action] then return end
 -- Whitelist scalar inputs. ExpectedAccount detects a stale view; it never selects an owner.
 -- Execution prices, timestamps and account ownership remain server-owned.
 local clean={Id=request.Id,Action=request.Action}
 for _,field in ipairs(fields) do
  local value=request[field]
  if value~=nil then
   if field=="StopOn"or field=="TargetOn"or field=="Create"then
    if type(value)~="boolean"then return end
   elseif type(value)~="number" and type(value)~="string" then return end
   if type(value)=="number" and (value~=value or math.abs(value)>1e9) then return end
   if type(value)=="string" and #value>(field=="Followers" and 512 or field=="ExpectedAccount" and 64 or 32) then return end
   clean[field]=value
  end
 end
 if #queue>=RequestQueue.Capacity then reply(state,clean.Id,false,"Exchange busy. Please retry.") return end
 state.Seen[clean.Id]=true table.insert(state.SeenOrder,clean.Id)
 state.LastRequestId=math.max(state.LastRequestId or 0,clean.Id)
 if #state.SeenOrder>256 then state.Seen[table.remove(state.SeenOrder,1)]=nil end
 -- Read-only: resend the authoritative Stats packet with the next update (Stats page Retry).
 if clean.Action=="Stats"then state.StatsKey=nil return end
 if clean.Action=="Subscribe"then
  local valid=false for _,tf in ipairs(Config.Timeframes)do if tf[1]==clean.Timeframe then valid=true break end end
  if Config.Contracts[clean.Contract]and valid then
   state.Contract=clean.Contract state.Timeframe=clean.Timeframe state.Full=true state.Subscribed=true
   -- Coalesce rapid subscription changes into the next scheduled market packet.
  end
  return
 end
 if not world:CanRun()then reply(state,clean.Id,false,world:Label())return end
 sequence+=1 table.insert(queue,{Player=player,Request=clean,Sequence=sequence,Epoch=epoch,Owner=state.Owner})
end)
local function processCore(item)
 local state=clients[item.Player] if not state or state.ResetPending then return end
 if not world:CanRun() then reply(state,item.Request.Id,false,world:Label(),nil,{Kind=item.Request.Action}) return end
 if item.Epoch~=epoch then reply(state,item.Request.Id,false,"Exchange reconnected. Please submit your order again.")return end
 local req=item.Request local uid=state.Uid
 funded:Evaluate(uid)
 local owner=funded:Owner(uid)
 if state.Owner~=owner then
  state.Owner=owner;state.Full=true
  if owner then market:SetConnected(owner,true)end
  if req.Action=="Place" or req.Action=="Close" or req.Action=="Cancel" or req.Action=="AmendOrder" or req.Action=="AmendProtection" then
   reply(state,req.Id,false,"Your account has restarted. Check the current account and try again.") return
  end
 end
 -- Account lifecycle. Each is idempotent and validated against the saved profile.
 if req.Action=="Start" then
  local ok,message,created=funded:Start(uid)
  local profile=funded:Profile(uid);if profile then profile.PlayerName=item.Player.Name;profile.DisplayName=item.Player.DisplayName end
  state.Owner=funded:Owner(uid) state.Full=true;if state.Owner then market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Start",Created=created}) return
 elseif req.Action=="Restart" then
  local ok,message=funded:Restart(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid) state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Restart",Tier=req.Tier}) return
 elseif req.Action=="ResetAccount"then
  local ok,message=funded:ResetAccount(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid);state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="ResetAccount"});return
 elseif req.Action=="AcknowledgeAway"then
  local ok,message=funded:AcknowledgeAway(uid,req.SummaryId)
  reply(state,req.Id,ok,message,nil,{Kind="AcknowledgeAway"});return
 elseif req.Action=="Flag" then
  local ok,message=funded:Flag(uid,req.Stage)
  reply(state,req.Id,ok,message,nil,{Kind="Flag",Stage=req.Stage}) return
 elseif req.Action=="ProtectionPreferences"then
  local ok,message=funded:SetProtectionPreferences(uid,req)
  reply(state,req.Id,ok,message,nil,{Kind="ProtectionPreferences"}) return
 end
 -- Trading owner and current run token are resolved only on the server.
 local owner=state.Owner
 if item.Owner~=owner or req.ExpectedAccount~=owner then reply(state,req.Id,false,"Your account has changed. Check it and try again.") return end
 if not owner or not market.Accounts[owner] then reply(state,req.Id,false,"Your trading account is loading.") return end
 local ok,result=Funded.Perform(market,owner,req)
 market:ProcessStops()
 funded:Evaluate(uid)
 local message=type(result)=="table" and Funded.Describe(result) or result or "Request rejected."
 reply(state,req.Id,ok,message,type(result)=="table" and result or nil,{Kind=req.Action})
end
local function process(item)
 local state=clients[item.Player];if not state or state.ResetPending then return end
 local req=item.Request
 if not market then reply(state,req.Id,false,"Exchange is not ready.");return end
 local accepted,cached,message=RequestJournal.Begin(market,state.Uid,req.RequestSession,req.Id)
 if not accepted then
  if cached then replies:Push(state,cached,os.clock())else reply(state,req.Id,false,message)end
  state.Full=true;return
 end
 state.ActiveJournal={Id=req.Id,Session=req.RequestSession}
 market.RequestContext={Sequence=item.Sequence,Id=req.Id,Step=market.Step}
 local ok,err=pcall(processCore,item)
 market.RequestContext=nil
 if not ok then
  reply(state,req.Id,false,"Request interrupted. Check the account snapshot before placing another order.")
  state.Full=true;warn("[Get Funded!] Request processing failed: "..tostring(err))
 end
 state.ActiveJournal=nil
end
Players.PlayerRemoving:Connect(function(player)
 depthAccess:Forget(player)
 -- Leaving cancels working orders. Positions and their protective triggers remain on the exchange.
 local departing=clients[player]
 if market and departing and departing.Owner then funded:Depart(departing.Uid);market:SetConnected(departing.Owner,false)end
 -- Accept already-received preference edits even if the player leaves before the next market step.
 local remaining={}
 for _,item in ipairs(queue)do
  if item.Player==player and item.Request.Action=="ProtectionPreferences"then process(item)
  elseif item.Player==player and market and departing then
   local req=item.Request
   if RequestJournal.Begin(market,departing.Uid,req.RequestSession,req.Id)then
    RequestJournal.Finish(market,departing.Uid,req.RequestSession,req.Id,{RequestId=req.Id,Ok=false,Message="Disconnected before execution; request cancelled."})
   end
  elseif item.Player~=player then table.insert(remaining,item)end
 end
 queue=remaining;clients[player]=nil
end)
local routing={}
TeleportService.TeleportInitFailed:Connect(function(player)
 routing[player]=nil
 local state=clients[player]if state then state.NextRoute=os.clock()+10 end
end)
local function route(player,state)
 local owner=world.Owner
 if world.Studio or routing[player]or os.clock()<(state.NextRoute or 0)or not owner or
  owner.LeaseUntil<=os.time()or owner.JobId==""or owner.JobId==game.JobId then return end
 routing[player]=true state.NextRoute=os.clock()+15
 task.spawn(function()
  local ok,err=pcall(function()
   local options=Instance.new("TeleportOptions")options.ServerInstanceId=owner.JobId
   TeleportService:TeleportAsync(owner.PlaceId,{player},options)
  end)
  if not ok then routing[player]=nil warn("[Get Funded!] Exchange transfer will retry: "..tostring(err))end
 end)
end
Players.PlayerRemoving:Connect(function(player)routing[player]=nil end)
-- TextChatCommand intercepts the command; authorization and username resolution stay on the server.
-- The owner wipe remains separate from the player reset, which preserves lifetime progress.
local ownerCommand=OwnerResetCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared" and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=function(name)
  for _,player in ipairs(Players:GetPlayers())do
   if player.Name:lower()==name:lower()then return player.UserId,player.Name end
  end
  local uid=Players:GetUserIdFromNameAsync(name)
  return uid,Players:GetNameFromUserIdAsync(uid)
 end,
 Reset=function(userId,name)
  local uid=Funded.Key(userId)
  if not world.Engine or not world.Engine.Profiles[uid]then return false,"@"..name.." has no saved data to reset."end
  resettingUid=uid
  for _,state in pairs(clients)do if state.Uid==uid then state.ResetPending=true end end
  local ok=world:TransformSaved(function(engine)
   return Funded.new(engine,Progression,Config):ResetPlayer(uid)
  end)
  if not ok then
   resettingUid=nil
   for player,state in pairs(clients)do if state.Uid==uid then
    if not world.Engine then
     player:Kick("The exchange is checking saved data after an owner reset. Please rejoin shortly.")
    else state.ResetPending=nil;state.Full=true end
   end end
   return false,"Reset was not confirmed. Wait for the saved exchange to recover, then check @"..name.." before retrying."
  end
  -- Clear delayed actions and diagnostic copies belonging to the wiped profile.
  for i=#queue,1,-1 do if queue[i].Player.UserId==userId then table.remove(queue,i)end end
  for i=#actionLog,1,-1 do if actionLog[i].Player==userId then table.remove(actionLog,i)end end
  leaderboard:UseDurableProjection(world.DurableProjection)
  root:SetAttribute("LeaderboardRevision",(root:GetAttribute("LeaderboardRevision")or 0)+1)
  task.spawn(function()leaderboard.NextWrite=0;leaderboard:Flush()end)
  return true,"Reset saved for @"..name..". All trading history, ranks, titles and settings cleared. New $10,000 account ready."
 end,
 AfterReset=function(userId)
  -- Rejoining discards local drafts, tutorial state, preference retries and old request tokens.
  for _,player in ipairs(Players:GetPlayers())do
   if player.UserId==userId then player:Kick("The owner reset your Get Funded! data, including ranks, titles and trading history. Rejoin to start with $10,000 in-game money.")end
  end
  resettingUid=nil
 end,
})
local chat=game:GetService("TextChatService")
local oldCommand=chat:FindFirstChild("OwnerResetCommand");if oldCommand then oldCommand:Destroy()end
local resetCommand=Instance.new("TextChatCommand")
resetCommand.Name="OwnerResetCommand";resetCommand.PrimaryAlias="/reset";resetCommand.AutocompleteVisible=false
resetCommand.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then ownerCommand:Handle(player,text)end
end)
resetCommand.Parent=chat
local giveCommand=OwnerGiveCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared"and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=ownerCommand.Options.Resolve,
 Give=function(userId,name,amount,actor)
  local uid=Funded.Key(userId);local receipt=game:GetService("HttpService"):GenerateGUID(false)
  local ok,balance=world:TransformSaved(function(engine)
   local accounts=Funded.new(engine,Progression,Config,{Capacity=function(kind)return world:HasCapacity(kind)end})
   local result=accounts:GrantMoney(uid,amount,actor,receipt)
   local profile=accounts:Profile(uid);profile.PlayerName=name
   return result
  end)
  if not ok then
   if world:CanRun()then return false,"Grant not applied: "..tostring(balance)end
   return false,"Grant could not be confirmed. Wait for the saved exchange to recover and check @"..name.."'s balance before retrying."
  end
  local function money(n)return "$"..string.format("%.0f",n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")end
  return true,"Saved: gave "..money(amount).." to @"..name..". Balance: "..money(balance).."."
 end,
})
local oldGive=chat:FindFirstChild("OwnerGiveCommand");if oldGive then oldGive:Destroy()end
local giveChat=Instance.new("TextChatCommand");giveChat.Name="OwnerGiveCommand";giveChat.PrimaryAlias="/give";giveChat.AutocompleteVisible=false
giveChat.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then giveCommand:Handle(player,text)end
end)
giveChat.Parent=chat
local botsCommand=OwnerBotsCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=ownerCommand.Options.GroupLookup,
 Ready=function()return world.Mode=="Shared"and not world.Busy and world:CanRun()end,
 NextSequence=function()local r=world.Population.BotRefreshReceipt;return (r and r.Sequence or 0)+1 end,
 Notify=ownerCommand.Options.Notify,
 Refresh=function(sequence,actor)return world:RefreshBots(sequence,actor)end,
})
local oldBots=chat:FindFirstChild("OwnerBotsCommand");if oldBots then oldBots:Destroy()end
local botsChat=Instance.new("TextChatCommand");botsChat.Name="OwnerBotsCommand";botsChat.PrimaryAlias="/bots";botsChat.AutocompleteVisible=false
botsChat.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then botsCommand:Handle(player,text)end
end)
botsChat.Parent=chat
task.spawn(function()world:Open()end)
game:BindToClose(function()
 if funded then for _,state in pairs(clients)do funded:Depart(state.Uid)end end
 world:Close()
 leaderboard:Queue(world.DurableProjection)
 -- Exchange durability comes first. A missed publish is rebuilt from its save on the next owner.
 leaderboard.NextWrite=0;leaderboard:Flush()
end)
task.spawn(function()
 while not world.Closing do
  task.wait(5)
  leaderboard:Queue(world.DurableProjection)
  leaderboard:Flush()
 end
end)
local elapsed,broadcast,maintenance=0,0,0
local performance={Frames=0,Steps=0,TotalMs=0,MaxMs=0,Backlog=0,BudgetHits=0}
RunService.Heartbeat:Connect(function(dt)
 local started=os.clock()
 debug.profilebegin("FundedMarketHeartbeat")
 if epoch~=world.Epoch then
  epoch=world.Epoch market=world.Engine population=world.Population elapsed=0
  funded=market and Funded.new(market,Progression,Config,{Capacity=function(kind) return world:HasCapacity(kind) end}) or nil
  if market and funded then
   local connected={}
   for _,state in pairs(clients)do local owner=funded:Owner(state.Uid);if owner then connected[owner]=true end end
   market:SetConnectedOwners(connected)
  end
  for player,state in pairs(clients)do state.Owner=nil resolve(player,state) end
 end
 local active=world:CanRun()
 root:SetAttribute("Ready",active)root:SetAttribute("PersistenceStatus",world:Label())
 if active then elapsed+=dt*Config.SimulationSpeed else elapsed=0 end
 broadcast+=dt maintenance+=dt local steps=0
 if active then
  local limited
  elapsed,steps,limited=SimulationScheduler.Advance(elapsed,Config,function()
   -- Owner maintenance precedes the next request batch/step, never interleaves with a fill.
   if botsCommand:AtBoundary()then return false end
   -- Bound request work, with a fixed FIFO batch for deterministic replay. Every
   -- accepted tail stays queued; the simulation still completes each atomic step.
   local pending;pending,queue=RequestQueue.Take(queue)
   for _,item in ipairs(pending) do
    table.insert(actionLog,{Step=market.Step,Sequence=item.Sequence,Player=item.Player.UserId,Request=item.Request})
    if #actionLog>5000 then table.remove(actionLog,1) end
    process(item)
   end
   if not world:CanRun()then return false end
   population:Step();funded:ProcessResets()
  end,os.clock,started)
  if limited then performance.BudgetHits+=1 end
 end
 -- Already accepted requests keep their FIFO place through bot maintenance.
 if not active and #queue>0 and not world.BotRefreshSaving then
  for _,item in ipairs(queue)do local state=clients[item.Player]if state then reply(state,item.Request.Id,false,world:Label())end end
  queue={}
 end
 if maintenance>=1 then
  maintenance=0 task.spawn(function()world:Maintain()end)
  -- SL/TP can execute while a player is away; unlocks are still earned once.
  if active and funded then
   -- Progress from offline protective fills is evaluated on the same saved profile.
   
   for uid in pairs(market.Profiles)do funded:Evaluate(uid) end
  end
  -- Idle connections release expired acknowledgements even if they never send or subscribe again.
  local clock=os.clock() for _,state in pairs(clients)do replies:Prune(state,clock) end
  if world.Mode=="Following"then for player,state in pairs(clients)do route(player,state)end end
 end
 -- Do not skip simulation steps under load; catch up over subsequent frames.
 if broadcast>=Config.BroadcastSeconds then
  broadcast=broadcast%Config.BroadcastSeconds
  for player,state in pairs(clients) do if state.Subscribed then safeEmit(player,state) end end
 end
 local ms=(os.clock()-started)*1000
 performance.Frames+=1 performance.Steps+=steps performance.TotalMs+=ms
 performance.MaxMs=math.max(performance.MaxMs,ms) performance.Backlog=elapsed
 performance.LastMs=ms;performance.LastSteps=steps
 debug.profileend()
end)
-- Read-only diagnostic access in Studio; never replicated to game clients.
if RunService:IsStudio() then
 local diagnostic=Instance.new("BindableFunction") diagnostic.Name="StudioDiagnostics" diagnostic.Parent=script.Parent
 diagnostic.OnInvoke=function(command,a,b)
  if command=="Tests" then return require(script.Parent.MarketTests).Run() end
  if command=="ContinuityTests"then return require(script.Parent.WorldTests).Run()end
  if command=="SingleAccountTests"then return require(script.Parent.SingleAccountTests).Run()end
  if command=="SecurityTests"then return require(script.Parent.SecurityTests).Run()end
  if command=="LeaderboardStatus"then return {Cached=leaderboard.Cache,ReadError=leaderboard.ReadError,WriteError=leaderboard.WriteError,Pending=leaderboard.Pending,Scope=Leaderboards.Scope(world.Studio)}end
  if command=="Performance"then local result=table.clone(performance);result.MeanMs=result.TotalMs/math.max(1,result.Frames);return result end
  if command=="Actions" then return actionLog end
  if not market then return {Mode=world.Mode,Status=world:Label(),Error=world.LastError}end
  if command=="Execution"then
   local key=Config.Contracts[a]and a or Config.ContractOrder[1];local book=market.Books[key]
   local orders,levels,trades={},{Bids={},Asks={}},{ }
   for _,side in ipairs({"Bids","Asks"})do for _,level in ipairs(book[side])do
    local ids={};for _,order in ipairs(level.Orders)do table.insert(ids,order.Id)end
    table.insert(levels[side],{Price=level.Price*book.Spec.Tick,Quantity=level.Quantity,Orders=ids})
   end end
   for _,order in pairs(market.Orders)do if order.Contract==key then
    local row=table.clone(order);row.Price=row.Price and row.Price*book.Spec.Tick or nil;row.BlockedReason=market:OrderBlockReason(order)
    table.insert(orders,row)
   end end
   table.sort(orders,function(x,y)return x.Priority<y.Priority end)
   for i=math.max(1,#market.Trades-199),#market.Trades do local trade=market.Trades[i];if trade.Contract==key then table.insert(trades,trade)end end
   return {Contract=key,Step=market.Step,Time=market.Time,FairValue=book.FairReference and book.FairReference*book.Spec.Tick,
    Rules=market.Config.PlayerExecution,PriceBandFraction=market.Config.PriceBandFraction,Book=levels,Orders=orders,Executions=trades,
    Diagnostics=market.ExecutionDiagnostics,LastCloseNotificationError=market.LastCloseNotificationError,RequestQueueDepth=#queue}
  end
  if command=="Profiles"then
   local views={} for uid in pairs(market.Profiles)do views[uid]={Saved=market.Profiles[uid],View=funded:View(uid)}end return views
  end
  if command=="Stats"then
   local views={} for uid in pairs(market.Profiles)do views[uid]=funded:Stats(uid)end return views
  end
  local books={}
  for _,key in ipairs(Config.ContractOrder) do
   local book=market.Books[key]
   books[key]={Last=book.Last and book.Last*book.Spec.Tick,Volume=book.Volume,Up=book.Up,Down=book.Down,Bids=#book.Bids,Asks=#book.Asks,Candles=#book.Candles["1m"]}
  end
  local accounts={}
  for _,id in ipairs(market.AccountOrder) do local account=market.Accounts[id] if account.Player then accounts[id]=market:Snapshot(id,Config.ContractOrder[1],"1m",false) end end
  return {Seed=market.Seed,Mode=world.Mode,Status=world:Label(),Step=market.Step,Time=market.Time,Audit=market:Audit(),Books=books,Accounts=accounts,Participants=#population.Agents,Regime=population.Regime.Name}
 end
end
]====]):sub(2),Hash=([====[!cec20529bccf09603a6ce0c24e081ac4509f7e8af0f6bb18706b84ae715f19e5]====]):sub(2),ExpectedHash=([====[!30dbf55cabf4a2e7383a6b73393245c039c3a1db598ed1902dd6ec6aa52cd655]====]):sub(2),ClassName=([====[!Script]====]):sub(2)}
local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end
for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Release hash mismatch "..path);if item.ExpectedHash then assert(instance and instance.ClassName==item.ClassName,"Missing/wrong class "..path);assert(hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash,"Source changed since backup: "..path)else assert(not instance or instance.ClassName==item.ClassName and hash(instance.Source)==item.Hash,"New module collision "..path)end end
local ordered={};for path in pairs(release)do table.insert(ordered,path)end;table.sort(ordered)
for _,path in ipairs(ordered)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new(item.ClassName);instance.Name=name;instance.Source=item.Source;instance.Parent=parent else instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Installed source mismatch "..path)end
return "Installed /bots refresh (8 sources). Save the local place, then start a new play session. Nothing published."
