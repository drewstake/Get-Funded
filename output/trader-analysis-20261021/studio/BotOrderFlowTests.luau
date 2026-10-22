local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local F=require(script.Parent.BotOrderFlow)
local CP=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=clone(x)end;return t end
local function equal(a,b)
 assert(type(a)==type(b),'Different types')
 if type(a)~='table'then assert(a==b,'Different values '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra field '..tostring(k))end
end
local function fixture(side)
 local c=clone(C);c.BotOrderFlow.SliceFraction={.25,.25};local e=E.new(c,71)
 local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(71),Markets={BX={}},Agents={}},P)
 local a=p:_agent('BX','Whale',1);a.Size=4;a.OrderFlowPolicy=c.BotOrderFlow.Version
 a.OrderObjective={Target=side*6,StartedAt=0,ExpiresAt=100,Filled=0}
 e:AddAccount('supplier',1e8,10000,1,false)
 return e,p,a,e.Books.BX
end
local function quote(e,b,side,size)
 assert(e:Submit('supplier',{Contract=b.Key,Direction=-side,Quantity=size or 100,Type='Limit',Price=(b.Last or b.Reference)*b.Spec.Tick+side*b.Spec.Tick}))
end
function Tests.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('Independent goals persist through actual buys and sells without funding bots',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b=fixture(side);quote(e,b,side);local ac=e.Accounts[a.Id];local base=ac.Base;local goal=a.OrderObjective
   for _=1,6 do F.Step(p,a);e:AdvanceClock(5)end
   assert(ac.Positions.BX.Quantity==6 and ac.Positions.BX.Direction==side)
   assert(a.OrderObjective==goal and goal.Filled==6 and e.TotalVolume==6)
   assert(ac.Base==base and ac.NetCapitalAdjustments==0 and not next(ac.OpenOrders))
   e:Audit()
  end
 end)
 test('Completed goals remain held until their deadline without flipping',function()
  local e,p,a,b=fixture(1);quote(e,b,1)
  for _=1,6 do F.Step(p,a);e:AdvanceClock(5)end
  local volume=e.TotalVolume;local position=clone(e.Accounts[a.Id].Positions)
  F.Step(p,a)
  assert(a.OrderObjective and a.OrderObjective.Target==6 and e.TotalVolume==volume)
  e:AdvanceClock(70);F.Step(p,a)
  assert(a.OrderObjective==nil and e.TotalVolume==volume and a.FlowCooldownUntil>e.Time)
  equal(position,e.Accounts[a.Id].Positions);e:Audit()
 end)
 test('New mandates spread their finite quantity over simulated time',function()
  local e,p,a,b=fixture(1);local ac=e.Accounts[a.Id]
  a.OrderObjective=nil;a.Limit=20;ac.Limit=20;a.Size=40
  p.Config.BotOrderFlow.TargetFraction={.5,.5};p.Config.BotOrderFlow.DurationSeconds={100,100}
  p.Random={Next=function()return .25 end,Range=function(_,lo,hi)return lo end}
  quote(e,b,1);F.Step(p,a)
  assert(a.OrderObjective.Target==10 and a.OrderObjective.PlannedQuantity==10)
  assert(e.TotalVolume==1,'Mandate front-loaded its full quantity')
  for _=1,5 do F.Step(p,a)end
  assert(e.TotalVolume==1,'Repeated decisions bypassed the time budget')
  e:AdvanceClock(40);F.Step(p,a)
  assert(e.TotalVolume==5 and a.OrderObjective.Filled==5);e:Audit()
 end)
 test('Externally closed positions end the mandate and cannot immediately re-enter',function()
  local e,p,a,b=fixture(1);quote(e,b,1);F.Step(p,a)
  local ac=e.Accounts[a.Id];assert(a.FlowPositionId==ac.Positions.BX.Id)
  e:CancelAll('supplier');quote(e,b,-1)
  assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Market',ReduceOnly=true}))
  assert(not ac.Positions.BX);local volume=e.TotalVolume
  F.Step(p,a);local deadline=a.FlowCooldownUntil
  assert(not a.OrderObjective and deadline>=e.Time+C.BotOrderFlow.StopPauseSeconds[1])
  quote(e,b,1);F.Step(p,a);e:AdvanceClock(deadline-e.Time-.25);F.Step(p,a)
  assert(e.TotalVolume==volume and not ac.Positions.BX and a.FlowNextDecision==deadline);e:Audit()
 end)
 test('Voluntary reductions clear tracked position identity without a stop cooldown',function()
  local e,p,a,b=fixture(1);quote(e,b,1);F.Step(p,a)
  e:CancelAll('supplier');quote(e,b,-1);a.OrderObjective.Target=-2
  F.Step(p,a);assert(not e.Accounts[a.Id].Positions.BX and not a.FlowPositionId)
  F.Step(p,a);assert(e.Accounts[a.Id].Positions.BX.Direction==-1 and not a.FlowCooldownUntil);e:Audit()
 end)
 test('Drawdown reductions bypass an exhausted execution budget',function()
  local e,p,a,b=fixture(1);quote(e,b,1);F.Step(p,a)
  e:CancelAll('supplier');quote(e,b,-1);a.Budget=e.Accounts[a.Id].Balance*2
  a.OrderObjective.PlannedQuantity=0;F.Step(p,a)
  assert(not e.Accounts[a.Id].Positions.BX);e:Audit()
 end)
 test('An empty book cannot move price, manufacture fills or consume an objective',function()
  local e,p,a,b=fixture(1);local before=b.Last;local base=e.Accounts[a.Id].Balance
  for _=1,5 do F.Step(p,a);e:AdvanceClock(5)end
  assert(b.Last==before and e.TotalVolume==0 and a.OrderObjective.Filled==0)
  assert(e.Accounts[a.Id].Balance==base and not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Partial child orders count fills only and cancel their unfilled remainder',function()
  local e,p,a,b=fixture(1);a.Size=40;quote(e,b,1,2);F.Step(p,a)
  assert(a.OrderObjective.Filled==2 and e.TotalVolume==2 and e.Accounts[a.Id].Positions.BX.Quantity==2)
  assert(not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Slices respect the price cap and cannot jump to distant liquidity',function()
  local e,p,a,b=fixture(1);a.Size=40;quote(e,b,1,1)
  assert(e:Submit('supplier',{Contract='BX',Direction=-1,Quantity=100,Type='Limit',Price=(b.Reference+15)*b.Spec.Tick}))
  F.Step(p,a);assert(e.TotalVolume==1 and b.Last==b.Reference+1);assert(not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Goals respect funded inventory limits and close before reversing',function()
  local e,p,a,b=fixture(1);local ac=e.Accounts[a.Id];ac.Limit=2;a.Limit=2;a.Size=40
  quote(e,b,1);F.Step(p,a);assert(ac.Positions.BX.Quantity<=2);local qty=ac.Positions.BX.Quantity
  e:CancelAll('supplier');quote(e,b,-1);a.OrderObjective.Target=-2;F.Step(p,a)
  assert(not ac.Positions.BX,'Reduce-only slice reversed inventory')
  assert(a.OrderObjective.Filled==qty*2);e:Audit()
 end)
 test('Locked, liquidating and triggered accounts do not submit new pressure',function()
  for _,condition in ipairs({'Locked','Liquidating','Triggered'})do
   local e,p,a,b=fixture(1);quote(e,b,1);local ac=e.Accounts[a.Id]
   if condition=='Triggered'then F.Step(p,a);ac.Positions.BX.Triggered='Stop'else ac[condition]=true end
   local volume=e.TotalVolume;F.Step(p,a);assert(e.TotalVolume==volume)
  end
 end)
 test('Expired goals pause and drawdown protection only reduces exposure',function()
  local e,p,a,b=fixture(1);quote(e,b,1);a.OrderObjective.ExpiresAt=0;F.Step(p,a)
  assert(e.TotalVolume==0 and a.OrderObjective==nil and a.FlowNextDecision>e.Time)
  local se,sp,sa,sb=fixture(1);quote(se,sb,1)
  sa.Budget=se.Accounts[sa.Id].Balance*2;F.Step(sp,sa);assert(se.TotalVolume==0)
 end)
 test('Strategy adoption preserves inventory, funding and reduce-only exits',function()
  local e,p,a,b=fixture(1);quote(e,b,1);F.Step(p,a);local ac=e.Accounts[a.Id]
  local ok,exit=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Reference+10)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local _,entry=e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=(b.Reference-10)*b.Spec.Tick})
  local balance,base,volume,position=ac.Balance,ac.Base,e.TotalVolume,clone(ac.Positions)
  a.OrderFlowPolicy=nil;F.Step(p,a)
  assert(e.Orders[exit.Id] and not e.Orders[entry.Id]);equal(ac.Positions,position)
  assert(ac.Balance==balance and ac.Base==base and e.TotalVolume==volume);e:Audit()
 end)
 test('V23 migration preserves accounts and tape; goals continue exactly through serialization',function()
  local old=clone(C);old.BotOrderFlow=nil;old.MakerQuotePolicyVersion=5;old.ReservePopulationVersion=2
  local e=E.new(old,193);local p=P.new(e);for _=1,40 do p:Step()end
  local snapshot=CP.Capture(e,p);snapshot.Version=23;local untouched=clone(snapshot)
  local re,rp=CP.Restore(snapshot,C);equal(snapshot,untouched)
  assert(re.NextTrade==e.NextTrade and re.TotalVolume==e.TotalVolume and re.Time==e.Time)
  for id,ac in pairs(e.Accounts)do local restored=re.Accounts[id];assert(ac.Balance==restored.Balance and ac.Base==restored.Base and ac.Realized==restored.Realized);equal(ac.Positions,restored.Positions)end
  for _=1,160 do rp:Step()end
  local saved=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C)
  equal(saved,CP.Capture(rr,pr))
  for _=1,240 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  assert(CP.Version==25)
  local future=clone(saved);future.Config.BotOrderFlow.Version=C.BotOrderFlow.Version+1
  assert(not pcall(CP.Restore,future,C),'Newer pressure policy accepted by older reader')
 end)
 test('Checkpoint index reconstruction preserves blocked status and account revision',function()
  local c=clone(C);local e=E.new(c,819);local p=P.new(e);local a=p.Agents[1]
  local ac=e.Accounts[a.Id];local id=next(ac.OpenOrders);local order=assert(e.Orders[id])
  ac.Risk=0;local available,reason=e:_available(order,true);assert(available==0)
  e:_blocked(order,reason);assert(order.Status=='Blocked')
  local saved=CP.Capture(e,p);local restored,rp=CP.Restore(CP.Decode(CP.Encode(saved)),c)
  equal(saved,CP.Capture(restored,rp));restored:Audit()
 end)
 test('Legacy configurations without funded population policy keep their existing strategy',function()
  local e,p,a=fixture(1);p.Config.BotPopulation=nil
  assert(not F.Enabled(p,a));F.Step(p,a);assert(e.TotalVolume==0)
 end)
 test('Consumed reserve quotes wait before refilling their slot',function()
  local e,p,a,b=fixture(1);p.Regime={Liquidity=1};local reserve=p:_agent('BX','Reserve',1)
  p:_reserve(reserve);local id=assert(reserve.Quotes['-1:1']);e:Cancel(reserve.Id,id)
  p:_reserve(reserve);assert(not reserve.Quotes['-1:1'])
  local deadline=assert(reserve.ReserveReplenishAt['-1:1'])
  e:AdvanceClock(deadline-e.Time-.25);p:_reserve(reserve);assert(not reserve.Quotes['-1:1'])
  e:AdvanceClock(.25);p:_reserve(reserve);assert(reserve.Quotes['-1:1']);e:Audit()
 end)
 return out
end
return Tests

