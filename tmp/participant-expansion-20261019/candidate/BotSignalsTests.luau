local C=require("./MarketConfig")
local E=require("./MarketEngine")
local P=require("./Participants")
local S=require("./BotSignals")
local CP=require("./WorldCheckpoint")
local Tests={}
local function clone(v)if type(v)~='table'then return v end;local r={}for k,x in pairs(v)do r[k]=clone(x)end;return r end
local function equal(a,b)
 assert(type(a)==type(b),'State type differs')
 if type(a)~='table'then assert(a==b,'State differs');return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Unexpected state key')end
end
local function fixture()
 local e=E.new(clone(C),73521);local p=P.new(e)
 for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
 local a;for _,agent in ipairs(p.Agents)do if agent.Kind=='Reversion'and agent.Key=='BX'then a=agent;break end end
 e.Time=60;a.Next=0;a.Bias=100;a.Size=5;a.Aggression=1;a.EntryThreshold=.5
 p.Random={Next=function()return .9 end,Noise=function()return 0 end,Range=function(_,lo,hi)return(lo+hi)/2 end,Int=function(_,lo,hi)return hi end}
 local b=e.Books.BX;local last=b.Last
 e:AddAccount('signal-buyer',1e7,1000,1,false);e:AddAccount('signal-seller',1e7,1000,1,false)
 assert(e:Submit('signal-buyer',{Contract='BX',Direction=1,Quantity=20,Type='Limit',Price=(last-1)*b.Spec.Tick}))
 assert(e:Submit('signal-seller',{Contract='BX',Direction=-1,Quantity=20,Type='Limit',Price=(last+1)*b.Spec.Tick}))
 local requests={};e.Submit=function(_,id,request)table.insert(requests,request);return true,{Filled=0,Remaining=request.Quantity}end
 return e,p,a,b,requests
end
function Tests.Run()
 local report={};local function test(name,fn)local ok,r=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('Protective public midpoint tracks up and down without stale-price bias',function()
  local e,p,a,b,requests=fixture();a.Kind='Protective';a.Bias=0;a.Belief=b.Last-1000
  p.Markets.BX.Fair=b.Last+10000;p:_trader(a);assert(a.Belief==b.Last and #requests==0)
  a.Belief=b.Last+1000;p:_trader(a);assert(a.Belief==b.Last and #requests==0)
  return 'A stale belief or hidden fair value cannot manufacture an entry when price equals the public midpoint'
 end)
 test('Reversion needs observed-price distance and an actual turn in both directions',function()
  local e,p,a,b,requests=fixture();local last=b.Last;local market=p.Markets.BX
  market.Fair=last+4
  market.SignalHistory={{Time=0,Price=last+5},{Time=30,Price=last+3},{Time=57,Price=last+1},{Time=60,Price=last}}
  p:_trader(a);assert(#requests==0,'Bought a continuing fall')
  market.SignalHistory[3].Price=last-1
  p:_trader(a);assert(#requests==1 and requests[1].Direction==1)
  market.Fair=last-10000;p:_trader(a);assert(#requests==2,'Private fair value changed the public signal')
  a.Bias=-100;market.Fair=last-4
  market.SignalHistory={{Time=0,Price=last-5},{Time=30,Price=last-3},{Time=57,Price=last-1},{Time=60,Price=last}}
  p:_trader(a);assert(#requests==2,'Sold a continuing rise')
  market.SignalHistory[3].Price=last+1
  p:_trader(a);assert(#requests==3 and requests[3].Direction==-1)
  return 'Continuations blocked; observed-price turns admitted independently of private fair value'
 end)
 test('Unconfirmed Reversion reductions cannot reverse or exceed the remaining position',function()
  local e,p,a,b,requests=fixture();a.Bias=-100
  e.Accounts[a.Id].Positions.BX={Id=1,Quantity=1,Direction=1,Entry=b.Last*b.Spec.Tick}
  p.Markets.BX.SignalHistory=nil;p:_trader(a)
  assert(#requests==1 and requests[1].ReduceOnly and requests[1].Quantity==1 and requests[1].Direction==-1)
  return 'Warmup and confirmation do not block reductions; five requested contracts are capped to one'
 end)
 test('Time windows are independent of trade count, bounded, and require fresh history',function()
  local e,p,a,b=fixture();local market=p.Markets.BX;market.SignalHistory=nil
  for i=0,200 do e.Time=i;b.Last=b.Reference+i;S.Sample(p,'BX');S.Sample(p,'BX')end
  assert(#market.SignalHistory<=62,'History grew without a bound')
  local window=assert(S.Window(p,'BX',20,3));assert(window.Move==20 and window.RecentMove==3)
  b.Recent=table.create(64,b.Last);local same=S.Window(p,'BX',20,3);equal(window,same)
  e.Time+=3;assert(not S.Window(p,'BX',20,3),'Stale history accepted')
  market.SignalHistory=nil;S.Sample(p,'BX');assert(not S.Window(p,'BX',20,3),'Warmup skipped')
  return 'One sample per second; at most 62 samples; execution bursts cannot shorten the horizon'
 end)
 test('Scalpers admit affordable small moves but reject flat prices and poor targets',function()
  local e,p,_,b,requests=fixture();local a
  for _,agent in ipairs(p.Agents)do if agent.Kind=='Scalper'and agent.Key=='BX'then a=agent;break end end
  a.Style='Momentum';a.Lookback=20;a.EntryThreshold=.5;a.Target=6;a.ReadyAt=0
  local last=b.Last;local market=p.Markets.BX
  market.SignalHistory={{Time=0,Price=last-2},{Time=40,Price=last-2},{Time=57,Price=last-1},{Time=60,Price=last}}
  b.Recent=table.create(64,last);b.Volatility=.2;p:_scalper(a)
  assert(#requests==1,'Two-tick move blocked by spread/slippage sum')
  a.ReadyAt=0;for _,point in ipairs(market.SignalHistory)do point.Price=last end
  p:_scalper(a);assert(#requests==1,'Flat tape admitted')
  market.SignalHistory[1].Price=last-2;market.SignalHistory[2].Price=last-2;market.SignalHistory[3].Price=last-1
  a.Target=3;p:_scalper(a);assert(#requests==1,'Target cannot cover spread plus slippage buffer')
  return 'A genuine two-tick move can trade; flat tape and inadequate target room cannot'
 end)
 test('V17 strategy migration preserves ledgers and orders; current format resumes exactly',function()
  local old=clone(C);old.BotSignals=nil
  local e=E.new(old,5501);local p=P.new(e);for _=1,100 do p:Step()end
  local before=CP.Capture(e,p);before.Version=17;local untouched=clone(before)
  local re,rp=CP.Restore(before,C);local after=CP.Capture(re,rp)
  equal(before,untouched);equal(before.Engine,after.Engine);equal(before.Population,after.Population)
  assert(re.Config.BotSignals.Version==C.BotSignals.Version and after.Version==CP.Version)
  for _=1,160 do rp:Step()end
  local saved=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C);equal(saved,CP.Capture(rr,pr))
  for _=1,160 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local newer=clone(saved);newer.Config.BotSignals.Version=C.BotSignals.Version+1;assert(not pcall(CP.Restore,newer,C))
  newer=clone(saved);newer.Version=CP.Version+1;assert(not pcall(CP.Restore,newer,C))
  return 'No deposits, withdrawals, trades or account/order changes on upgrade; exact resumed signals and RNG'
 end)
 return report
end
return Tests
