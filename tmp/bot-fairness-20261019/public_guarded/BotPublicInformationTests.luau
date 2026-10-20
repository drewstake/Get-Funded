local C=require("./MarketConfig")
local E=require("./MarketEngine")
local P=require("./Participants")
local S=require("./BotSignals")
local L=require("./BotLiquidity")
local CP=require("./WorldCheckpoint")
local Tests={}
local kinds={'Liquidity','Momentum','Value','Reversion','Protective','Scalper','Whale'}
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local function equal(a,b)
 assert(type(a)==type(b),'State type differs')
 if type(a)~='table'then assert(a==b,'State differs: '..tostring(a)..' vs '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra state key '..tostring(k))end
end
local function fixture(kind,hidden)
 local e=E.new(clone(C),8129);local b=e.Books.BX
 local p=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(8129),Agents={},Markets={},
  Regime={Volatility=1,Liquidity=1,Activity=1},NewsUntil=0},P)
 for _,key in ipairs(e.Config.ContractOrder)do p.Markets[key]={Fair=e.Books[key].Reference+hidden,Anchor=hidden,Impulse=hidden}end
 b.Last=b.Reference;b.Recent={b.Last-10,b.Last-5,b.Last};b.Volatility=.2
 e:AddAccount('bidder',1e7,1000,1,false);e:AddAccount('asker',1e7,1000,1,false)
 e:Submit('bidder',{Contract='BX',Direction=1,Quantity=20,Type='Limit',Price=(b.Last-1)*b.Spec.Tick})
 e:Submit('asker',{Contract='BX',Direction=-1,Quantity=20,Type='Limit',Price=(b.Last+1)*b.Spec.Tick})
 local a=p:_agent('BX',kind,1);a.Size=1;a.Limit=8;e.Accounts[a.Id].Limit=8
 e.Time=60;a.NextObservation=0;a.ObservedAt=0
 p.Markets.BX.SignalHistory={{Time=0,Price=b.Last-5},{Time=30,Price=b.Last-3},{Time=57,Price=b.Last-1},{Time=60,Price=b.Last}}
 return e,p,a,b
end
function Tests.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('Every trading profile and decision is independent of hidden value and future news',function()
  for _,kind in ipairs(kinds)do
   local e,p,a=fixture(kind,10000);local other,q,z=fixture(kind,-10000)
   equal(a,z);p.NextNews=61;q.NextNews=10000
   for iteration=1,12 do
    p:_observe(a);q:_observe(z)
    if kind=='Liquidity'then L.Step(p,a);L.Step(q,z)
    elseif kind=='Scalper'then p:_scalper(a);q:_scalper(z)
    else p:_trader(a);q:_trader(z)end
    equal(a,z);equal(e.Accounts,other.Accounts);equal(e.Orders,other.Orders)
    assert(p.Random.State==q.Random.State,kind..' consumed hidden-dependent random draws')
    e:AdvanceClock(.25);other:AdvanceClock(.25)
   end
   e:Audit();other:Audit()
  end
  return 'Seven trader types initialize, observe and submit identically with opposite hidden values and future schedules'
 end)
 test('Trader paths cannot read private market fields even with a legacy profile',function()
  for _,kind in ipairs(kinds)do
   local e,p,a,b=fixture(kind,0);a.InformationVersion=nil;a.Belief=1e9;a.Parent=100
   local history=p.Markets.BX.SignalHistory
   p.Markets.BX=setmetatable({SignalHistory=history},{__index=function(_,key)
    if key=='Fair'or key=='Anchor'or key=='Impulse'then error('Private market read: '..kind..' '..key)end
   end})
   p:_observe(a)
   if kind=='Liquidity'then L.Step(p,a)elseif kind=='Scalper'then p:_scalper(a)else p:_trader(a)end
   assert(a.InformationVersion==S.InformationVersion and a.Parent<100)
  end
  return 'Private generator fields are guarded during adoption and every strategy path'
 end)
 test('Public quote matches the player snapshot and falls back safely without a two-sided book',function()
  local e,p,a,b=fixture('Value',0)
  e:AddAccount('player',10000,100,.8,true)
  local visible=e:Snapshot('player','BX','1m',true).Quotes.BX;local quote=S.Quote(p,'BX')
  assert(quote.Bid*b.Spec.Tick==visible.Bid and quote.Ask*b.Spec.Tick==visible.Ask)
  assert(quote.Value==(visible.Bid+visible.Ask)/2/b.Spec.Tick)
  e:CancelAll('asker');assert(S.Quote(p,'BX').Value==b.Last)
  e:CancelAll('bidder');assert(S.Quote(p,'BX').Value==b.Last)
  return 'The strategy and client share executable bid/ask filtering; empty sides use last trade'
 end)
 test('Adoption cancels private entries and parent intent while preserving inventory and exits',function()
  local e,p,a,b=fixture('Value',10000)
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market',StopTicks=8}))
  local ac=e.Accounts[a.Id];local pos=clone(ac.Positions.BX)
  local ok,entry=e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=(b.Last-10)*b.Spec.Tick});assert(ok)
  local yes,exit=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Last+10)*b.Spec.Tick,ReduceOnly=true});assert(yes)
  a.InformationVersion=nil;a.Belief=1e9;a.Parent=50
  local balance,base,volume,draw=ac.Balance,ac.Base,e.TotalVolume,p.Random.State
  p:_publicInformation(a)
  assert(not e.Orders[entry.Id]and e.Orders[exit.Id]and a.Parent==0)
  assert(a.Belief==S.Quote(p,'BX').Value)
  equal(pos,ac.Positions.BX);assert(ac.Balance==balance and ac.Base==base and e.TotalVolume==volume and p.Random.State==draw)
  local agent=clone(a);local orders=clone(e.Orders);p:_publicInformation(a);equal(agent,a);equal(orders,e.Orders);e:Audit()
  return 'Idempotent adoption retains cash, positions, stops and reduce-only exits without fills or random draws'
 end)
 test('Makers and reserves retain private valuation and are excluded from adoption',function()
  for _,kind in ipairs({'Maker','Reserve'})do
   local e,p,a,b=fixture(kind,10);local other,q,z=fixture(kind,-10)
   assert(a.Belief~=z.Belief)
   local before=clone(a);a.InformationVersion=nil;before.InformationVersion=nil;p:_publicInformation(a);equal(before,a)
   if kind=='Maker'then p:_maker(a);q:_maker(z)else p:_reserve(a);q:_reserve(z)end
   local different=false
   for id,o in pairs(e.Orders)do local rhs=other.Orders[id];if not rhs or o.Price~=rhs.Price then different=true end end
   assert(different,kind..' lost its internal pricing guidance');e:Audit();other:Audit()
  end
  return 'Both infrastructure groups continue repricing from internal fair value'
 end)
 test('V20 adoption preserves economics and V21 checkpoints replay exactly',function()
  local e=E.new(clone(C),9401);local p=P.new(e);for _=1,100 do p:Step()end
  local old=CP.Capture(e,p);old.Version=20;old.Config.BotInformationVersion=nil
  for _,a in ipairs(old.Population.Agents)do a.InformationVersion=nil;a.Belief=1e9 end
  local untouched=clone(old);local re,rp=CP.Restore(old,C)
  equal(old,untouched);equal(old.Engine,CP.Capture(re,rp).Engine);equal(old.Population,CP.Capture(re,rp).Population)
  rp:Step();for _,a in ipairs(rp.Agents)do if a.Kind~='Maker'and a.Kind~='Reserve'then
   assert(a.InformationVersion==S.InformationVersion and a.Belief<1e8)
  end end
  local saved=CP.Capture(re,rp);assert(saved.Version==21 and saved.Config.BotInformationVersion==1)
  local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C);equal(saved,CP.Capture(rr,pr))
  for _=1,240 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local newer=clone(saved);newer.Config.BotInformationVersion=2;assert(not pcall(CP.Restore,newer,C))
  return 'Restore itself preserves state; first-step adoption is saved and exact continuation survives encode/decode'
 end)
 return out
end
return Tests
