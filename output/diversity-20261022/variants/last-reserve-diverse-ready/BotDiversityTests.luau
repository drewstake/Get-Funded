-- Synthetic signal inputs test decisions; all execution assertions use the real funded engine.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local D=require(script.Parent.BotDiversity)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra')end
end
local function fixture(kind)
 local c=copy(C);c.BotDiversity.Stretch=true;c.BotDiversity.Portfolio=true
 local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}},Regime={Volatility=1,Liquidity=1,Activity=1}},P)
 local a=p:_agent('BX',kind or'Reversion',1);a.Size=3;a.Limit=30;a.Stop=30;e.Accounts[a.Id].Limit=30
 e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=D.Adopt(p,a);s.Horizon=60;s.Extension=.0003;s.ReadyAt=0;s.Hold=90;s.TargetFraction=.5;s.Build=15
 return e,p,a,e.Books.BX,s
end
local function quote(e,b,side,qty,tick)
 local ok,r=e:Submit(side==1 and'buyer'or'seller',{Contract='BX',Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or(b.Last or b.Reference)-side)*b.Spec.Tick})
 assert(ok,tostring(r));return r
end
local function history(e,p,b,direction,flat)
 e:AdvanceClock(100-e.Time);local h={};p.Markets.BX.MomentumHistory=h
 local last=b.Last or b.Reference
 for t=0,100,5 do table.insert(h,{Time=t,Price=last-(flat and 0 or direction*(100-t)*1.5)})end
 quote(e,b,1,100);quote(e,b,-1,100)
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and'Passed'or tostring(r)})end
 test('Legacy policy configurations cannot accidentally enable diversity',function()
  for _,key in ipairs({'BotOrderFlow','BotPopulation','BotMomentum'})do
   local e,p,a,b,s=fixture();p.Config[key]=nil;assert(not D.Enabled(p,a));D.Step(p,a);assert(e.TotalVolume==0)
  end
 end)
 test('Execution-policy migration retains every saved Whale profile and economic state',function()
  local old=copy(C);old.BotWhale.AggressiveProbability={.10,.35};local e=E.new(old,7919);local p=P.new(e)
  for _=1,80 do p:Step()end
  local before=CP.Capture(e,p);local re,rp=CP.Restore(before,C);local after=CP.Capture(re,rp)
  equal(before.Engine,after.Engine);equal(before.Population,after.Population)
  equal(re.Config.BotWhale.AggressiveProbability,C.BotWhale.AggressiveProbability)
  assert(re.Config.BotWhale.Version==old.BotWhale.Version)
 end)

 test('Private independent profiles are diverse, persistent and do not draw shared RNG',function()
  local e,p,a,b,s=fixture();local buckets={};local states={}
  for i=2,40 do local a=p:_agent('BX','Reversion',i);local n=p.Random.State;local x=D.Adopt(p,a);assert(n==p.Random.State and D.Adopt(p,a)==x);buckets[math.floor(x.Horizon/60)]=true;assert(not states[x.RandomState]);states[x.RandomState]=true end
  local n=0;for _ in pairs(buckets)do n+=1 end;assert(n>=4)
 end)
 test('Stretched prices admit symmetric counterflow before any slowing or reversal',function()
  for _,side in ipairs({1,-1})do local e,p,a,b,s=fixture();history(e,p,b,side);local x=assert(D.Signal(p,a,s));assert(x.Side==-side and x.Distance>=x.Required)
   a.Belief=1e12;p.Markets.BX.Fair=-1e12;equal(x,D.Signal(p,a,s))
  end
 end)
 test('Flat, stale, short and one-sided observations cannot create stretch orders',function()
  local e,p,a,b,s=fixture();history(e,p,b,1,true);assert(D.Signal(p,a,s).Side==0)
  history(e,p,b,1);e:AdvanceClock(11);assert(not D.Signal(p,a,s));p.Markets.BX.MomentumHistory={};assert(not D.Signal(p,a,s))
  local e,p,a,b,s=fixture();history(e,p,b,1);e:CancelAll('seller');assert(not D.Signal(p,a,s))
 end)
 test('Countertrend entry is matched, stopped and capped by ordinary funding and inventory',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);local price=b.Last or b.Reference;D.Step(p,a)
  local pos=assert(e.Accounts[a.Id].Positions.BX);assert(pos.Direction==-1 and pos.Stop and pos.Quantity<=a.Size and pos.Quantity<=D.Capacity(p,a))
  assert(e.TotalVolume==pos.Quantity and e.Accounts[a.Id].NetCapitalAdjustments==0)
  assert((b.Last or b.Reference)==price-1);assert(not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Completed inventory mandate stops adding and has a finite holding deadline',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);D.Step(p,a)
  for _=1,12 do e:AdvanceClock(3);D.Step(p,a)end
  local pos=assert(e.Accounts[a.Id].Positions.BX);assert(s.Phase=='Holding' and pos.Quantity<=math.abs(s.Target))
  local volume=e.TotalVolume;D.Step(p,a);assert(volume==e.TotalVolume)
  e:AdvanceClock(100);D.Step(p,a);assert(e.TotalVolume>volume and s.ExitReason=='Time');e:Audit()
 end)
 test('No quotes yields no synthetic fills and no working IOC remains',function()
  local e,p,a,b,s=fixture('Value');e:AdvanceClock(100);local n=e.NextTrade;D.Step(p,a);assert(e.NextTrade==n and not e.Accounts[a.Id].Positions.BX and not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Portfolio demand uses private signed mandates and finite funded capacity',function()
  local e,p,a,b,s=fixture('Value');e:AdvanceClock(100);quote(e,b,1);quote(e,b,-1);D.Step(p,a)
  local pos=assert(e.Accounts[a.Id].Positions.BX);assert(pos.Quantity<=a.Size and math.abs(s.Target)<=D.Capacity(p,a)and s.Style=='Portfolio');e:Audit()
 end)
 test('Locks, liquidation, retirement, trigger ownership and zero buying power block entries',function()
  for _,condition in ipairs({'Locked','Liquidating','Retiring','Risk'})do local e,p,a,b,s=fixture();history(e,p,b,1)
   if condition=='Retiring'then a.Retiring=true elseif condition=='Risk'then e.Accounts[a.Id].Risk=0 else e.Accounts[a.Id][condition]=true end
   D.Step(p,a);assert(e.TotalVolume==0);e:Audit()
  end
  local e,p,a,b,s=fixture();history(e,p,b,1);D.Step(p,a);e.Accounts[a.Id].Positions.BX.Triggered='Stop loss';local n=e.NextOrder;D.Step(p,a);assert(e.NextOrder==n)
 end)
 test('Externally closed positions end intent and enter cooldown instead of immediate re-entry',function()
  local e,p,a,b,s=fixture();history(e,p,b,1);D.Step(p,a);local pos=e.Accounts[a.Id].Positions.BX
  assert(e:Submit(a.Id,{Contract='BX',Direction=-pos.Direction,Quantity=pos.Quantity,Type='Market',ReduceOnly=true}))
  local n=e.NextOrder;D.Step(p,a);assert(s.Phase=='Waiting' and s.ReadyAt>e.Time and e.NextOrder==n);e:Audit()
 end)
 test('Adoption preserves manual exits and explicitly removed manual stops',function()
  local e,p,a,b,s=fixture();quote(e,b,-1,5);assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Market',StopTicks=20}))
  local pos=e.Accounts[a.Id].Positions.BX;pos.ManualStop=true;pos.Stop=nil;pos.ManualTarget=true
  local ok,o=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=(b.Last+40)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  a.Diversity=nil;D.Step(p,a);assert(e.Orders[o.Id] and pos.Stop==nil and pos.ManualStop and pos.ManualTarget)
  a.Diversity.Hold=0;D.Step(p,a);assert(pos.Quantity==2 and e.Orders[o.Id]);e:Audit()
 end)
 test('Strategy adoption preserves restored economic state and refuses downgrade',function()
  local old=copy(C);old.BotDiversity=nil;local e=E.new(old,7919);local p=P.new(e)
  for _=1,40 do p:Step()end
  local saved=CP.Capture(e,p);local before=copy(saved);local re,rp=CP.Restore(saved,C)
  equal(saved,before);equal(saved.Engine,CP.Capture(re,rp).Engine);equal(saved.Population,CP.Capture(re,rp).Population)
  assert(not pcall(CP.Restore,CP.Capture(re,rp),old));re:Audit()
 end)
 test('Full population profiles, both subtypes and execution clocks serialize and continue exactly',function()
  local e=E.new(copy(C),7919);local p=P.new(e)
  for _=1,2000 do p:Step()end
  local saved=CP.Capture(e,p);local re,rp=CP.Restore(CP.Decode(CP.Encode(saved)),C);equal(saved,CP.Capture(re,rp))
  for _=1,160 do p:Step();rp:Step()end
  equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
 end)
 if C.BotDiversity.ReserveMode then
  test('Exactly one third of Reserve accounts receives diverse roles without any funding change',function()
   local e,p,a,b,s=fixture();local n,styles=0,{}
   for i=1,18 do local x=p:_agent('BX','Reserve',i);local ac=e.Accounts[x.Id];local before={Base=ac.Base,Balance=ac.Balance,Limit=ac.Limit,Risk=ac.Risk,Capital=ac.StartingCapital}
    if D.Enabled(p,x)then local q=D.Adopt(p,x);n+=1;styles[q.Style]=(styles[q.Style]or 0)+1 end
    equal(before,{Base=ac.Base,Balance=ac.Balance,Limit=ac.Limit,Risk=ac.Risk,Capital=ac.StartingCapital})
   end
   assert(n==6 and styles.Portfolio==3 and styles.Stretch==3);e:Audit()
  end)
  test('Reserve reassignment settles inherited inventory through capped matched exits before new risk',function()
   local e,p,a,b,s=fixture();a=p:_agent('BX','Reserve',3);local ac=e.Accounts[a.Id];local base=ac.Base
   quote(e,b,-1,100);assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=4,Type='Market',StopTicks=20}));quote(e,b,1,100)
   local volume=e.TotalVolume;D.Step(p,a);assert(not ac.Positions.BX and e.TotalVolume==volume+4 and ac.Base==base)
   local q=assert(a.Diversity);assert(q.Phase=='Waiting'and q.ReadyAt>e.Time);e:Audit()
   if p.Config.BotDiversity.ReserveMode=='Withdraw'then e:AdvanceClock(500);local n=e.NextOrder;D.Step(p,a);assert(e.NextOrder==n and not ac.Positions.BX)end
  end)
 end
 return out
end
return T
