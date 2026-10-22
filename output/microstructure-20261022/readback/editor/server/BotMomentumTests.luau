local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local M=require(script.Parent.BotMomentum)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture()
 local c=copy(C);local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}}},P)
 local a=p:_agent('BX','Momentum',1);local b=e.Books.BX
 e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=M.Adopt(p,a);s.CooldownUntil=0;s.Horizon=60;s.Confirmation=10;s.Threshold=.8;s.Style='Trend';s.NextReview=0
 return e,p,a,b,s
end
local function quote(e,b,side,qty,tick)
 return e:Submit(side==1 and 'buyer'or 'seller',{Contract=b.Key,Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or (b.Last or b.Reference)-side)*b.Spec.Tick})
end
local function history(e,p,b,side,flat)
 local start=b.Reference;e.Time=100
 local h={};for t=0,100,5 do table.insert(h,{Time=t,Price=start+(flat and 0 or side*t/5)})end
 p.Markets.BX.MomentumHistory=h
 -- Establish the last through a real, funded match. History is a signal fixture only.
 local tick=h[#h].Price
 assert(quote(e,b,-1,1,tick));assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
 quote(e,b,1,100);quote(e,b,-1,100)
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Stable profiles diversify horizons without consuming shared RNG',function()
  local e,p,a,b,s=fixture();local before=p.Random.State;local horizons,styles={},{}
  for i=2,37 do local agent=p:_agent('BX','Momentum',i);local state=p.Random.State;local q=M.Adopt(p,agent);assert(p.Random.State==state);horizons[q.Cohort]=true;styles[q.Style]=true end
  assert(horizons[1]and horizons[2]and horizons[3]and styles.Trend and styles.Breakout)
  local q=copy(s);a.Momentum=nil;local again=M.Adopt(p,a)
  -- Profile's own first draws are repeatable regardless of global RNG state.
  assert(q.RandomState==again.RandomState)
 end)
 test('Time-based signal is symmetric; flat, stale and incomplete histories cannot enter',function()
  for _,side in ipairs({1,-1})do local e,p,a,b,s=fixture();history(e,p,b,side);local signal=assert(M.Signal(p,a,s));assert(signal.Side==side)
   e.Time+=11;assert(not M.Signal(p,a,s));e:Audit()
  end
  local e,p,a,b,s=fixture();history(e,p,b,1,true);assert(M.Signal(p,a,s).Side==0)
  s.Horizon=600;assert(not M.Signal(p,a,s));e:Audit()
 end)
 test('Breakout uses prior completed range and rejects an unbroken range',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);s.Style='Breakout';s.Confirmation=20
  assert(M.Signal(p,a,s).Side==1)
  p.Markets.BX.MomentumHistory[17].Price=b.Last+10
  assert(M.Signal(p,a,s).Side==0);e:Audit()
 end)
 test('Building is time-budgeted, funded, IOC and cannot manufacture fills',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);local base=e.Accounts[a.Id].Base
  M.Step(p,a);assert(s.Phase=='Building'and s.Filled>0);local filled=s.Filled
  for _=1,6 do M.Step(p,a)end
  -- Faster build profiles can have more than one contract due in their first time bucket.
  -- Repeated calls cannot spend beyond that fixed time budget or leave an IOC remainder.
  local due=math.ceil(math.abs(s.Target)*math.clamp((e.Time-s.StartedAt+C.BotMomentum.SliceSeconds[2])/s.BuildSeconds,0,1))
  assert(s.Filled>=filled and s.Filled<=due and not next(e.Accounts[a.Id].OpenOrders));filled=s.Filled
  assert(e:Exposure(e.Accounts[a.Id],'BX',1,0));assert(e.Accounts[a.Id].Base==base);e:Audit()
  e:CancelAll('seller');e:CancelAll('buyer');local volume=e.TotalVolume;local last=b.Last;e.Time+=10;M.Step(p,a)
  assert(e.TotalVolume==volume and b.Last==last and s.Filled==filled);e:Audit()
 end)
 test('Price-capped children cannot consume distant quotes',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);e:CancelAll('seller');quote(e,b,-1,1,b.Last+1);quote(e,b,-1,100,b.Last+15)
  a.Size=40;s.Target=20;s.Filled=0;s.StartedAt=0;s.BuildSeconds=200;s.BuildUntil=300;s.Phase='Building';s.NextReview=1000
  M.Step(p,a);assert(e.Accounts[a.Id].Positions.BX.Quantity==1);assert(not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Holding survives weak signals; sustained opposite thesis reduces without reversing',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a);local pos=e.Accounts[a.Id].Positions.BX;assert(pos)
  s.Phase='Holding';s.NextReview=0;s.Threshold=20;M.Step(p,a);assert(s.Phase=='Holding')
  s.Threshold=.8;p.Markets.BX.MomentumHistory[9].Price=b.Last+30
  s.NextReview=0;M.Step(p,a);assert(s.InvalidSince and s.Phase=='Holding')
  e.Time+=s.Confirmation+1;M.Sample(p,'BX');s.NextReview=0
  -- Continue a clear negative lookback at the later window boundary.
  for _,v in ipairs(p.Markets.BX.MomentumHistory)do if v.Time<=e.Time-s.Horizon then v.Price=b.Last+30 end end
  M.Step(p,a);assert(s.Phase=='Reducing'or s.Phase=='Waiting');local held=e.Accounts[a.Id].Positions.BX;assert(not held or held.Direction==1);e:Audit()
 end)
 test('Time exit ignores entry warmup and closes before any reversal',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a);s.OpenedAt=e.Time-s.HoldSeconds;p.Markets.BX.MomentumHistory={}
  M.Step(p,a);assert(not e.Accounts[a.Id].Positions.BX and s.Phase=='Waiting'and s.CooldownUntil>e.Time);e:Audit()
 end)
 test('Empty exit book retains inventory and retries through real liquidity',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a);s.OpenedAt=e.Time-s.HoldSeconds;e:CancelAll('buyer');e:CancelAll('seller')
  local qty=e.Accounts[a.Id].Positions.BX.Quantity;local volume=e.TotalVolume;M.Step(p,a)
  assert(s.Phase=='Reducing'and e.Accounts[a.Id].Positions.BX.Quantity==qty and e.TotalVolume==volume)
  quote(e,b,1,100);M.Step(p,a);assert(not e.Accounts[a.Id].Positions.BX);e:Audit()
 end)
 test('Stopped positions and recovery cannot resurrect an old mandate',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a)
  assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Market',ReduceOnly=true}))
  local volume=e.TotalVolume;M.Step(p,a);assert(s.Phase=='Waiting'and e.TotalVolume==volume and s.CooldownUntil>e.Time);e:Audit()
 end)
 test('Trailing stops tighten only; locked and triggered positions never enter',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a);local ac=e.Accounts[a.Id];local pos=ac.Positions.BX;local stop=pos.Stop
  s.Phase='Holding';s.Best=pos.Entry/b.Spec.Tick+a.Stop*2;M.Step(p,a);assert(pos.Stop>stop);local tighter=pos.Stop
  s.Best=b.Last;M.Step(p,a);assert(pos.Stop==tighter)
  pos.Triggered='Stop loss';local orders=e.NextOrder;M.Step(p,a);assert(e.NextOrder==orders)
  pos.Triggered=nil;ac.Locked=true;M.Step(p,a);assert(e.NextOrder==orders);e:Audit()
 end)
 test('Adoption preserves funding, positions and reduce-only exits',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);M.Step(p,a);local ac=e.Accounts[a.Id]
  local ok,x=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Last+30)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local pos=copy(ac.Positions);local cash=ac.Balance;local volume=e.TotalVolume;a.Momentum=nil;M.Adopt(p,a)
  equal(pos,ac.Positions);assert(e.Orders[x.Id]and ac.Balance==cash and e.TotalVolume==volume);e:Audit()
 end)
 test('V25 migration is read-only and V26 checkpoint continuation is exact',function()
  local e=E.new(copy(C),7919);local p=P.new(e)
  for _=1,80 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=25;saved.Config.BotMomentum=nil
  for _,a in ipairs(saved.Population.Agents)do a.Momentum=nil end
  for _,market in pairs(saved.Population.Markets)do market.MomentumHistory=nil end
  local re,rp=CP.Restore(saved,C);assert(re.NextTrade==e.NextTrade and re.TotalVolume==e.TotalVolume and re.Time==e.Time)
  for _,old in ipairs(saved.Engine.Accounts)do local ac=re.Accounts[old.Id];assert(ac.Base==old.Base and ac.Balance==old.Balance and ac.Realized==old.Realized);equal(ac.Positions,old.Positions)end
  local round=CP.Decode(CP.Encode(CP.Capture(re,rp)));local rr,pr=CP.Restore(round,C)
  for _=1,100 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local down=copy(C);down.BotMomentum=nil;assert(not pcall(CP.Restore,CP.Capture(re,rp),down))
  local newer=CP.Capture(re,rp);newer.Config.BotMomentum.Version+=1;assert(not pcall(CP.Restore,newer,C))
 end)
 test('Active build, hold, reduction and cooldown states serialize and continue exactly',function()
  for _,phase in ipairs({'Building','Holding','Reducing','Cooldown'})do
   local e=E.new(copy(C),1729);local p=P.new(e);local a
   for _,agent in ipairs(p.Agents)do if agent.Kind=='Momentum'and agent.Key=='BX'then a=agent;break end end
   local s=M.Adopt(p,a);s.CooldownUntil=0
   local ac=e.Accounts[a.Id];local ok,r=e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market',StopTicks=a.Stop});assert(ok and r.Filled==1)
   s.PositionId=ac.Positions.BX.Id;s.OpenedAt=e.Time;s.Best=e.Books.BX.Last
   s.Phase=phase=='Cooldown'and 'Waiting'or phase;s.Target=4;s.Filled=1;s.StartedAt=e.Time;s.BuildUntil=e.Time+s.BuildSeconds
   if phase=='Cooldown'then s.CooldownUntil=e.Time+100 end
   local snapshot=CP.Decode(CP.Encode(CP.Capture(e,p)));local re,rp=CP.Restore(snapshot,C)
   for _=1,40 do p:Step();rp:Step()end
   equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
  end
 end)
 test('History remains bounded and dormant accounts cannot accumulate fabricated price signals',function()
  local e,p,a,b,s=fixture()
  for i=1,400 do e.Time=i*5;M.Sample(p,'BX')end
  assert(#p.Markets.BX.MomentumHistory<=C.BotMomentum.RetentionSeconds/C.BotMomentum.SampleSeconds+2)
  local prior=e.NextTrade;assert(not M.Signal(p,a,s));M.Step(p,a)
  assert(e.NextTrade==prior and not e.Accounts[a.Id].Positions.BX)
 end)
 return out
end
return T
