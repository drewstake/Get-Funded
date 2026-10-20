local C=require("./MarketConfig")
local E=require("./MarketEngine")
local P=require("./Participants")
local F=require("./OrderFlowMarket")
local X=require("./PlayerExecution")
local CP=require("./WorldCheckpoint")
local Tests={}
local function clone(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=clone(x)end;return t end
local function equal(a,b)
 assert(type(a)==type(b),'Different types')
 if type(a)~='table'then assert(a==b,'Different values '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra field '..tostring(k))end
end
local function fixture()
 local c=clone(C);c.OrderFlowMarket={Version=1,SampleSeconds=1,WindowSeconds=6,MinTrades=3,MinMoveTicks=4,MoveFraction=0,CooldownSeconds=12,DisplaySeconds=6}
 local e=E.new(c,10191)
 e:AddAccount('supply',1e8,10000,1,false);e:AddAccount('demand',1e8,10000,1,false)
 return e,e.Books.BX
end
local function printTrade(e,key,time,offset,side)
 local b=e.Books[key];e.Time=time;e.Step=math.floor(time/e.Config.StepSeconds)
 e:CancelAll('supply')
 local price=(b.Reference+offset)*b.Spec.Tick;side=side or 1
 local ok=e:Submit('supply',{Contract=key,Direction=-side,Quantity=1,Type='Limit',Price=price});assert(ok)
 local filled,r=e:Submit('demand',{Contract=key,Direction=side,Quantity=1,Type='Market'});assert(filled and r.Filled==1)
end
function Tests.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('No executed orders means no price change, drift, shock or announcement',function()
  local c=clone(C);c.BotPopulation=nil;c.MakersPerInstrument=0;c.ParticipantsPerInstrument=0;c.ScalpersPerInstrument=0;c.WhaleFrequency=0;c.Reserve=nil;c.NewsFrequency=99999
  local e=E.new(c,551);local p=P.new(e);p.OrderFlowVersion=nil;p.NextNews=0;p.NextBeliefs=0;p.Direction=1;p.News='old shock';p.NewsUntil=1e9
  for _,m in pairs(p.Markets)do m.Fair=1e8;m.Anchor=1e8;m.Impulse=1e8 end
  local reference={};for key,b in pairs(e.Books)do reference[key]=b.Reference end
  for _=1,2400 do p:Step()end
  assert(e.TotalVolume==0 and e.NextTrade==0 and p.News==nil and p.NextNews==nil and p.Direction==nil)
  for key,b in pairs(e.Books)do assert(b.Last==nil and F.Reference(b)==reference[key]and not F.Event(e,key,1));assert(p.Markets[key].Fair==nil)end
  return 'Ten simulated minutes, random activity regimes and hostile legacy news fields cannot move price'
 end)
 test('Buy and sell executions drive price and the shared public collar',function()
  for _,side in ipairs({1,-1})do
   local e,b=fixture();b.FairReference=b.Reference+side*10000
   assert(X.Allows(e,b,b.Reference,side))
   assert(not X.Allows(e,b,b.Reference+side*21,side),'Hidden fair value moved the execution guard')
   for i=0,8 do printTrade(e,'BX',i,side*i,side)end
   assert(b.Last==b.Reference+side*8 and b.FairReference==b.Last and e.NextTrade==9)
   e:Audit()
  end
  return 'Both directions settle against real counterparties and only executions advance the reference'
 end)
 test('Production public collars preserve player targets and stops in both directions',function()
  for _,side in ipairs({1,-1})do for _,target in ipairs({true,false})do
   local e,b=fixture();printTrade(e,'BX',0,0)
   e:AddAccount('player',100000,100,.8,true)
   assert(e:Submit('supply',{Contract='BX',Direction=-side,Quantity=100,Type='Limit',Price=b.Last*b.Spec.Tick}))
   local ok,entry=e:Submit('player',{Contract='BX',Direction=side,Quantity=1,Type='Market',StopTicks=4,TargetTicks=4})
   assert(ok and entry.Filled==1,'Production entry allowance blocked a funded one-contract order')
   for i=1,4 do printTrade(e,'BX',i,side*(target and i or -i),side*(target and 1 or -1))end
   if not target then
    e:CancelAll('supply')
    assert(e:Submit('supply',{Contract='BX',Direction=side,Quantity=100,Type='Limit',Price=b.Last*b.Spec.Tick}))
    e:ProcessStops()
   end
   assert(not e.Accounts.player.Positions.BX,'Actual execution did not close the protected position')
   assert((e.Accounts.player.Realized>0)==target);e:Audit()
  end end
  return 'Current production policy supports funded entries, target fills and stop exits through real liquidity'
 end)
 test('Alerts require a full window, sufficient trades and the configured price move',function()
  local e,b=fixture();printTrade(e,'BX',0,0);printTrade(e,'BX',2,2);printTrade(e,'BX',4,4)
  assert(not F.Event(e,'BX',1),'Alert before warmup')
  printTrade(e,'BX',6,6);local event=assert(F.Event(e,'BX',1))
  assert(event.Contract=='BX'and event.Direction==1 and event.FromPrice==b.Reference*b.Spec.Tick and event.ToPrice==b.Last*b.Spec.Tick)
  assert(not F.Event(e,'BT',1),'BX movement leaked into BT banner')
  printTrade(e,'BX',7,7);assert(F.Event(e,'BX',1).Id==event.Id,'Cooldown ignored')
  e.Time=12;assert(not F.Event(e,'BX',1),'Expired event replayed')
  local flat=fixture();for i=0,12 do printTrade(flat,'BX',i,0)end;assert(not F.Event(flat,'BX',1),'Flat trading announced')
  local sparse=fixture();printTrade(sparse,'BX',0,0);printTrade(sparse,'BX',6,10);assert(not F.Event(sparse,'BX',1),'One print announced a surge')
  return 'Per-instrument factual alerts respect threshold, warmup, activity, cooldown and expiry'
 end)
 test('Selloff detection, repeated events and bounded history use no future/random state',function()
  local e,b=fixture()
  for i=0,30 do printTrade(e,'BX',i,-i,-1)end
  local event=assert(F.Event(e,'BX',4));assert(event.Direction==-1 and event.Id:sub(1,2)=='4:')
  assert(#b.Flow.History<=9 and b.Flow.Count==31)
  local original=event.Id;for i=31,42 do printTrade(e,'BX',i,-i,-1)end
  assert(F.Event(e,'BX',4).Id~=original)
  e:Audit();return 'Repeated genuine moves can alert after cooldown; storage remains bounded'
 end)
 test('V21 adoption removes old private intent without funding or fabricating trades',function()
  local e=E.new(clone(C),5219);local p=P.new(e);for _=1,40 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=21;saved.Config.OrderFlowMarket=nil;saved.Population.OrderFlowVersion=nil
  saved.Population.NextNews=0;saved.Population.News='Legacy bullish event';saved.Population.NewsUntil=1e9
  for _,m in pairs(saved.Population.Markets)do m.Fair=1e9;m.Anchor=1e9;m.Impulse=100 end
  local untouched=clone(saved);local re,rp=CP.Restore(saved,C);equal(saved,untouched)
  local before=CP.Capture(re,rp);rp:Prepare();local after=CP.Capture(re,rp)
  assert(re.TotalVolume==before.Engine.TotalVolume and re.NextTrade==before.Engine.NextTrade and rp.News==nil)
  for i,account in ipairs(after.Engine.Accounts)do local old=before.Engine.Accounts[i]
   assert(account.Balance==old.Balance and account.Base==old.Base and account.Realized==old.Realized);equal(account.Positions,old.Positions)
  end
  for _,o in ipairs(after.Engine.Orders)do local ac=re.Accounts[o.Owner];assert(ac.Player or o.ReduceOnly,'Legacy bot entry survived')end
  local adopted=CP.Capture(re,rp);rp:Prepare();equal(adopted,CP.Capture(re,rp))
  local rr,pr=CP.Restore(CP.Decode(CP.Encode(adopted)),C)
  for _=1,240 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local future=clone(adopted);future.Config.OrderFlowMarket.Version=2;assert(not pcall(CP.Restore,future,C))
  return 'Idempotent adoption preserves balances, P&L and positions; exact V22 continuation and downgrade refusal'
 end)
 test('Execution alert history and cooldown survive exact checkpoint continuation',function()
  local e=E.new(clone(C),881);local p=P.new(e)
  for _=1,160 do p:Step()end
  local snapshot=CP.Capture(e,p);local rr,pr=CP.Restore(CP.Decode(CP.Encode(snapshot)),C);equal(snapshot,CP.Capture(rr,pr))
  for _=1,240 do p:Step();pr:Step()end
  equal(CP.Capture(e,p),CP.Capture(rr,pr));assert(CP.Version==23)
  return 'Observed history, alert state, orders and RNG continue identically'
 end)
 return out
end
return Tests
