local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local R=require(script.Parent.BotReversion)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra')end
end
local function fixture()
 local c=copy(C);local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}},Regime={Volatility=1,Liquidity=1,Activity=1}},P)
 local a=p:_agent('BX','Reversion',1);a.Size=2;a.Limit=40;a.Stop=24;local ac=e.Accounts[a.Id];ac.Limit=40
 e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=R.Adopt(p,a);s.Horizon=60;s.Recent=10;s.Extension=6;s.Deceleration=.6;s.Aggression=1;s.ReadyAt=0;s.Hold=90
 return e,p,a,e.Books.BX,s
end
local function quote(e,b,side,qty,tick)
 local ok,r=e:Submit(side==1 and 'buyer'or 'seller',{Contract='BX',Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or(b.Last or b.Reference)-side)*b.Spec.Tick});assert(ok,tostring(r));return r
end
local function history(e,p,b,direction,mode)
 e.Time=100;local h={};p.Markets.BX.ReversionHistory=h
 local anchor=b.Reference
 for t=0,100,2 do
  local move=t<=90 and t*.5 or 45+(t-90)*(mode=='Accelerating'and 1 or mode=='Flat'and .5 or .1)
  if mode=='Flat'then move=0 end
  table.insert(h,{Time=t,Price=anchor+direction*move})
 end
 b.Last=h[#h].Price
 quote(e,b,1,100,b.Last-1);quote(e,b,-1,100,b.Last+1)
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Profiles are diverse, stable and do not consume shared RNG',function()
  local e,p,a,b,s=fixture();local horizons,delays={},{}
  for i=2,40 do local a=p:_agent('BX','Reversion',i);local before=p.Random.State;local q=R.Adopt(p,a);assert(p.Random.State==before);horizons[math.floor((q.Horizon-p.Config.BotReversion.LookbackSeconds[1])/(p.Config.BotReversion.LookbackSeconds[2]-p.Config.BotReversion.LookbackSeconds[1])*8)]=true;delays[math.floor((q.Cooldown-p.Config.BotReversion.CooldownSeconds[1])/(p.Config.BotReversion.CooldownSeconds[2]-p.Config.BotReversion.CooldownSeconds[1])*8)]=true;assert(R.Adopt(p,a)==q)end
  local n=0;for _ in pairs(horizons)do n+=1 end;assert(n>=4);local n=0;for _ in pairs(delays)do n+=1 end;assert(n>=4)
 end)
 test('A stretched slowing continuation admits a fade before an opposite print, symmetrically',function()
  for _,direction in ipairs({1,-1})do local e,p,a,b,s=fixture();history(e,p,b,direction,'Slowing');local signal=assert(R.Signal(p,a,s));assert(signal.Side==-direction and signal.RecentRate*direction>0 and signal.PriorRate*direction>signal.RecentRate*direction)
   p.Markets.BX.Fair=b.Last+100000;a.Belief=b.Last-100000;equal(signal,R.Signal(p,a,s))
  end
 end)
 test('Flat, accelerating, stale and insufficient histories do not create entries',function()
  for _,mode in ipairs({'Flat','Accelerating'})do local e,p,a,b,s=fixture();history(e,p,b,1,mode);assert(R.Signal(p,a,s).Side==0)end
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');e.Time+=5;assert(not R.Signal(p,a,s));p.Markets.BX.ReversionHistory={};assert(not R.Signal(p,a,s))
 end)
 test('Sampling follows simulation time, is bounded and does not read execution count',function()
  local e,p,a,b,s=fixture();for i=0,400 do e.Time=i;R.Sample(p,'BX');R.Sample(p,'BX')end
  local h=p.Markets.BX.ReversionHistory;assert(#h<=102);assert(h[#h].Time==400);local n=#h;b.Recent=table.create(1000,b.Reference);R.Sample(p,'BX');assert(#h==n)
 end)
 test('Entry fills are funded and capped, with stops and no pyramiding',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');local before=e.TotalVolume;R.Step(p,a)
  local pos=assert(e.Accounts[a.Id].Positions.BX);assert(pos.Direction==-1 and pos.Quantity<=R.Capacity(p,a,math.clamp(a.Stop,p.Config.BotReversion.MinStopTicks,p.Config.BotReversion.MaxStopTicks))and pos.Stop)
  assert(e.TotalVolume-before==pos.Quantity and e.Accounts[a.Id].NetCapitalAdjustments==0)
  local qty=pos.Quantity;R.Step(p,a);assert(e.Accounts[a.Id].Positions.BX.Quantity==qty);e:Audit()
 end)
 test('Passive entries expire and cannot be instantly replenished',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');s.Aggression=0;R.Step(p,a);local id=assert(s.ChildId);local o=e.Orders[id];assert(o and not e.Accounts[a.Id].Positions.BX)
  R.Step(p,a);assert(s.ChildId==id);e:AdvanceClock(o.Expires-e.Time);R.Step(p,a);assert(not s.ChildId and s.ReadyAt>e.Time);local orders=e.NextOrder;R.Step(p,a);assert(e.NextOrder==orders);e:Audit()
 end)
 test('Partial entry fills cancel the remaining entry at the next observation',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');s.Aggression=0;R.Step(p,a);local id=assert(s.ChildId)
  e:CancelAll('seller');assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}));assert(e.Accounts[a.Id].Positions.BX)
  R.Step(p,a);assert(not e.Orders[id]and not s.ChildId);assert(e.Accounts[a.Id].Positions.BX.Quantity==1);e:Audit()
 end)
 test('Profit exits are reduce-only, retain FIFO, and cannot reverse inventory',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');R.Step(p,a);R.Step(p,a);local id=assert(s.ExitId);local o=e.Orders[id];assert(o.ReduceOnly);local priority=o.Priority;R.Step(p,a);assert(e.Orders[id].Priority==priority)
  e:CancelAll('buyer');assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=100,Type='Market'}));assert(not e.Accounts[a.Id].Positions.BX);R.Step(p,a);assert(s.Phase=='Waiting'and s.ReadyAt>e.Time);e:Audit()
 end)
 test('Timed exits cancel only their own target and use capped genuine matches',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');R.Step(p,a);R.Step(p,a);local target=assert(s.ExitId);local qty=e.Accounts[a.Id].Positions.BX.Quantity;local volume=e.TotalVolume
  e:AdvanceClock(s.Hold+1);R.Step(p,a);assert(not e.Orders[target]);local pos=e.Accounts[a.Id].Positions.BX
  assert(not pos or pos.Quantity<qty);assert(e.TotalVolume>volume);e:Audit()
 end)
 test('Manual exits and protection survive adoption and share the closing inventory budget',function()
  local e,p,a,b,s=fixture();quote(e,b,-1,5);assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Market',StopTicks=20}));local pos=e.Accounts[a.Id].Positions.BX;pos.ManualStop=true
  local stop=pos.Stop;local ok,o=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=(b.Last+40)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  a.Reversion=nil;R.Step(p,a);assert(e.Orders[o.Id]and pos.Stop==stop and pos.ManualStop)
  local count=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do if e.Orders[id].ReduceOnly then count+=e.Orders[id].Remaining end end;assert(count==2);e:Audit()
  pos.Stop=nil;pos.ManualStop=true;a.Reversion=nil;R.Step(p,a);assert(pos.Stop==nil and pos.ManualStop and e.Orders[o.Id]);e:Audit()
 end)
 test('Locks, liquidation, retirement, triggered protection and no buying power block entry',function()
  for _,condition in ipairs({'Locked','Liquidating','Retiring','Risk'})do local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing')
   if condition=='Retiring'then a.Retiring=true elseif condition=='Risk'then e.Accounts[a.Id].Risk=0 else e.Accounts[a.Id][condition]=true end
   R.Step(p,a);assert(e.TotalVolume==0 and not next(e.Accounts[a.Id].OpenOrders));e:Audit()
  end
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');R.Step(p,a);e.Accounts[a.Id].Positions.BX.Triggered='Stop loss';local n=e.NextOrder;R.Step(p,a);assert(e.NextOrder==n)
 end)
 test('V27 adoption is read-only for economic state; policy downgrades fail closed',function()
  local old=copy(C);old.BotReversion=nil;local e=E.new(old,7919);local p=P.new(e);for _=1,40 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=27;local before=copy(saved);local re,rp=CP.Restore(saved,C);equal(saved,before);equal(saved.Engine,CP.Capture(re,rp).Engine);equal(saved.Population,CP.Capture(re,rp).Population)
  assert(CP.Version==28 and re.Config.NewsFrequency==0 and re.Config.BotMomentum.Version==old.BotMomentum.Version and re.Config.BotWhale.Version==old.BotWhale.Version)
  assert(not pcall(CP.Restore,CP.Capture(re,rp),old));local future=CP.Capture(re,rp);future.Config.BotReversion.Version+=1;assert(not pcall(CP.Restore,future,C));re:Audit()
 end)
 test('Full population profiles and sample windows serialize exactly',function()
  local e=E.new(copy(C),7919);local p=P.new(e)
  for _=1,900 do p:Step()end
  local saved=CP.Capture(e,p);local re,rp=CP.Restore(CP.Decode(CP.Encode(saved)),C);equal(saved,CP.Capture(re,rp))
  for _=1,160 do p:Step();rp:Step()end
  equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
 end)
 test('Pending, unobserved-partial, holding and reducing checkpoints resume exactly',function()
  for _,phase in ipairs({'Pending','Partial','Holding','Reducing'})do
   local e=E.new(copy(C),123);local p=P.new(e);local a
   for _,agent in ipairs(p.Agents)do if agent.Kind=='Reversion'and agent.Key=='BX'then a=agent;break end end
   for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
   e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
   a.Size=2;a.Stop=24;local b=e.Books.BX;local s=R.Adopt(p,a)
   s.Horizon=60;s.Recent=10;s.Extension=6;s.Deceleration=.6;s.ReadyAt=0;s.Hold=90;s.Aggression=(phase=='Pending'or phase=='Partial')and 0 or 1
   history(e,p,b,1,'Slowing');R.Step(p,a)
   if phase=='Pending'then assert(s.ChildId and e.Orders[s.ChildId]and not e.Accounts[a.Id].Positions.BX)
   elseif phase=='Partial'then e:CancelAll('seller');assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}));assert(not s.PositionId and e.Accounts[a.Id].Positions.BX)
   else
    assert(s.Phase=='Holding'and s.PositionId)
    if phase=='Reducing'then e:CancelAll('seller');e:AdvanceClock(91);R.Step(p,a);assert(s.Phase=='Reducing'and e.Accounts[a.Id].Positions.BX)end
   end
   local saved=CP.Capture(e,p);local re,rp=CP.Restore(CP.Decode(CP.Encode(saved)),C);equal(saved,CP.Capture(re,rp))
   for _=1,80 do p:Step();rp:Step()end
   equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
  end
 end)
 test('A passive entry filled and stopped between decisions cannot restart immediately',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,'Slowing');s.Aggression=0;R.Step(p,a);local id=assert(s.ChildId)
  e:CancelAll('seller');local qty=e.Orders[id].Remaining;assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=qty,Type='Market'}));local pos=assert(e.Accounts[a.Id].Positions.BX);assert(not s.PositionId)
  while b.Last*b.Spec.Tick<pos.Stop do
   local nextTick=math.min(math.round(pos.Stop/b.Spec.Tick),b.Last+10)
   quote(e,b,-1,1,nextTick);assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  end
  quote(e,b,-1,10,b.Last+1);e:ProcessStops();assert(not e.Accounts[a.Id].Positions.BX)
  local volume=e.TotalVolume;R.Step(p,a);assert(s.Phase=='Waiting'and s.ReadyAt>e.Time and e.TotalVolume==volume);e:Audit()
 end)
 return out
end
return T
