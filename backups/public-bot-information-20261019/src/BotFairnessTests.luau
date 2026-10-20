local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local L=require(script.Parent.BotLiquidity)
local S=require(script.Parent.BotSignals)
local CP=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local function equal(a,b)
 assert(type(a)==type(b),'State type differs')
 if type(a)~='table'then assert(a==b,'State differs');return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra state key')end
end
local function fixture(kind)
 local c=clone(C);local e=E.new(c,1729)
 local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(1729),Agents={},Markets={},
  Regime={Volatility=1,Liquidity=1,Activity=1},NewsUntil=0},P)
 for _,key in ipairs(c.ContractOrder)do p.Markets[key]={Fair=e.Books[key].Reference}end
 local a=p:_agent('BX',kind or 'Liquidity',1);a.Size=2;a.Limit=8;e.Accounts[a.Id].Limit=8
 e:AddAccount('buyer',1e7,1000,1,false);e:AddAccount('seller',1e7,1000,1,false)
 return e,p,a,e.Books.BX
end
local function quote(e,side,tick,qty)
 return e:Submit(side==1 and 'buyer'or 'seller',{Contract='BX',Direction=side,Quantity=qty or 20,Type='Limit',Price=tick*e.Books.BX.Spec.Tick})
end
local function funding(e,a,equity)
 local ac=e.Accounts[a.Id];local delta=equity-e:Summary(ac).Equity
 ac.Base+=delta;ac.Balance+=delta;ac.NetCapitalAdjustments+=delta;ac.Revision+=1
end
function Tests.Run()
 local out={};local function test(name,fn)local ok,result=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})end
 test('Liquidity quotes passively, retains FIFO and cannot reverse through an exit',function()
  local e,p,a,b=fixture();local last=b.Reference
  quote(e,1,last-2);quote(e,-1,last+2);local volume=e.TotalVolume
  L.Step(p,a);assert(e.TotalVolume==volume,'Liquidity crossed the spread')
  local ac=e.Accounts[a.Id];local ids=clone(a.LiquidityQuotes)
  assert(ids['1']and ids['-1']);L.Step(p,a);equal(ids,a.LiquidityQuotes)
  e:CancelAll('buyer');assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=2,Type='Market'}))
  local pos=assert(ac.Positions.BX);assert(pos.Stop and pos.Quantity==2)
  quote(e,1,last-2);L.Step(p,a)
  local exit=e.Orders[a.LiquidityQuotes['-1']];assert(exit.ReduceOnly and exit.Remaining<=pos.Quantity)
  assert(e:Exposure(ac,'BX',1,0));e:Audit()
  return 'Entries do not pay the spread; existing quotes keep priority; inventory exits are reduce-only'
 end)
 test('Liquidity pauses before depletion and waits for real exit liquidity',function()
  local e,p,a,b=fixture();quote(e,-1,b.Reference+1,2)
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Market'}))
  local ac=e.Accounts[a.Id];e:CancelAll('seller');funding(e,a,1800)
  local trades=e.NextTrade;assert(p:_repairRisk(a));assert(e.NextTrade==trades and ac.Positions.BX.Quantity==2)
  assert(not next(ac.OpenOrders),'Entry survived drawdown pause')
  quote(e,1,b.Reference-1);assert(p:_repairRisk(a));assert(not ac.Positions.BX,'Risk exit did not use real liquidity')
  trades=e.NextTrade;assert(p:_repairRisk(a));L.Step(p,a);assert(e.NextTrade==trades and not next(ac.OpenOrders))
  local baseline=ac.Balance;funding(e,a,a.Budget);assert(not p:_repairRisk(a));assert(ac.Balance>baseline)
  e:Audit();return 'Underfunded bots reduce to flat and stay paused; only explicit restored equity permits new risk'
 end)
 test('Legacy liquidity inventory receives stops without widening existing protection',function()
  local e,p,a,b=fixture();quote(e,-1,b.Reference+1,2)
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  local ac=e.Accounts[a.Id];local pos=ac.Positions.BX;assert(not pos.Stop)
  L.Protect(p,a);assert(pos.Stop);local stop=pos.Stop
  pos.Stop=stop+b.Spec.Tick;L.Protect(p,a);assert(pos.Stop==stop+b.Spec.Tick)
  e:Audit();return 'Legacy positions gain bounded protection on a decision; tighter stops survive'
 end)
 test('Bot scale-ins and partial fills never loosen stops in either direction',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b=fixture();quote(e,-side,b.Reference+side,1)
   assert(e:Submit(a.Id,{Contract='BX',Direction=side,Quantity=1,Type='Market',StopTicks=8}))
   local pos=e.Accounts[a.Id].Positions.BX;local stop=pos.Stop
   quote(e,-side,b.Reference-side*3,1)
   assert(e:Submit(a.Id,{Contract='BX',Direction=side,Quantity=1,Type='Market',StopTicks=24}))
   assert(pos.Quantity==2 and pos.Stop==stop,'Scale-in widened stop');e:Audit()
  end
  return 'Long and short averaging-down preserves the original stop'
 end)
 test('Makers withdraw stale value risk before minimum rest and never take liquidity',function()
  local e,p,a,b=fixture('Maker');p:_maker(a)
  local old=clone(a.Quotes);local volume=e.TotalVolume
  quote(e,1,b.Reference-10);quote(e,-1,b.Reference+10)
  p.Markets.BX.Fair=b.Reference+20;e:AdvanceClock(.25);p:_maker(a)
  for slot,id in pairs(old)do if slot:sub(1,2)=='-1'then assert(not e.Orders[id],'Stale ask survived value shock')end end
  assert(e.TotalVolume==volume,'Maker crossed the spread on repricing');e:Audit()
  return 'Materially stale quotes cancel immediately; replacements remain passive'
 end)
 test('Public time-weighted signal cannot see hidden fair value',function()
  local e,p,a,b=fixture();e.Time=60;b.Last=b.Reference
  local m=p.Markets.BX;m.SignalHistory={{Time=0,Price=b.Last+8},{Time=30,Price=b.Last+4},{Time=57,Price=b.Last-2},{Time=60,Price=b.Last}}
  local w=S.Window(p,'BX',30,3);assert(math.abs(w.Mean-(b.Last+3.4))<1e-8)
  m.Fair=b.Last+10000;local first=S.Reversal(p,'BX',w,2,2,1)
  m.Fair=b.Last-10000;assert(first==1 and S.Reversal(p,'BX',w,2,2,1)==first)
  m.SignalHistory={{Time=0,Price=b.Last},{Time=60,Price=b.Last}};w=S.Window(p,'BX',30,3)
  assert(not S.Reversal(p,'BX',w,2,2,1),'Flat public tape fabricated a reversal')
  return 'Duration weighting is exact; hidden generator changes cannot change reversal decisions'
 end)
 test('V19 upgrade preserves economic state and V20 resumes deterministically',function()
  local old=clone(C);old.BotSignals.Version=1;old.BotLiquidity=nil;old.MakerQuotePolicyVersion=4
  local e=E.new(old,5501);local p=P.new(e);for _=1,120 do p:Step()end
  local snapshot=CP.Capture(e,p);snapshot.Version=19;local untouched=clone(snapshot)
  local re,rp=CP.Restore(snapshot,C);local after=CP.Capture(re,rp)
  equal(snapshot,untouched);equal(snapshot.Engine,after.Engine);equal(snapshot.Population,after.Population)
  assert(re.Config.BotSignals.Version==2 and re.Config.BotLiquidity.Version==1 and after.Version==20)
  for _=1,400 do rp:Step()end
  local saved=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C)
  equal(saved,CP.Capture(rr,pr));for _=1,400 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local newer=clone(saved);newer.Config.BotLiquidity.Version=2;assert(not pcall(CP.Restore,newer,C))
  return 'No funding or trades at migration; exact replay retains quotes, stops, signal history and RNG'
 end)
 return out
end
return Tests
