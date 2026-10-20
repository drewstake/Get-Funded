-- Edit-only install. No DataStore write, cash adjustment, play/stop, file save or publication.
assert(not game:GetService("RunService"):IsRunning(),"Install in Edit mode")
assert(game.PlaceId==137759823569682,"This release targets Get Funded!")
local Encoding=game:GetService("EncodingService")
local function hash(s)local b=Encoding:ComputeStringHash(s:gsub("\r\n","\n"),Enum.HashAlgorithm.Sha256);return(b:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end
local release={}
release[([====[!ServerScriptService.MarketReign.BotFairnessTests]====]):sub(2)]={Source=([====[!local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
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
  local pos=assert(ac.Positions.BX);assert(pos.Stop and pos.Quantity==1)
  quote(e,1,last-2);L.Step(p,a)
  local exit=e.Orders[a.LiquidityQuotes['-1']];assert(exit.ReduceOnly and exit.Remaining<=pos.Quantity)
  for id in pairs(ac.OpenOrders)do assert(e.Orders[id].ReduceOnly,'Liquidity added to an open position')end
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
 test('Paused liquidity preserves a triggered protective exit and its priority',function()
  local e,p,a,b=fixture();quote(e,-1,b.Reference+1,2)
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Market'}))
  local ac=e.Accounts[a.Id];local pos=ac.Positions.BX
  funding(e,a,1800);pos.Target=pos.Entry+20*b.Spec.Tick;pos.Triggered='Take profit'
  e:AdvanceClock(.25);local id=assert(pos.ExitOrder);local order=assert(e.Orders[id]);local priority=order.Priority
  assert(p:_repairRisk(a));assert(e.Orders[id]==order and order.Priority==priority and pos.ExitOrder==id)
  e:Audit();return 'Pausing cancels entry risk without cancelling or reprioritizing a pending protective exit'
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
 test('V19 upgrade preserves economic state and current format resumes deterministically',function()
  local old=clone(C);old.BotSignals.Version=1;old.BotLiquidity=nil;old.MakerQuotePolicyVersion=4
  local e=E.new(old,5501);local p=P.new(e);for _=1,120 do p:Step()end
  local snapshot=CP.Capture(e,p);snapshot.Version=19;local untouched=clone(snapshot)
  local re,rp=CP.Restore(snapshot,C);local after=CP.Capture(re,rp)
  equal(snapshot,untouched);equal(snapshot.Engine,after.Engine);equal(snapshot.Population,after.Population)
  assert(re.Config.BotSignals.Version==2 and re.Config.BotLiquidity.Version==C.BotLiquidity.Version and after.Version==CP.Version)
  for _=1,400 do rp:Step()end
  local saved=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C)
  equal(saved,CP.Capture(rr,pr));for _=1,400 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local newer=clone(saved);newer.Config.BotLiquidity.Version=C.BotLiquidity.Version+1;assert(not pcall(CP.Restore,newer,C))
  return 'No funding or trades at migration; exact replay retains quotes, stops, signal history and RNG'
 end)
 test('Earlier liquidity policies acquire new sizing settings without funding; version bump leaves fresh trading identical',function()
  local old=clone(C);old.BotLiquidity.Version=1
  local e=E.new(old,31415);local p=P.new(e)
  local current=E.new(clone(C),31415);local population=P.new(current)
  for _=1,160 do p:Step();population:Step()end
  equal(CP.Capture(e,p).Engine,CP.Capture(current,population).Engine)
  assert(e.TradeHash==current.TradeHash and p.Random.State==population.Random.State)
  local snapshot=CP.Capture(e,p);snapshot.Version=20
  snapshot.Config.BotLiquidity.EntryContracts=nil;snapshot.Config.BotLiquidity.MinHalfSpreadTicks=nil;snapshot.Config.BotLiquidity.VolatilitySpread=nil
  local re,rp=CP.Restore(snapshot,C);equal(snapshot.Engine,CP.Capture(re,rp).Engine)
  assert(re.Config.BotLiquidity.Version==2 and re.Config.BotLiquidity.EntryContracts==1)
  for _=1,160 do rp:Step()end;re:Audit()
  return 'V1 acquires V2 fields with no balance change; version-only changes produce identical trades and RNG'
 end)
 return out
end
return Tests
]====]):sub(2),Hash=([====[!9c698d602c8b5ac793ab1b1bc8e75260aa1d557aec4a8e666ee3c7b0dfafc9fa]====]):sub(2),ExpectedHash=nil}
release[([====[!ServerScriptService.MarketReign.BotLiquidity]====]):sub(2)]={Source=([====[!-- Passive, finite liquidity. Risk is funded by existing equity, never a cash top-up.
local Liquidity={}
local Signals=require(script.Parent.BotSignals)
function Liquidity.Protect(population,a)
 local e=population.Engine;local account=e.Accounts[a.Id];local p=account.Positions[a.Key]
 if not p or p.Triggered then return false end
 local c=population.Config.BotLiquidity;local b=e.Books[a.Key]
 local ticks=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))
 local stop=math.max(1,math.round(p.Entry/b.Spec.Tick)-p.Direction*ticks)*b.Spec.Tick
 -- Adopt legacy inventory on its next decision; never move an existing stop farther away.
 if not p.Stop or (stop-p.Stop)*p.Direction>0 then p.Stop=stop;account.Revision+=1 end
 return ((b.Last or b.Reference)*b.Spec.Tick-p.Stop)*p.Direction<=0
end
function Liquidity.Limit(population,a)
 local c=population.Config.BotLiquidity
 local e=population.Engine;local account=e.Accounts[a.Id];local b=e.Books[a.Key]
 local equity=e:Summary(account).Equity
 if equity<=a.Budget*(1-c.MaxDrawdown)then return 0 end
 local stop=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))
 return math.max(0,math.min(a.Limit,account.Limit,c.MaxInventory,
  math.floor(equity*account.Risk*c.MarginFraction/b.Spec.Margin),
  math.floor(equity*c.PositionRiskFraction/(stop*b.Spec.Tick*b.Spec.Multiplier))))
end
function Liquidity.Step(population,a)
 population:_publicInformation(a)
 local e=population.Engine;local c=population.Config.BotLiquidity;local b=e.Books[a.Key]
 local account=e.Accounts[a.Id];local p=account.Positions[a.Key]
 if account.Locked or account.Liquidating or b.Spec.CloseOnly or p and p.Triggered then return end
 if a.LiquidityPolicy~=c.Version then
  -- Old random entry orders must not survive adoption. Preserve reduce-only exits.
  local ids={};for id in pairs(account.OpenOrders)do
   if not e.Orders[id].ReduceOnly then table.insert(ids,id)end
  end
  table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
  a.LiquidityQuotes={};a.LiquidityPolicy=c.Version
 end
 local limit=Liquidity.Limit(population,a);if limit<1 then return end
 e:_pruneBook(b)
 local quote=Signals.Quote(population,a.Key);local bid,ask=quote.Bid,quote.Ask
 if not bid or not ask then
  for _,id in pairs(a.LiquidityQuotes)do if e.Orders[id]then e:Cancel(a.Id,id)end end
  a.LiquidityQuotes={};return
 end
 local inventory=p and p.Quantity*p.Direction or 0
 local half=math.max(c.MinHalfSpreadTicks,math.ceil(b.Volatility*c.VolatilitySpread))
 -- Ordinary liquidity traders use the same visible midpoint as players.
 local center=quote.Value-inventory/limit*half
 for _,side in ipairs({1,-1})do
  local slot=tostring(side)
  local tick=side==1 and math.min(bid,math.floor(center-half))or math.max(ask,math.ceil(center+half))
  tick=math.max(1,tick)
  local reducing=p~=nil and side==-p.Direction
  -- A small uninformed supplier must not pyramid into adverse fills. Work its exit first.
  local size=reducing and math.min(a.Size,p.Quantity)or(p and 0 or math.min(c.EntryContracts,a.Size,limit))
  local held=a.LiquidityQuotes[slot]and e.Orders[a.LiquidityQuotes[slot]]
  if held and (size==0 or held.ReduceOnly~=reducing or held.Remaining>size or math.abs(held.Price-tick)>=c.RepriceTicks)then
   e:Cancel(a.Id,held.Id);held=nil
  end
  if not held and size>0 then
   if not reducing then size=population:_fit(a,side,size)end
   if size>0 then
    local request={Contract=a.Key,Direction=side,Quantity=size,Type='Limit',Price=tick*b.Spec.Tick,
     ReduceOnly=reducing,Expires=e.Time+c.QuoteSeconds}
    if not reducing then request.StopTicks=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))end
    local ok,result=e:Submit(a.Id,request)
    if ok and result.Remaining>0 then a.LiquidityQuotes[slot]=result.Id else a.LiquidityQuotes[slot]=nil end
   end
  end
 end
end
return Liquidity
]====]):sub(2),Hash=([====[!d0bb95793515cffd2f649e07be1ded12f03ed348ee6f3ca9a6fee9f6a2d702a1]====]):sub(2),ExpectedHash=nil}
release[([====[!ServerScriptService.MarketReign.BotPopulationTests]====]):sub(2)]={Source=([====[!local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Policy=require(script.Parent.BotPopulation)
local Tests={}
local function clone(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' value');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function oldConfig()
 local c=clone(C);c.BotPopulation=nil;c.MakersPerInstrument=10;c.ParticipantsPerInstrument=36;c.WhalesPerInstrument=3;c.ScalpersPerInstrument=18
 c.Reserve.Capital=100000000000;c.Reserve.InventoryLimit=50000000
 return c
end
function Tests.Run()
 local report={};local function test(name,fn)local ok,r=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('Exact capital, counts, styles, diversity and reproducibility',function()
  for _,seed in ipairs({5501,4407,73521})do
   local e=E.new(clone(C),seed);local p=P.new(e);Policy.Validate(p)
   local total=0;local nextTimes={};local observations={}
   for _,key in ipairs(C.ContractOrder)do
    local sum,n,styles=0,0,{Momentum=0,Reversion=0}
    for _,a in ipairs(p.Agents)do if a.Key==key then
     local ac=e.Accounts[a.Id];n+=1;sum+=ac.StartingCapital
     assert(ac.StartingCapital==C.BotPopulation.Capital[a.Kind]and ac.Base==ac.StartingCapital and ac.NetCapitalAdjustments==0)
     assert(a.Limit*e.Books[key].Spec.Margin<=ac.Base*ac.Risk*C.BotPopulation.MarginFraction+.01)
     nextTimes[a.Next]=true;observations[a.ObservationSeconds]=true
     if a.Kind=='Scalper'then styles[a.Style]+=1 end
     if a.Kind=='Reserve'then assert(a.Limit==2000 and a.Size==C.Reserve.QuoteSizes[key])end
    end end
    assert(n==130 and sum==68000000 and styles.Momentum==12 and styles.Reversion==12);total+=sum
   end
   assert(total==204000000 and #p.Agents==390)
   local n=0;for _ in pairs(nextTimes)do n+=1 end;assert(n>380)
   n=0;for _ in pairs(observations)do n+=1 end;assert(n>380)
   local e2=E.new(clone(C),seed);local p2=P.new(e2)
   equal(CP.Capture(e,p),CP.Capture(e2,p2));e:Audit()
  end
  return 'Three seeds: 390 bots, $204M, 12/12 scalpers per market; independent reproducible schedules'
 end)
 test('Sizing reserves pending orders and reduces unaffordable requests',function()
  local e=E.new(clone(C),1);local p=P.new(e);local a
  for _,x in ipairs(p.Agents)do if x.Kind=='Liquidity'and x.Key=='BX'and not next(e.Accounts[x.Id].Positions)then a=x;break end end
  e:CancelAll(a.Id);local ac=e.Accounts[a.Id];assert(not next(ac.Positions))
  ac.Base=2000;ac.Balance=2000;ac.Realized=0;ac.Risk=.8;ac.Limit=20
  assert(p:_fit(a,1,5)==2)
  local price=(e.Books.BX.Last-100)*e.Books.BX.Spec.Tick
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=price}))
  assert(p:_fit(a,1,5)==1 and p:_fit(a,-1,5)==2)
  ac.Risk=0;assert(p:_fit(a,1,5)==0)
  e:CancelAll(a.Id);e:Audit();return 'Downsizes to 2 then 1 with a pending entry; zero capacity sends no order'
 end)
 test('Value observations follow elapsed time with noisy independent estimates',function()
  local e=E.new(clone(C),2);local p=P.new(e);local a
  for _,x in ipairs(p.Agents)do if x.Kind=='Value'then a=x;break end end
  a.Belief=100;a.ObservationNoise=0;a.ValueOffset=0;a.BeliefHalfLife=10;a.ObservedAt=0;a.NextObservation=0
  for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
  e.Books[a.Key].Last=200;p.Markets[a.Key].Fair=9999;e.Time=10;p:_observe(a)
  assert(math.abs(a.Belief-150)<1e-9 and a.NextObservation>10)
  p:_observe(a);assert(a.Belief==150)
  return 'Half-life updates on observation clocks; no future data or forced prices'
 end)
 test('Scalpers reject flat/noisy signals but can size down a qualified entry',function()
  local e=E.new(clone(C),3);local p=P.new(e);for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
  local a;for _,x in ipairs(p.Agents)do if x.Kind=='Scalper'and x.Key=='BX'then a=x;break end end
  local b=e.Books.BX;local last=b.Last;local ac=e.Accounts[a.Id]
  e:AddAccount('buyer',1000000,1000,1,false);e:AddAccount('seller',1000000,1000,1,false)
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=5,Type='Limit',Price=(last-1)*b.Spec.Tick}))
  assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=5,Type='Limit',Price=(last+1)*b.Spec.Tick}))
  b.Recent={last,last};a.Bias=100;local n=e.NextOrder;p:_scalper(a);assert(e.NextOrder==n)
  b.Recent={last-30,last};a.Style='Momentum';a.Size=2;a.Limit=2;ac.Limit=2;ac.Base=1000;ac.Balance=1000;ac.Risk=.8
  e.Time=60;p.Markets.BX.SignalHistory={{Time=0,Price=last-30},{Time=57,Price=last-1},{Time=60,Price=last}}
  p.Config.Scalper.AggressiveChance=1;p:_scalper(a)
  assert(ac.Positions.BX and ac.Positions.BX.Quantity==1)
  e:Audit();return 'Flat tape cannot trigger an entry; qualified two-contract request fits one contract'
 end)
 test('Migration retains players, positions, exits and P&L; records funding; resumes exactly',function()
  local c=oldConfig();local e=E.new(c,5501);local p=P.new(e)
  for _=1,100 do p:Step()end
  local funded=require(script.Parent.FundedAccounts).new(e,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),c)
  funded:Start('migration-player');local player=funded:Owner('migration-player')
  assert(e:Submit(player,{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  local source=CP.Capture(e,p);source.Version=14
  local original=clone(source);local re,rp=CP.Restore(source,C);equal(source,original)
  Policy.Validate(rp);assert(rp.MigrationReport.Needed)
  equal(e.Accounts[player],re.Accounts[player]);equal(e.Profiles,re.Profiles)
  assert(re.NextTrade==e.NextTrade and re.TradeHash==e.TradeHash and re.Time==e.Time)
  for _,old in ipairs(source.Engine.Accounts)do
   local ac=re.Accounts[old.Id]
   equal(old.Positions,ac.Positions);assert(old.Realized==ac.Realized and old.CashFlow==ac.CashFlow)
   if not ac.Player then
    assert(ac.StartingCapital==old.Base and #ac.CapitalAdjustments==1)
    assert(math.abs(re:Summary(ac).Equity-ac.PolicyCapitalTarget)<.001)
    assert(math.abs(ac.Base-ac.StartingCapital-ac.NetCapitalAdjustments)<.001)
   end
  end
  for _,o in ipairs(source.Engine.Orders)do if o.ReduceOnly or e.Accounts[o.Owner].Player then equal(o,re.Orders[o.Id])else assert(not re.Orders[o.Id])end end
  local after=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(after)),C)
  equal(after,CP.Capture(rr,pr));local state=rp.Random.State
  assert(not Policy.Apply(rp).Needed and rp.Random.State==state);equal(after,CP.Capture(re,rp))
  for _=1,300 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  return 'V14→V15 migration is pure on input, no trades on restore, idempotent funding and exact replay'
 end)
 test('Surplus bots retire with obligations; oversized reserve reduces through matching',function()
  local c=oldConfig();c.BehaviorWeights={Protective=1};c.ParticipantsPerInstrument=36
  local e=E.new(c,5);local p=P.new(e);for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
  local reserve,extra
  for _,a in ipairs(p.Agents)do if a.Key=='BX'and a.Kind=='Reserve'then reserve=a end;if a.Key=='BX'and a.Kind=='Protective'then extra=a end end
  local b=e.Books.BX;local price=b.Last*b.Spec.Tick
  local counter=e:AddAccount('counterparty',10000000,10000,1,false)
  assert(e:Submit(counter.Id,{Contract='BX',Direction=-1,Quantity=3001,Type='Limit',Price=price}))
  assert(e:Submit(reserve.Id,{Contract='BX',Direction=1,Quantity=3000,Type='Market'}))
  assert(e:Submit(extra.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  local re,rp=CP.Restore(CP.Capture(e,p),C);Policy.Validate(rp)
  local ra,retiring;for _,a in ipairs(rp.Agents)do if a.Id==reserve.Id then ra=a end;if a.Id==extra.Id then retiring=a end end
  assert(ra.Limit==2000 and re.Accounts[ra.Id].Positions.BX.Quantity==3000)
  assert(retiring.Retiring and re.Accounts[extra.Id].Positions.BX.Quantity==1)
  rp:_repairRisk(ra);assert(re.Accounts[ra.Id].Positions.BX.Quantity==3000,'Invented liquidity')
  assert(re:Submit(counter.Id,{Contract='BX',Direction=1,Quantity=1100,Type='Limit',Price=price}))
  for _=1,20 do rp:_repairRisk(ra)end
  rp:_repairRisk(retiring)
  assert(re.Accounts[ra.Id].Positions.BX.Quantity==2000 and not re.Accounts[extra.Id].Positions.BX)
  assert(retiring.Retired);re:Audit();return 'Surplus accounts preserved; no fake fills; reserve closes exactly excess inventory'
 end)
 test('Duplicate agents and unsupported policy downgrade fail closed',function()
  local e=E.new(clone(C),7);local p=P.new(e);local s=CP.Capture(e,p)
  table.insert(s.Population.Agents,clone(s.Population.Agents[1]));assert(not pcall(CP.Restore,s,C))
  s=CP.Capture(e,p);s.Population.PolicyVersion=99;assert(not pcall(CP.Restore,s,C))
  s=CP.Capture(e,p);s.Config.BotPopulation=nil;assert(not pcall(CP.Restore,s,C))
  s=CP.Capture(e,p);s.Config.BotPopulation.Counts.Value=19;assert(not pcall(CP.Restore,s,C))
  s=CP.Capture(e,p);s.Engine.Accounts[1].NetCapitalAdjustments=123;assert(not pcall(CP.Restore,s,C))
  return 'No duplicate population or unrecognized policy accepted'
 end)
 return report
end
return Tests
]====]):sub(2),Hash=([====[!dedd7b987c3f0dc634f87a52f80772121ea1add2316474d3f5058c30d00b2f1c]====]):sub(2),ExpectedHash=([====[!b482abeef1b8bca9c33bc652f24049e4e84f01537cb90fc85bf7371e69af5499]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotPublicInformationTests]====]):sub(2)]={Source=([====[!local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local S=require(script.Parent.BotSignals)
local L=require(script.Parent.BotLiquidity)
local CP=require(script.Parent.WorldCheckpoint)
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
]====]):sub(2),Hash=([====[!44b6b3f0bd13ae44f51b62d42acab0839c5a9a11b6cba6c08304d2972e298bc4]====]):sub(2),ExpectedHash=nil}
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
  equal(CP.Capture(e,p),CP.Capture(restored,rp));assert(CP.Version==21)
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
]====]):sub(2),Hash=([====[!c6ae4e479e3458185f2ff42cfbfab2ca3cdc238e8e282d8a1ffe6fa94fb7d250]====]):sub(2),ExpectedHash=([====[!e9b94775b25b493c9bc992843b95fa6322ecfe5ae2a88bedf46e659471e4df0b]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotSignals]====]):sub(2)]={Source=([====[!-- Server-only, bounded price observations in simulated seconds (not execution count).
-- Histories live in Participants.Markets, so checkpoints retain exact signal timing.
local Signals={}
Signals.InformationVersion=1
-- Best bid/ask are public even without the depth pass. Strategies use ticks internally.
-- A one-sided/empty book falls back to the observed last price, never generator state.
function Signals.Quote(population,key)
 local e=population.Engine;local b=e.Books[key];local depth=e:PublicDepth(key,1)
 local bid=depth.Bids[1]and depth.Bids[1].Price/b.Spec.Tick
 local ask=depth.Asks[1]and depth.Asks[1].Price/b.Spec.Tick
 return {Bid=bid,Ask=ask,Value=bid and ask and (bid+ask)/2 or b.Last or b.Reference}
end
function Signals.Sample(population,key)
 local c=population.Config.BotSignals;if not c then return end
 local market=population.Markets[key];local book=population.Engine.Books[key]
 if book.Spec.CloseOnly then return end
 local now=population.Engine.Time
 local history=market.SignalHistory or {};market.SignalHistory=history
 if #history>0 and now-history[#history].Time<c.SampleSeconds then return end
 table.insert(history,{Time=now,Price=book.Last or book.Reference})
 -- Retain one observation before the window boundary for an exact backward lookup.
 while #history>2 and history[2].Time<now-c.RetentionSeconds do table.remove(history,1)end
end
function Signals.Window(population,key,seconds,confirmationSeconds)
 local history=population.Markets[key].SignalHistory
 if not history or #history==0 then return nil end
 local now=population.Engine.Time
 if now-history[#history].Time>population.Config.BotSignals.SampleSeconds*2 then return nil end
 local previous,recent
 for i=#history,1,-1 do
  local point=history[i]
  if not recent and point.Time<=now-confirmationSeconds then recent=point end
  if point.Time<=now-seconds then previous=point;break end
 end
 if not previous or not recent then return nil end
 local book=population.Engine.Books[key];local last=book.Last or book.Reference
 local low,high=last,last
 local total,duration=0,0
 for i=#history,1,-1 do
  local point=history[i];if point.Time<previous.Time then break end
  low=math.min(low,point.Price);high=math.max(high,point.Price)
 end
 -- Time-weighted observed price, excluding the newest observation. No private generator state.
 for i=1,#history-1 do
  local point=history[i];local from=math.max(previous.Time,point.Time)
  local untilTime=math.min(now,history[i+1].Time)
  if untilTime>from then total+=point.Price*(untilTime-from);duration+=untilTime-from end
 end
 return {Move=last-previous.Price,RecentMove=last-recent.Price,Low=low,High=high,Last=last,
  Mean=duration>0 and total/duration or previous.Price}
end
function Signals.Reversal(population,key,window,spread,minDeviation,reversalTicks)
 if not window then return nil end
 local fair=window.Mean
 local required=math.max(minDeviation,spread*.5+reversalTicks)
 -- A rise/fall alone is not a bargain. Require current fair-value distance AND a turn.
 if fair-window.Last>=required and window.RecentMove>=reversalTicks
  and window.Last-window.Low>=reversalTicks then return 1 end
 if window.Last-fair>=required and window.RecentMove<=-reversalTicks
  and window.High-window.Last>=reversalTicks then return -1 end
 return nil
end
return Signals
]====]):sub(2),Hash=([====[!08bbfb0dc76db7fc2097f4219dbebccce738faaa65f932d6b9b756a71b3fc3a3]====]):sub(2),ExpectedHash=([====[!c35794afe246d39486eec772a50da8b0d68ceb456b058e111627f8025c82de1c]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotSignalsTests]====]):sub(2)]={Source=([====[!local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local S=require(script.Parent.BotSignals)
local CP=require(script.Parent.WorldCheckpoint)
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
]====]):sub(2),Hash=([====[!fb0b2d228a178dabdc9cff615e16f6749979369ef8a677fb5e105721bb4dc2fe]====]):sub(2),ExpectedHash=([====[!03664ded512890765e50cf28648ce7d67bb93e0024eee4507e76875df4955bd4]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.BotStatsTests]====]):sub(2)]={Source=([====[!local Stats=require(script.Parent.BotStats)
local Command=require(script.Parent.OwnerBotsCommand)
local Refresh=require(script.Parent.BotRefresh)
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Tests={}
local function copy(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b)
 assert(type(a)==type(b));if type(a)~="table"then assert(a==b);return end
 for k,v in pairs(a)do equal(v,b[k])end for k in pairs(b)do assert(a[k]~=nil)end
end
local function near(a,b)assert(math.abs(a-b)<.001,tostring(a).." ~= "..tostring(b))end
local function fixture()
 local c=copy(C);c.PlayerExecution=nil;c.Contracts.BX.Last=5000
 local e=E.new(c,771);local p={Agents={}}
 local a=e:AddAccount("bot:long",100000,100,.8,false)
 table.insert(p.Agents,{Id=a.Id,Kind="Maker",Key="BX"})
 e:AddAccount("private-player",1000000,100,.8,true)
 assert(e:Submit("private-player",{Contract="BX",Direction=-1,Quantity=2,Type="Limit",Price=5000}))
 assert(e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=2,Type="Market"}))
 e.Books.BX.Last=5010/.25
 local b=e:AddAccount("bot:retired",30000,20,.8,false)
 table.insert(p.Agents,{Id=b.Id,Kind="Value",Key="BX",Retiring=true})
 local house=e:AddAccount("private-clearing",1000000000,100,.8,false);house.House=true
 local archive=e:AddAccount("private-archive",999,1,.8,false);archive.Archive=true
 -- Even malformed population membership cannot expose these accounts.
 for _,id in ipairs({"private-player","private-clearing","private-archive"})do table.insert(p.Agents,{Id=id})end
 return e,p,a
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Stats reconcile type/market totals, include retiring bots and exclude private accounts",function()
  local e,p=fixture();local r=Stats.Capture(e,p)
  assert(r.Total.Count==2 and r.Total.Active==1 and r.Total.Retired==1)
  near(r.Total.Allocation,1000000);near(r.Total.Balance,130000);near(r.Total.Equity,131000)
  near(r.Total.Realized,0);near(r.Total.Unrealized,1000);near(r.Total.Pnl,1000)
  assert(r.Total.Positions==1 and r.Total.Contracts==2)
  near(r.Kinds.Maker.Pnl+r.Kinds.Value.Pnl,r.Markets.BX.Pnl)
  local text=Stats.Format(r)
  assert(text:find("BY BOT TYPE",1,true)and text:find("BY MARKET",1,true)and text:find("INDIVIDUAL BOTS",1,true))
  assert(not text:find("private",1,true)and #text<Stats.MaxBytes)
 end)
 test("Inspection and formatting are deterministic and do not mutate the exchange",function()
  local e,p=fixture();local accounts,books,orders,agents=copy(e.Accounts),copy(e.Books),copy(e.Orders),copy(p)
  local first=Stats.Text(e,p);assert(first==Stats.Text(e,p))
  equal(accounts,e.Accounts);equal(books,e.Books);equal(orders,e.Orders);equal(agents,p)
  -- A detached report may be edited without changing an account.
  local r=Stats.Capture(e,p);r.Bots[1].Equity=7;equal(accounts,e.Accounts)
 end)
 test("Reports use refresh P&L baselines instead of counting historical profit or funding",function()
  local e,p,a=fixture();local plan=Refresh.Prepare(e,p,1,1);Refresh.Apply(e,p,plan);e:Audit()
  -- Retiring accounts are reported but do not receive refresh funding.
  local r=Stats.Capture(e,p);near(r.Total.Pnl,0);near(r.Total.Equity,780000);assert(r.Refresh.Sequence==1)
  near(e.Accounts['bot:retired'].Balance,30000);near(r.Total.CapitalAdjusted,649000)
  e.Books.BX.Last=5012/.25;r=Stats.Capture(e,p);near(r.Total.Pnl,200);near(r.Total.Unrealized,200)
  assert(Stats.Format(r):find("Last bot refresh: #1",1,true));near(a.Realized,0)
 end)
 test("Depleted equity, pending exits, working and queued orders are counted accurately",function()
  local e,p,a=fixture();a.Positions.BX.Triggered="Stop loss";e.Books.BX.Last=3900/.25
  assert(e:Submit("bot:retired",{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=3800}))
  local r=Stats.Capture(e,p);assert(r.Total.Depleted==1 and r.Total.Exits==1 and r.Total.Orders==1)
  local id=next(e.Accounts["bot:retired"].OpenOrders);e.Orders[id].Queued=true
  r=Stats.Capture(e,p);assert(r.Total.Queued==1)
 end)
 test("Empty populations format without division by zero",function()
  local e=E.new(copy(C),1);local r=Stats.Capture(e,{Agents={}})
  assert(r.Total.Count==0 and not Stats.Format(r):find("nan",1,true))
 end)
 test("Exact stats parsing and server ownership prevent unauthorized report generation",function()
  assert(Command.Parse(" /BOTS STATS ")=="stats"and Command.Parse("/bots refresh")=="refresh")
  for _,s in ipairs({"/bots stats all","/bots status","/botsstats","/bots","/bots stats\nrefresh"})do assert(not Command.Parse(s))end
  local calls=0;local messages={};local actor={UserId=1}
  local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,StatsReady=function()return true end,
   Stats=function(player)assert(player==actor);calls+=1 end,Notify=function(_,m)table.insert(messages,m)end,
   Ready=function()error("Stats cannot enter refresh flow")end,NextSequence=function()error("Stats cannot allocate a reset receipt")end})
  command:Handle({UserId=2},"/bots stats");assert(calls==0 and messages[1]:find("Only the experience owner",1,true))
  command:Handle(actor,"/bots stats");command:Handle(actor,"/bots stats");assert(calls==1 and not command.Pending and not command.Busy)
 end)
 test("Group-owner reports are private and unavailable worlds fail closed",function()
  local count=0;local command=Command.new({CreatorType=Enum.CreatorType.Group,CreatorId=77,
   GroupLookup=function()return {Owner={Id=1}}end,StatsReady=function()return true end,
   Stats=function()count+=1 end,Notify=function()end})
  command:Handle({UserId=2},"/bots stats");command:Handle({UserId=1},"/bots stats");assert(count==1)
  command.Options.StatsReady=function()return false end;command:Handle({UserId=1},"/bots stats");assert(count==1)
  command.Options.GroupLookup=function()error("lookup failed")end;command:Handle({UserId=1},"/bots stats");assert(count==1)
 end)
 test("Stats failures do not block a later refresh or leak internal error details",function()
  local message;local command=Command.new({CreatorType=Enum.CreatorType.User,CreatorId=1,StatsReady=function()return true end,
   Stats=function()error("private error")end,Notify=function(_,m)message=m end,Ready=function()return true end,NextSequence=function()return 1 end})
  command:Handle({UserId=1},"/bots stats");assert(message:find("could not be prepared",1,true)and not message:find("private error",1,true))
  command:Handle({UserId=1},"/bots refresh");assert(command.Pending and command.Pending.Sequence==1)
 end)
 return rows
end
return Tests
]====]):sub(2),Hash=([====[!a959ccb874f67697850c6a255bd62c8572a14dd888c580e3063dea3cc2a630e2]====]):sub(2),ExpectedHash=([====[!e868077e11f23143747f3ef4f3ee3ed9be7057c85154cda1a7ae6ebce919e931]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.MakerLiquidityTests]====]):sub(2)]={Source=([====[!local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(v)
 if type(v)~="table"then return v end
 local out={}for k,x in pairs(v)do out[k]=clone(x)end return out
end
local function equal(a,b)
 assert(type(a)==type(b),"State type changed")
 if type(a)~="table"then assert(a==b,"State value changed");return end
 for k,v in pairs(a)do equal(v,b[k])end
 for k in pairs(b)do assert(a[k]~=nil,"Unexpected state key")end
end
local function fixture(count,multiplier)
 local config=clone(C);config.MakerQuoteSizeMultiplier=multiplier or 3
 local e=E.new(config,7251)
 local p=setmetatable({Engine=e,Config=config,Random=P.RNG.new(7251),Agents={},Markets={},
  Regime={Volatility=1,Liquidity=1,Activity=1},NewsUntil=0},P)
 for _,key in ipairs(config.ContractOrder)do p.Markets[key]={Fair=e.Books[key].Reference}end
 for i=1,count do
  local a=p:_agent("BX","Maker",i);a.Size=6
  p:_maker(a)
 end
 e:AddAccount("taker",1000000,1000,1,true)
 return e,p,p.Agents[1]
end
function Tests.Run()
 local results={}
 local function test(name,fn)local ok,result=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})end
 test("Larger real quotes fill a 143-contract market order in both directions",function()
  local report={}
  for _,side in ipairs({1,-1})do
   local old=fixture(3,1)
   local _,before=old:Submit("taker",{Contract="BX",Direction=side,Quantity=143,Type="Market"})
   local e=fixture(3,3)
   local ok,after=e:Submit("taker",{Contract="BX",Direction=side,Quantity=143,Type="Market"})
   assert(ok and after.Filled==143 and after.Cancelled==0)
   assert(before.Filled<143 and before.Cancelled>0)
   assert(e.Accounts.taker.Positions.BX.Quantity==143 and e.TotalVolume==143)
   old:Audit();e:Audit()
   table.insert(report,{Direction=side,Before=before.Filled,After=after.Filled})
  end
  return report
 end)
 test("Consumed quotes replenish after a short delay; partial quotes retain priority",function()
  local e,p,a=fixture(1);local bidId=a.Quotes["1:1"];local askId=a.Quotes["-1:1"]
  local bid=e.Orders[bidId];local ask=e.Orders[askId];local qty=ask.Remaining
  assert(e:Submit("taker",{Contract="BX",Direction=-1,Quantity=bid.Remaining,Type="Market"}))
  assert(e:Submit("taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  local priority=ask.Priority
  p:_maker(a)
  assert(not a.Quotes["1:1"] and a.ReplenishAt["1:1"]==e.Time+C.MakerReplenishSeconds)
  e:AdvanceClock(C.MakerReplenishSeconds-.25);p:_maker(a)
  assert(not a.Quotes["1:1"],"Replenished before cooldown")
  e:AdvanceClock(.25);p:_maker(a)
  assert(a.Quotes["1:1"] and a.Quotes["1:1"]~=bidId,"Depleted slot not replenished")
  assert(a.Quotes["-1:1"]==askId and ask.Remaining==qty-1 and ask.Priority==priority,"Partial quote lost FIFO")
  e:Audit();return "1.5-second refill delay; existing partial quote preserved"
 end)
 test("Larger quotes fit available inventory and capital without resetting balances",function()
  local e,p,a=fixture(1);e:CancelAll(a.Id);a.QuotePolicy=nil
  local account=e.Accounts[a.Id];account.Limit=5;a.Limit=5;a.Size=9
  local balance,base=account.Balance,account.Base
  p:_maker(a)
  local buy,sell=0,0
  for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o.Direction==1 then buy+=o.Remaining else sell+=o.Remaining end end
  assert(buy==5 and sell==5,"Did not size quotes to the remaining inventory allowance")
  assert(account.Balance==balance and account.Base==base and e:Exposure(account,"BX",1,0))
  e:CancelAll(a.Id);a.QuotePolicy=nil;account.Risk=0
  p:_maker(a);assert(not next(account.OpenOrders),"Posted without risk capacity")
  e:Audit();return "Quotes capped at five per side; no quotes with zero buying power"
 end)
 test("Thin liquidity regimes retain smaller finite depth",function()
  local e,p,a=fixture(1);e:CancelAll(a.Id);a.QuotePolicy=nil
  p.Regime.Liquidity=.22;p:_maker(a)
  local n=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do
   n+=1;assert(e.Orders[id].Remaining<=4,"Thin market received full-sized quotes")
  end
  assert(n==2,"Thin market should have one level per side")
  e:Audit();return "Stress still reduces size and depth"
 end)
 test("Old worlds adopt tuning without altering accounts, tape or resting orders during restore",function()
  local old=clone(C);old.MakerQuotePolicyVersion=2
  old.MakerQuoteSizeMultiplier=nil;old.MakerReplenishSeconds=nil;old.MakerDecisionMultiplier=nil
  local e=E.new(old,7282);local p=P.new(e)
  for _=1,200 do p:Step()end
  local before=Checkpoint.Capture(e,p)
  local restored,agents=Checkpoint.Restore(before,C)
  local after=Checkpoint.Capture(restored,agents)
  equal(before.Engine,after.Engine);equal(before.Population,after.Population)
  assert(after.Config.MakerQuoteSizeMultiplier==C.MakerQuoteSizeMultiplier and after.Config.MakerReplenishSeconds==1.5 and after.Config.MakerDecisionMultiplier==.5)
  local resumed,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(after)),C)
  equal(after,Checkpoint.Capture(resumed,rp))
  for _=1,400 do agents:Step();rp:Step()end
  equal(Checkpoint.Capture(restored,agents),Checkpoint.Capture(resumed,rp))
  local migrated=0;for _,a in ipairs(agents.Agents)do if a.Kind=="Maker" and a.QuotePolicy==C.MakerQuotePolicyVersion then migrated+=1 end end
  assert(migrated==60);restored:Audit();resumed:Audit()
  return "Restore preserves history and accounts; makers adopt the policy on their next turn; replay remains exact"
 end)
 return results
end
return Tests
]====]):sub(2),Hash=([====[!902f82ca4b0dc713d3f70b227c5c6e5a35f4626a54b1ae8899fa83e84e42376e]====]):sub(2),ExpectedHash=([====[!1c955067f4f1f15d40f89cccdc1c4d5c501c59d77b42e0b9a0753fbe969a531d]====]):sub(2)}
release[([====[!ReplicatedStorage.MarketReign.MarketConfig]====]):sub(2)]={Source=([====[!-- All prices, participants and funds in this place are simulated.

return {

 Seed = 0, -- Offline preview/test seed only. Live random state is private in ServerScriptService.

 StepSeconds = 0.25,

 SimulationSpeed = 18,

 BroadcastSeconds = 0.1, -- Ten lightweight market batches per second; GUI motion follows display frames.

 DepthLevels = 5, -- Real best levels supplied per side; the UI never pads missing liquidity.
 MakerQuotePolicyVersion = 5,
 MakerMinRestSeconds = 18, -- Simulated seconds (one wall-clock second at the default speed).
 MakerRepriceTicks = 3, -- Keep queue priority until fair value moves materially.
 MakerQuoteSizeMultiplier = 1.5, -- Twice as many makers share the former aggregate quote budget.
 MakerReplenishSeconds = 1.5, -- Delay after discovering a fully consumed/expired quote.
 MakerDecisionMultiplier = 0.5, -- Check inventory and depleted slots twice as frequently.
 -- Additional funded institutions, anchored to independent simulated fair value.
 ReservePopulationVersion = 2,
 -- Capital backs inventory over time; it is not the quantity displayed at one price.
 -- Simulation calibration, not a live CME feed. See liquidity-research.json for sources.
 Reserve = {Count=6,Capital=5000000,InventoryLimit=2000,QuoteSize=24,
  QuoteSizes={BX=24,BT=4,BG=3},SizeVariation={0.7,1.3},DepthGrowth=0.15,SpacingTicks=1,
  Offsets={1,2,3,4,5},DecisionSeconds=1,RestSeconds=2,RepriceTicks=2},
 -- A balance controls total holdings, not how much liquidity a player can take in one burst.
 PlayerExecution = {Version=1,WindowSeconds=18,SliceContracts=5000,OwnerContracts=20000,
  MarketContracts=100000,BookFraction=0.1,GuardTicks=20,OwnersPerStep=32},

 WarmupSeconds = 1800, -- History is generated by running the same matching engine.

 MaxCatchupSteps = 32,
 SimulationFrameBudgetMs = 8,
 BotExitRetrySeconds = 4, -- Simulated seconds; new quotes/fair value wake blocked exits sooner.
 MarketRetirementVersion = 1, -- Cash-settle and archive closed markets once, without funding bots.

 ParticipantsPerInstrument = 76,
 -- Exact allocation. Capital is simulation funding, distinct from trading P&L.
 BotPopulation = {Version=1,
  Order={"Maker","Liquidity","Momentum","Value","Reversion","Protective","Scalper","Whale","Reserve"},
  Counts={Maker=20,Liquidity=24,Momentum=12,Value=20,Reversion=12,Protective=8,Scalper=24,Whale=4,Reserve=6},
  Capital={Maker=750000,Liquidity=150000,Momentum=200000,Value=250000,Reversion=200000,Protective=150000,Scalper=100000,Whale=1500000,Reserve=5000000},
  -- Reserve half of allowed funding for drawdowns; pending entries still reserve real margin.
  MarginFraction=0.5, ReferenceDollarVolatility=12.5,
  TraderActivityScale=76/36, MakerActivityScale=2, WhaleActivityScale=4/3,
  ValueHalfLife={6,18}, ValueObservationSeconds={2,8}, ValueNoiseTicks={2,6},
  ScalperMinMoveTicks={3,8}, ScalperNoise=0.2,
 },

 -- Additional short-horizon participants; times use simulated seconds.
 ScalperPopulationVersion = 1,
 ScalpersPerInstrument = 24,
 Scalper = {
  Size = {1,2}, DecisionSeconds = {2.67,6.67}, CooldownSeconds = {12,32},
  HoldSeconds = {48,160}, OrderLifetimeSeconds = {3,7},
  TargetTicks = {4,10}, StopTicks = {5,12}, MaxSpreadTicks = 3,
  MaxSlippageTicks = 1, AggressiveChance = 0.45,
 },

 -- Strategy-only version: adopting it never changes bot capital, inventory or existing exits.
 BotInformationVersion = 1, -- Only Maker and Reserve strategies may observe internal fair value.
 BotLiquidity = {Version=2,MaxDrawdown=.25,MaxInventory=8,MarginFraction=.5,
  PositionRiskFraction=.01,MinStopTicks=8,MaxStopTicks=24,QuoteSeconds=6,DecisionSeconds=2,RepriceTicks=2,
  EntryContracts=1,MinHalfSpreadTicks=2,VolatilitySpread=1},
 BotSignals = {Version=2,SampleSeconds=1,RetentionSeconds=60,FairNoiseTicks=0.6,
  ReversionSeconds=30,ConfirmationSeconds=3,ReversalTicks=1,ReversionDeviationTicks=2,
  ScalperSeconds={12,30},ScalperMinMoveTicks=1,ScalperVolatilityMultiplier=2,
  ScalperDeviationTicks=1,ScalperProfitBufferTicks=1},

 MakersPerInstrument = 20,

 MakerPopulationVersion = 1, -- One-time top-up of active markets when older worlds resume.

 WhalesPerInstrument = 4,

 BehaviorWeights = {Liquidity=30, Momentum=20, Value=22, Reversion=18, Protective=10},

 Liquidity = 1,

 Volatility = 1,

 WhaleFrequency = 1,

 NewsFrequency = 1,

 RegimeSeconds = {100, 240},

 Regimes = {

  {Name="Quiet", Weight=24, Volatility=0.45, Liquidity=1.4, Activity=0.65, Trend=0},

  {Name="Trending", Weight=22, Volatility=1, Liquidity=1, Activity=1.1, Trend=0.10},

  {Name="Range-bound", Weight=24, Volatility=0.85, Liquidity=1.2, Activity=1, Trend=0},

  {Name="High volatility", Weight=16, Volatility=2.5, Liquidity=0.6, Activity=1.7, Trend=0},

  {Name="Thin liquidity", Weight=14, Volatility=1.5, Liquidity=0.22, Activity=0.85, Trend=0},

 },

 Timeframes = {{"1m",60},{"5m",300},{"15m",900},{"1h",3600},{"1D",86400}},

 MaxCandles = 1200, -- Per series. Presentation history only (never read by matching); bounded for checkpoint and subscribe size.

 -- Retain history for panning; ChartViewport independently limits density for readable candles.
 MaxTradeHistory = 4000,

 MaxOrderHistory = 4000,

 MaxAccountHistory = 60,

 MaxPlayerQuantity = 100, -- Batch size for legacy close/liquidation paths, not an entry ceiling.

 MaxPlayerInventory = 100, -- Retained for old checkpoint compatibility; players use ContractLimits.

 MaxPlayerOrders = 16,

 PriceBandFraction = 0.10,

 -- Simulated margins, independent of the exchange contract multipliers. They size participant (bot) risk

 -- only. Player accounts receive one contract per $1,000 of closed balance (minimum five),

 -- independent of margin and open P&L; player orders match the same finite book as participants.

 -- Retired markets are close-only and never offered for new trades. A restored world keeps a retired book
 -- only when its save already held one, so open positions, their SL/TP and closing orders keep working and
 -- trade history keeps its symbols. RTY and YM retired with the Blox markets; MES-MYM are pre-V3 micros.
 LegacyOrder = {"RTY","YM","MES","MNQ","M2K","MYM"},
 LegacyContracts = {
  RTY={Name="RTY · retired market",Short="Retired · close only",Last=2218.4,Multiplier=50,Tick=0.1,Scale=0.6,Margin=750,CloseOnly=true},
  YM={Name="YM · retired market",Short="Retired · close only",Last=42376,Multiplier=5,Tick=1,Scale=2,Margin=750,CloseOnly=true},
  MES={Name="Legacy micro · retired",Short="Legacy micro",Last=5824.75,Multiplier=5,Tick=0.25,Scale=1,Margin=1200,CloseOnly=true},
  MNQ={Name="Legacy micro · retired",Short="Legacy micro",Last=20485.5,Multiplier=2,Tick=0.25,Scale=3,Margin=2000,CloseOnly=true},
  M2K={Name="Legacy micro · retired",Short="Legacy micro",Last=2218.4,Multiplier=5,Tick=0.1,Scale=0.6,Margin=800,CloseOnly=true},
  MYM={Name="Legacy micro · retired",Short="Legacy micro",Last=42376,Multiplier=0.5,Tick=1,Scale=2,Margin=1000,CloseOnly=true},
 },
 -- Renamed in place: a restored save moves the book, positions, orders and history to the new symbol.
 Renamed={ES="BX",NQ="BT"},
 -- New books opened while migrating a pre-V3 micro save start near the saved micro price.
 LegacyToCurrent={MES="BX",MNQ="BT"},
 Contracts = {
  BX={Name="Blox 500",Short="Blox 500",Last=5824.75,Change=0,Multiplier=50,Tick=0.25,Scale=1,Margin=750},
  BT={Name="BloxTech 100",Short="BloxTech 100",Last=20485.5,Change=0,Multiplier=20,Tick=0.25,Scale=3,Margin=750},
  BG={Name="Blox Gold",Short="Blox Gold",Last=2384.6,Change=0,Multiplier=100,Tick=0.1,Scale=1,Margin=750},
 },
 ContractOrder = {"BX","BT","BG"},

}
]====]):sub(2),Hash=([====[!01b0eb2aa3856a21e987cdab5ea6e505d054c241d97b48df40a8f76b0072e223]====]):sub(2),ExpectedHash=([====[!e469c046fd60fbf416dfb1079b6167ca9a9f9649f96be714e2afc39ec8b0ee8f]====]):sub(2)}
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
  if o.StopTicks and not p.ManualStop and (not a.Player or p.Stop==nil)then
   local stop=math.round((p.Entry-side*o.StopTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick
   -- Adding to a losing bot position must not move its existing stop farther away.
   if not p.Stop or (stop-p.Stop)*side>0 then p.Stop=stop end
  end
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
 if self.Books[o.Contract].Spec.CloseOnly and not o.ReduceOnly then return 0,"Market is close-only"end
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
 if b.Spec.CloseOnly and not reducing then return false,b.Key.." is a retired market and is close-only. Choose an available market for new trades." end
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
-- One read-only executable quote view for clients and public-information strategies.
function Engine:PublicDepth(key,levels)
 local b=self.Books[key];local depth={Bids={},Asks={}};local summaries={}
 for _,side in ipairs({"Bids","Asks"})do
  local direction=side=="Asks"and 1 or -1
  for _,level in ipairs(b[side])do
   if not PlayerExecution.Allows(self,b,level.Price,direction)then break end
   local quantity=0;for _,o in ipairs(level.Orders)do quantity+=self:_available(o,true,summaries)end
   if quantity>0 then table.insert(depth[side],{Price=level.Price*b.Spec.Tick,Quantity=quantity})end
   if #depth[side]>=(levels or self.Config.DepthLevels or 5)then break end
  end
 end
 return depth
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
  local depth=self:PublicDepth(symbol)
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
 local accounts={}for _,id in ipairs(self.AccountOrder)do table.insert(accounts,self.Accounts[id])end
 local archive=self.MarketRetirement
 if archive then
  assert(archive.Version==self.Config.MarketRetirementVersion,'Retirement archive policy mismatch')
  for _,a in ipairs(archive.Accounts)do
   assert(not self.Accounts[a.Id]and a.Retired and not a.Player and not a.House and not a.Archive,'Invalid retired bot archive')
   assert(not next(a.Positions)and not next(a.OpenOrders),'Archived bot has exposure')
   table.insert(accounts,a)
  end
  for key,row in pairs(archive.Markets)do local b=row.Book
   assert(not self.Books[key]and b.Spec.CloseOnly and not b.Bids[1]and not b.Asks[1],'Archived market is active')
   volume+=b.Volume
   for _,tf in ipairs(self.Config.Timeframes)do assert((b.CandleVolume[tf[1]]or 0)==b.Volume,'Archived candle volume mismatch')end
  end
 end
 for _,a in ipairs(accounts)do
  cash+=a.CashFlow equity+=self:Summary(a).Equity-a.Base
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
]====]):sub(2),Hash=([====[!f9693d427ffd1d44afd00aa397fef7570ea7232dd0a9cfe023f7688e8756eeef]====]):sub(2),ExpectedHash=([====[!f5a25d6fb3f7241cb5a48e21da97048320703af787c52e972a4b5ed894338f4c]====]):sub(2)}
release[([====[!ServerScriptService.MarketReign.Participants]====]):sub(2)]={Source=([====[!-- One deterministic scheduler; participants never own task loops or modify trade prices.
local Participants={}
local BotPopulation=require(script.Parent.BotPopulation)
local BotExitRetry=require(script.Parent.BotExitRetry)
local Signals=require(script.Parent.BotSignals)
local BotLiquidity=require(script.Parent.BotLiquidity)
Participants.__index=Participants
local RNG={} RNG.__index=RNG
function RNG.new(seed) return setmetatable({State=math.floor(math.abs(seed))%2147483646+1},RNG) end
function RNG:Next() self.State=self.State*48271%2147483647 return self.State/2147483647 end
function RNG:Range(a,b) return a+(b-a)*self:Next() end
function RNG:Int(a,b) return math.floor(self:Range(a,b+1)) end
function RNG:Noise() return (self:Next()+self:Next()+self:Next()-1.5)*2 end
Participants.RNG=RNG
function Participants.new(engine)
 local self=setmetatable({Engine=engine,Config=engine.Config,Random=RNG.new(engine.Seed),Agents={},Markets={},Regime=nil,
  NextRegime=0,NextNews=80,NextBeliefs=0,News="No synthetic news",NewsUntil=0,Events={}},Participants)
 local r=self.Random
 self:_regime()
 for _,key in ipairs(self.Config.ContractOrder) do
  local book=engine.Books[key]
  self.Markets[key]={Fair=book.Reference,Anchor=book.Reference,Impulse=0}
  book.FairReference=book.Reference
  if book.Spec.CloseOnly then continue end
  for i=1,self.Config.MakersPerInstrument do self:_agent(key,"Maker",i) end
  self:_ordinary(key)
  if self.Config.WhaleFrequency>0 then for i=1,self.Config.WhalesPerInstrument do self:_agent(key,"Whale",i) end end
  if not book.Spec.CloseOnly then for i=1,self.Config.ScalpersPerInstrument or 0 do self:_agent(key,"Scalper",i) end end
  if self.Config.Reserve and not book.Spec.CloseOnly then for i=1,self.Config.Reserve.Count do self:_agent(key,"Reserve",i)end end
 end
 self.PolicyVersion=self.Config.BotPopulation and self.Config.BotPopulation.Version or nil
 BotPopulation.Validate(self)
 -- A genuine opening auction: finite makers post, and a participant crosses a quote.
 for _,a in ipairs(self.Agents) do if a.Kind=="Maker" then self:_maker(a) end end
 for _,a in ipairs(self.Agents) do if a.Kind=="Reserve" then self:_reserve(a)end end
 for _,key in ipairs(self.Config.ContractOrder) do
  for _,a in ipairs(self.Agents) do if a.Key==key and a.Kind~="Maker" and a.Kind~="Reserve"then
   engine:Submit(a.Id,{Contract=key,Direction=r:Next()<0.5 and 1 or -1,Quantity=1,Type="Market"}) break
  end end
 end
 return self
end
function Participants:_ordinary(key)
 local kinds={"Liquidity","Momentum","Value","Reversion","Protective"}
 if self.Config.BotPopulation and not self.Engine.Books[key].Spec.CloseOnly then
  for _,kind in ipairs(kinds)do for i=1,self.Config.BotPopulation.Counts[kind]do self:_agent(key,kind,i)end end
 else
  for i=1,self.Config.ParticipantsPerInstrument do
   local total=0;for _,kind in ipairs(kinds)do total+=self.Config.BehaviorWeights[kind]or 0 end
   local draw=self.Random:Range(0,total);local chosen="Liquidity"
   for _,kind in ipairs(kinds)do draw-=self.Config.BehaviorWeights[kind]or 0;if draw<=0 then chosen=kind;break end end
   self:_agent(key,chosen,i)
  end
 end
end
function Participants:_profile(key,kind,index)
 local r=self.Random local maker=kind=="Maker" local whale=kind=="Whale"
 local id="bot:"..key..":"..kind..":"..index
 local budget=r:Int(maker and 350000 or whale and 600000 or 50000,maker and 650000 or whale and 1100000 or 160000)
 local a={Id=id,Key=key,Kind=kind,Budget=budget,Risk=r:Range(0.45,0.85),Limit=r:Int(maker and 140 or whale and 180 or 16,maker and 250 or whale and 350 or 60),
  Speed=r:Range(maker and 1.5 or whale and 28 or 2.5,maker and 4.5 or whale and 100 or 13),Size=r:Int(maker and 3 or whale and 18 or 1,maker and 9 or whale and 60 or 5),
  Bias=r:Range(-0.55,0.55),Belief=((maker or kind=="Reserve")and self.Markets[key].Fair or Signals.Quote(self,key).Value)+r:Noise()*9,Patience=r:Range(4,35),Aggression=r:Range(0.2,0.8),
  Next=r:Range(0.2,18),Stop=r:Int(16,85),Target=r:Int(20,140),Parent=0,ParentSide=1}
 if whale then a.Bias=index%2==0 and -0.3 or 0.3 end
 if kind=="Scalper" then
  local s=assert(self.Config.Scalper,"Scalper settings required")
  a.Size=r:Int(s.Size[1],s.Size[2]);a.Limit=a.Size
  a.Speed=r:Range(s.DecisionSeconds[1],s.DecisionSeconds[2])
  a.Stop=r:Int(s.StopTicks[1],s.StopTicks[2]);a.Target=r:Int(s.TargetTicks[1],s.TargetTicks[2])
  a.MaxHold=r:Range(s.HoldSeconds[1],s.HoldSeconds[2])
  a.Patience=r:Range(s.OrderLifetimeSeconds[1],s.OrderLifetimeSeconds[2])
  a.Cooldown=r:Range(s.CooldownSeconds[1],s.CooldownSeconds[2])
  a.Style=index%2==0 and "Momentum" or "Reversion"
  a.Lookback=r:Int(3,12);a.ReadyAt=0
 end
 if kind=="Reserve"then
  local c=self.Config.Reserve;budget=c.Capital;a.Budget=budget;a.Risk=.8;a.Limit=c.InventoryLimit
  a.Size=c.QuoteSizes and c.QuoteSizes[key]or c.QuoteSize;a.Speed=c.DecisionSeconds
  a.ReservePolicy=self.Config.ReservePopulationVersion
 end
 a.InformationVersion=Signals.InformationVersion
 BotPopulation.Configure(self,a)
 return a
end
function Participants:_agent(key,kind,index)
 local a=self:_profile(key,kind,index)
 assert(not self.Engine.Accounts[a.Id],"Duplicate bot account")
 local account=self.Engine:AddAccount(a.Id,a.Budget,a.Limit,a.Risk,false)
 account.StartingCapital=a.Budget;account.NetCapitalAdjustments=0
 account.PolicyCapitalTarget=a.Budget
 if kind=="Reserve"then account.LiquidityProvider=true end
 table.insert(self.Agents,a)
 return a
end
-- Append missing makers to active markets. Saved agent ids may still use a retired symbol;
-- count by Key/Kind and never reuse an existing account. Quotes begin on normal future steps,
-- so restoring a world cannot execute trades or rewrite its tape just by adding liquidity.
function Participants:EnsureMakers(keys,target)
 return self:_ensurePopulation(keys,"Maker",target)
end
function Participants:EnsureScalpers(keys,target)
 return self:_ensurePopulation(keys,"Scalper",target)
end
function Participants:EnsureReserves(keys)
 return self:_ensurePopulation(keys,"Reserve",self.Config.Reserve and self.Config.Reserve.Count or 0)
end
-- Withdraw obsolete bot quotes on upgrade without executing trades or resetting ledgers.
-- Replacement sizes come from the current policy even for already-saved agents.
function Participants:RefreshReservePolicy()
 local c=self.Config.Reserve;if not c then return end
 for _,a in ipairs(self.Agents)do if a.Kind=="Reserve"and a.ReservePolicy~=self.Config.ReservePopulationVersion then
  self.Engine:CancelAll(a.Id,a.Key);a.Quotes={}
  a.Size=c.QuoteSizes and c.QuoteSizes[a.Key]or c.QuoteSize;a.Speed=c.DecisionSeconds
  a.ReservePolicy=self.Config.ReservePopulationVersion
  a.Next=self.Engine.Time+c.DecisionSeconds
 end end
end
function Participants:_ensurePopulation(keys,kind,target)
 local e=self.Engine local added=0
 for _,key in ipairs(keys) do
  if e.Books[key] and not e.Books[key].Spec.CloseOnly then
   local count=0
   for _,a in ipairs(self.Agents) do if a.Key==key and a.Kind==kind and not a.Retiring then count+=1 end end
   local index=count+1
   while count<target do
    while e.Accounts["bot:"..key..":"..kind..":"..index] do index+=1 end
    local a=self:_agent(key,kind,index)
    a.Next+=e.Time
    count+=1 index+=1 added+=1
   end
  end
 end
 return added
end
-- Add a new market on migration without reseeding or advancing the saved exchange.
-- Retired (close-only) books keep their original participants and economics until positions close.
function Participants:AddMarket(key)
 local e=self.Engine local r=self.Random local first=#self.Agents+1
 local book=e.Books[key]
 self.Markets[key]={Fair=book.Reference,Anchor=book.Reference,Impulse=0}
 book.FairReference=book.Reference
 if book.Spec.CloseOnly then return end
 for i=1,self.Config.MakersPerInstrument do self:_agent(key,"Maker",i) end
 self:_ordinary(key)
 if self.Config.WhaleFrequency>0 then for i=1,self.Config.WhalesPerInstrument do self:_agent(key,"Whale",i) end end
 if not book.Spec.CloseOnly then for i=1,self.Config.ScalpersPerInstrument or 0 do self:_agent(key,"Scalper",i) end end
 if self.Config.Reserve and not book.Spec.CloseOnly then for i=1,self.Config.Reserve.Count do self:_agent(key,"Reserve",i)end end
 for i=first,#self.Agents do
  local a=self.Agents[i] a.Next+=e.Time
  if a.Kind=="Maker" then self:_maker(a) end
  if a.Kind=="Reserve"then self:_reserve(a)end
 end
 for i=first,#self.Agents do
  local a=self.Agents[i]
  if a.Kind~="Maker" and a.Kind~="Reserve"then e:Submit(a.Id,{Contract=key,Direction=r:Next()<0.5 and 1 or -1,Quantity=1,Type="Market"}) break end
 end
end
function Participants:_regime()
 local r=self.Random local total=0 for _,regime in ipairs(self.Config.Regimes) do total+=regime.Weight end
 local draw=r:Range(0,total) local chosen=self.Config.Regimes[1]
 for _,regime in ipairs(self.Config.Regimes) do draw-=regime.Weight if draw<=0 then chosen=regime break end end
 self.Regime=chosen self.Direction=r:Next()<0.5 and 1 or -1
 self.NextRegime=self.Engine.Time+r:Range(self.Config.RegimeSeconds[1],self.Config.RegimeSeconds[2])
 table.insert(self.Events,{Step=self.Engine.Step,Kind="Regime",Name=chosen.Name,Direction=self.Direction})
 if #self.Events>40 then table.remove(self.Events,1) end
end
function Participants:_fit(a,side,quantity)
 local e=self.Engine;local ac=e.Accounts[a.Id];local lo,hi=0,math.max(0,math.floor(quantity))
 if e:Exposure(ac,a.Key,side,hi)then return hi end
 while lo<hi do local mid=math.ceil((lo+hi)/2);if e:Exposure(ac,a.Key,side,mid)then lo=mid else hi=mid-1 end end
 return lo
end
-- Migration never fabricates a closing fill. Excess/retiring positions work down through finite quotes.
function Participants:_repairRisk(a)
 local e=self.Engine;local ac=e.Accounts[a.Id]
 local retiring=a.Retiring;local needs=retiring
 local liquidityLimit=a.Kind=='Liquidity'and self.Config.BotLiquidity and BotLiquidity.Limit(self,a)
 if liquidityLimit and BotLiquidity.Protect(self,a)then liquidityLimit=0 end
 if liquidityLimit==0 then
  local entries={};for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(entries,id)end end
  table.sort(entries);for _,id in ipairs(entries)do e:Cancel(a.Id,id)end
  needs=true
 end
 for key,pos in pairs(ac.Positions)do
  -- ProcessStops owns triggered exits, including their retry schedule.
  if pos.Triggered then needs=true;continue end
  local maximum=retiring and 0 or math.min(ac.Limit,math.max(0,math.floor(e:Summary(ac).Equity*ac.Risk/e.Books[key].Spec.Margin)))
  if liquidityLimit then maximum=math.min(maximum,liquidityLimit)end
  if pos.Quantity>maximum then
   needs=true;e:CancelAll(a.Id,key)
   if BotExitRetry.Ready(e,ac,key,pos)then
    local ok,result=e:Submit(a.Id,{Contract=key,Direction=-pos.Direction,Quantity=math.min(64,pos.Quantity-maximum),Type='Market',ReduceOnly=true})
    if not ok or result.Filled==0 then BotExitRetry.Attempted(e,ac,key,pos)end
   end
  end
 end
 if retiring and not next(ac.Positions)then e:CancelAll(a.Id);a.Retired=true end
 return needs
end
-- Retire private estimates and pending entries once when adopting an older saved bot.
-- This never changes funding, positions, stops, targets or reduce-only exit orders.
function Participants:_publicInformation(a)
 if a.Kind=='Maker'or a.Kind=='Reserve'or a.InformationVersion==Signals.InformationVersion then return end
 local e=self.Engine;local account=e.Accounts[a.Id];local ids={}
 for id in pairs(account.OpenOrders)do
  local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end
 end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
 a.Belief=Signals.Quote(self,a.Key).Value
 a.Parent=0;a.ParentSide=1;a.ObservedAt=e.Time;a.NextObservation=e.Time
 a.InformationVersion=Signals.InformationVersion
end
function Participants:_observe(a)
 self:_publicInformation(a)
 if not a.PolicyVersion or a.Kind~='Value' or self.Engine.Time<a.NextObservation then return end
 local now=self.Engine.Time;local elapsed=math.max(0,now-a.ObservedAt)
 local observation=Signals.Quote(self,a.Key).Value+a.ValueOffset+self.Random:Noise()*a.ObservationNoise
 a.Belief+=(observation-a.Belief)*(1-math.exp(-math.log(2)*elapsed/a.BeliefHalfLife))
 a.ObservedAt=now;a.NextObservation=now+a.ObservationSeconds*self.Random:Range(.7,1.3)
end
-- Funded reserve liquidity follows independent fair value, never the last player fill.
-- Quotes are passive and finite. Each replacement reserves real inventory and margin.
function Participants:_reserve(a)
 local e=self.Engine;local b=e.Books[a.Key];local c=self.Config.Reserve;local account=e.Accounts[a.Id]
 if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 a.Quotes=a.Quotes or {}
 local position=account.Positions[a.Key];local inventory=position and position.Quantity*position.Direction or 0
 local fair=math.round(self.Markets[a.Key].Fair);b.FairReference=fair
 local scale=c.SpacingTicks or math.max(1,b.Spec.Scale or 1)
 local stress=math.max(.25,math.min(1,self.Regime.Liquidity))
 local skew=math.clamp(math.round(inventory/a.Limit*4),-4,4)
 for depth,offset in ipairs(c.Offsets)do for _,side in ipairs({1,-1})do
  local slot=side..":"..depth;local held=a.Quotes[slot]and e.Orders[a.Quotes[slot]]
  local tick=math.max(1,fair-skew-side*math.ceil(offset*scale))
  if held and e.Time-held.Time>=c.RestSeconds and math.abs(held.Price-tick)>=c.RepriceTicks then
   e:Cancel(a.Id,held.Id);held=nil
  end
  if not held then
   a.Quotes[slot]=nil
   local opposing=side==1 and b.Asks[1]or b.Bids[1]
   if not opposing or (tick-opposing.Price)*side<0 then
    local variation=c.SizeVariation and self.Random:Range(c.SizeVariation[1],c.SizeVariation[2])or 1
    local size=math.max(1,math.floor(a.Size*variation*stress*(1+(depth-1)*(c.DepthGrowth or .5))*(1-inventory/a.Limit*side*.8)))
    local lo,hi=0,math.max(0,size)
    if not e:Exposure(account,a.Key,side,hi)then
     while lo<hi do local mid=math.ceil((lo+hi)/2);if e:Exposure(account,a.Key,side,mid)then lo=mid else hi=mid-1 end end
     size=lo
    end
    if size>0 then
     local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",Price=tick*b.Spec.Tick,Expires=e.Time+c.RestSeconds*30})
     if ok and result.Remaining>0 then a.Quotes[slot]=result.Id end
    end
   end
  end
 end end
end
function Participants:_maker(a)
 local e=self.Engine local b=e.Books[a.Key] local r=self.Random local c=b.Spec local market=self.Markets[a.Key]
 local account=e.Accounts[a.Id] if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 local policy=self.Config.MakerQuotePolicyVersion or 2
 if a.QuotePolicy~=policy then e:CancelAll(a.Id,a.Key);a.Quotes={};a.ReplenishAt={};a.QuotePolicy=policy end
 local p=account.Positions[a.Key] local inventory=p and p.Quantity*p.Direction or 0
 local stress=self.Regime.Volatility*self.Config.Volatility+math.min(6,b.Volatility)*0.2
 -- Inventory affects our reservation price; the last taker print cannot drag every maker off value.
 local center=market.Fair-inventory/a.Limit*(5+stress*5)
 local spread=math.max(1,math.floor(stress*0.8+b.Volatility*0.2))
 local liquidity=self.Regime.Liquidity*self.Config.Liquidity
 if self.Engine.Time<self.NewsUntil then liquidity*=0.6 end
 local minRest=self.Config.MakerMinRestSeconds or 18
 local reprice=self.Config.MakerRepriceTicks or 3
 local replenish=self.Config.MakerReplenishSeconds or math.max(4,minRest/3)
 local sizeMultiplier=self.Config.MakerQuoteSizeMultiplier or 1
 local activeDepth=liquidity<.35 and 1 or liquidity<.7 and 2 or 3
 for depth=1,3 do
  for _,side in ipairs({1,-1}) do
   local slot=tostring(side)..":"..depth
   local held=a.Quotes[slot]and e.Orders[a.Quotes[slot]]
   if a.Quotes[slot]and not held then a.Quotes[slot]=nil;a.ReplenishAt[slot]=e.Time+replenish end
   local tick=math.max(1,math.round(center-side*(spread+(depth-1)*math.max(1,math.floor(stress)))))
   local opposing=side==1 and b.Asks[1]or b.Bids[1]
   if opposing then tick=side==1 and math.max(1,math.min(tick,opposing.Price-1))or math.max(tick,opposing.Price+1)end
   local age=held and e.Time-held.Time or math.huge
   local eligible=depth<=activeDepth
   -- Keep normal FIFO/resting behavior, but withdraw materially mispriced risk on a value move.
   local stale=held and math.abs(held.Price-tick)>=reprice and (held.Price-market.Fair)*side>=math.max(2,spread)
   if held and (stale or age>=minRest and (not eligible or math.abs(held.Price-tick)>=reprice))then
    e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil
   end
   if eligible and not held and e.Time>=(a.ReplenishAt[slot]or 0)then
    local size=math.max(1,math.floor(a.Size*sizeMultiplier*liquidity*(1+(depth-1)*.15)*(1-inventory/a.Limit*side*.8)))
    -- Fit the quote to remaining buying power instead of rejecting the whole larger quote.
    -- This includes all working orders; no new capital or inventory allowance is created.
    if not e:Exposure(account,a.Key,side,size) then
     local lo,hi=0,size
     while lo<hi do
      local mid=math.ceil((lo+hi)/2)
      if e:Exposure(account,a.Key,side,mid) then lo=mid else hi=mid-1 end
     end
     size=lo
    end
    if size>0 then
     local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",Price=tick*c.Tick,Expires=e.Time+minRest*6})
     if ok and result.Remaining>0 then a.Quotes[slot]=result.Id end
    end
   end
  end
 end
end
-- One small position at a time. Every fill goes through the shared finite book.
-- Profit-taking rests as real liquidity; stops and timed exits cannot reverse the position.
function Participants:_scalper(a)
 self:_publicInformation(a)
 local e,r=self.Engine,self.Random local b=e.Books[a.Key] local s=self.Config.Scalper
 local account=e.Accounts[a.Id] local p=account.Positions[a.Key]
 if p then
  if a.PositionId~=p.Id then
   a.PositionId=p.Id;a.OpenedAt=e.Time
   e:CancelAll(a.Id,a.Key) -- Cancel any unfilled entry remainder before managing the exit.
  end
  if p.Triggered or account.Liquidating then e:CancelAll(a.Id,a.Key);return end
  if e.Time-a.OpenedAt>=a.MaxHold or b.Spec.CloseOnly or account.Locked then
   e:CancelAll(a.Id,a.Key)
   if BotExitRetry.Ready(e,account,a.Key,p)then
    local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=-p.Direction,Quantity=p.Quantity,Type="Market",ReduceOnly=true})
    if not ok or result.Filled==0 then BotExitRetry.Attempted(e,account,a.Key,p)end
   end
   return
  end
  -- Keep the target's queue priority until filled, stopped, or the holding time expires.
  if not next(account.OpenOrders) then
   local target=math.max(1,math.round(p.Entry/b.Spec.Tick)+p.Direction*a.Target)*b.Spec.Tick
   e:Submit(a.Id,{Contract=a.Key,Direction=-p.Direction,Quantity=p.Quantity,Type="Limit",Price=target,ReduceOnly=true})
  end
  return
 end
 if a.PositionId then
  e:CancelAll(a.Id,a.Key);a.PositionId=nil;a.OpenedAt=nil
  a.ReadyAt=e.Time+a.Cooldown*r:Range(0.75,1.25)
 end
 if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 if e.Time<a.ReadyAt or next(account.OpenOrders) then return end
 e:_pruneBook(b)
 local quote=Signals.Quote(self,a.Key);local bid,ask=quote.Bid,quote.Ask
 if not bid or not ask then return end
 local spread=ask-bid
 if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then return end
 local signals=self.Config.BotSignals
 local last=b.Last or b.Reference local previous=b.Recent[math.max(1,#b.Recent-a.Lookback)] or last
 local move=(last-previous)/math.max(1,b.Volatility*2)
 local policy=a.PolicyVersion and self.Config.BotPopulation
 local signal=a.Bias*(policy and .2 or 1)+r:Noise()*(policy and policy.ScalperNoise or 1)+(a.Style=="Momentum" and move or -move)
 if signals then
  -- Costs constrain the achievable target; they are not added to the required price move.
  if a.Target<spread+s.MaxSlippageTicks+signals.ScalperProfitBufferTicks then return end
  local seconds=math.clamp(a.Lookback,signals.ScalperSeconds[1],signals.ScalperSeconds[2])
  local window=Signals.Window(self,a.Key,seconds,signals.ConfirmationSeconds)
  if not window then return end
  if a.Style=="Reversion"then
   local side=Signals.Reversal(self,a.Key,window,spread,signals.ScalperDeviationTicks,signals.ReversalTicks)
   if not side then return end
   signal=side*math.max(1,a.EntryThreshold or .2)
  else
   local required=math.max(signals.ScalperMinMoveTicks,spread*.5,b.Volatility*signals.ScalperVolatilityMultiplier)
   if math.abs(window.Move)<required or window.Move*window.RecentMove<0 then return end
   signal=window.Move/math.max(1,b.Volatility*2)
  end
 elseif policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then return end
 if math.abs(signal)<(a.EntryThreshold or .2) then return end
 local side=signal>0 and 1 or -1
 local aggressive=r:Next()<s.AggressiveChance
 -- A marketable limit caps entry slippage; passive entries join the best quote.
 local tick=aggressive and (side==1 and ask+s.MaxSlippageTicks or bid-s.MaxSlippageTicks)
  or (side==1 and bid or ask)
 local size=self:_fit(a,side,a.Size);if size<1 then return end
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",
  Price=math.max(1,tick)*b.Spec.Tick,StopTicks=a.Stop,Expires=e.Time+a.Patience})
 if ok then
  a.ReadyAt=e.Time+a.Cooldown
  if result.Filled>0 then
   e:CancelAll(a.Id,a.Key)
   local held=account.Positions[a.Key]
   if held then a.PositionId=held.Id;a.OpenedAt=e.Time end
  end
 end
end
function Participants:_trader(a)
 self:_publicInformation(a)
 local e=self.Engine local b=e.Books[a.Key] local r=self.Random local c=b.Spec
 local account=e.Accounts[a.Id]
 if b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 if account.Locked or account.Liquidating or account.Positions[a.Key] and account.Positions[a.Key].Triggered then return end
 if r:Next()<0.25 then return end -- varied inactivity, even around news
 local last=b.Last or b.Reference local quote=Signals.Quote(self,a.Key)
 local signals=self.Config.BotSignals
 if signals and a.Kind=='Reversion'then
  local window=Signals.Window(self,a.Key,signals.ReversionSeconds,signals.ConfirmationSeconds)
  -- Warmup may block entries, but must never block reducing an existing position.
  a.Belief=window and window.Mean or last
 elseif signals and a.Kind=='Protective'then
  -- Estimate from publicly executable quotes, with independent observation error.
  a.Belief=quote.Value+r:Noise()*self.Regime.Volatility*c.Scale*signals.FairNoiseTicks
 elseif not(a.PolicyVersion and a.Kind=='Value')then
  a.Belief+=(quote.Value-a.Belief)*r:Range(0.02,0.18)+r:Noise()*self.Regime.Volatility*c.Scale*0.6
 end
 local p=account.Positions[a.Key] local inventory=p and p.Quantity*p.Direction or 0
 local recent=b.Recent local previous=recent[math.max(1,#recent-(a.Lookback or r:Int(8,35)))] or last
 local momentum=(last-previous)/math.max(3,b.Volatility*8)
 local edge=(a.Belief-last)/math.max(4,b.Volatility*8)
 local signal=a.Bias+r:Noise()*1.3-inventory/a.Limit*1.8
 if a.Kind=="Momentum" then signal+=momentum*r:Range(0.5,1.4)
 elseif a.Kind=="Value" then
  if a.PolicyVersion then
   local bid,ask=quote.Bid,quote.Ask;if not bid or not ask then return end
   if math.abs(a.Belief-last)<(ask-bid)/2+a.EntryBuffer then return end
   signal=edge*a.SignalWeight+a.Bias*.2+r:Noise()*.2-inventory/a.Limit*1.8
  else signal+=edge*r:Range(0.6,1.5)end
 elseif a.Kind=="Reversion" then signal-=momentum*r:Range(0.6,1.6) signal+=edge*0.3
 elseif a.Kind=="Protective" then signal+=edge*0.4 end
 if math.abs(signal)<(a.EntryThreshold or r:Range(0.1,0.55)) then return end
 local side=signal>0 and 1 or -1 local size=r:Int(1,a.Size)
 local reducing=false
 if signals and a.Kind=="Reversion"then
  if p and side==-p.Direction then
   -- Confirmation applies to new risk, never to an exit; an unconfirmed exit cannot reverse.
   size=math.min(size,p.Quantity);reducing=true
  else
   local bid,ask=quote.Bid,quote.Ask;if not bid or not ask then return end
   local window=Signals.Window(self,a.Key,signals.ReversionSeconds,signals.ConfirmationSeconds)
   if Signals.Reversal(self,a.Key,window,ask-bid,signals.ReversionDeviationTicks,signals.ReversalTicks)~=side then return end
  end
 end
 local aggressive=r:Next()<a.Aggression
 if a.Kind=="Whale" then
  if a.Parent>0 then side=a.ParentSide size=math.min(a.Parent,r:Int(4,math.max(5,math.floor(a.Size/3)))) a.Parent-=size
  else
   size=r:Int(math.floor(a.Size/2),a.Size)
   if r:Next()<0.55 then a.Parent=size*r:Int(2,4) a.ParentSide=side size=math.min(a.Parent,r:Int(4,12)) a.Parent-=size end
  end
  aggressive=r:Next()<0.8
 end
 if r:Next()<0.45 then
  local stale={}
  for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o and e.Time-o.Time>=math.max(12,a.Patience)then table.insert(stale,id)end end
  table.sort(stale);for _,id in ipairs(stale)do e:Cancel(a.Id,id)end
 end
 if not reducing then size=self:_fit(a,side,size)end;if size<1 then return end
 local request={Contract=a.Key,Direction=side,Quantity=size,Type=aggressive and "Market" or "Limit",ReduceOnly=reducing,Expires=e.Time+a.Patience*r:Range(0.5,1.5)}
 if not aggressive then
  local distance=r:Int(1,math.max(2,math.floor(3+self.Regime.Volatility*3)))
  request.Price=math.max(1,math.round(last-side*distance))*c.Tick
 end
 if a.Kind=="Protective" or (a.Kind~="Maker" and r:Next()<0.16) then request.StopTicks=a.Stop request.TargetTicks=a.Target end
 e:Submit(a.Id,request)
end
function Participants:Step()
 local e=self.Engine local r=self.Random
 -- Clear every legacy private entry before any participant can match it this step.
 for _,a in ipairs(self.Agents)do if not e.Books[a.Key].Spec.CloseOnly then self:_publicInformation(a)end end
 e:AdvanceClock(self.Config.StepSeconds)
 if e.Time>=self.NextRegime then self:_regime() end
 if self.Config.NewsFrequency>0 and e.Time>=self.NextNews then
  local sign=r:Next()<0.5 and 1 or -1
  local magnitude=r:Range(8,40)*self.Config.Volatility
  for _,key in ipairs(self.Config.ContractOrder) do
   if e.Books[key].Spec.CloseOnly then continue end
   local m=self.Markets[key] local shock=sign*magnitude*e.Books[key].Spec.Scale*r:Range(0.4,1.5)
   m.Anchor+=shock m.Impulse+=shock*0.1
  end
  self.News=(sign>0 and "Optimistic" or "Cautious").." synthetic outlook"
  self.NewsUntil=e.Time+r:Range(20,55) self.NextNews=e.Time+r:Range(140,420)/self.Config.NewsFrequency
  table.insert(self.Events,{Step=e.Step,Kind="News",Name=self.News,Direction=sign}) if #self.Events>40 then table.remove(self.Events,1) end
 end
 if e.Time>=self.NextBeliefs then
  for _,key in ipairs(self.Config.ContractOrder) do
   if e.Books[key].Spec.CloseOnly then continue end
   local m=self.Markets[key] local c=e.Books[key].Spec
   m.Anchor+=self.Regime.Trend*self.Direction*c.Scale+r:Noise()*self.Regime.Volatility*self.Config.Volatility*c.Scale*0.16
   m.Fair+=(m.Anchor-m.Fair)*0.025+m.Impulse*0.06
   m.Impulse*=0.96
   m.Fair=math.clamp(m.Fair,e.Books[key].Reference*0.6,e.Books[key].Reference*1.4)
   e.Books[key].FairReference=math.round(m.Fair)
  end
  self.NextBeliefs=e.Time+1
 end
 if self.Config.BotSignals then for _,key in ipairs(self.Config.ContractOrder)do Signals.Sample(self,key)end end
 for _,a in ipairs(self.Agents) do
  if e.Books[a.Key].Spec.CloseOnly then continue end
  if not a.Retiring then self:_observe(a)end
  if not a.Retired and e.Time>=a.Next then
   local repairing=(a.PolicyVersion or a.Retiring)and self:_repairRisk(a)
   if not repairing then
    if a.Kind=="Maker" then self:_maker(a) elseif a.Kind=="Reserve"then self:_reserve(a)elseif a.Kind=="Scalper" then self:_scalper(a)
    elseif a.Kind=='Liquidity'and self.Config.BotLiquidity then BotLiquidity.Step(self,a)else self:_trader(a) end
   end
   local delay=a.Speed*r:Range(0.45,1.65)/self.Regime.Activity
   if a.Kind=="Maker" then delay*=self.Config.MakerDecisionMultiplier or 1 end
   if a.Kind=='Liquidity'and self.Config.BotLiquidity then delay=math.min(delay,self.Config.BotLiquidity.DecisionSeconds)end
   if a.Kind=="Whale" then delay=a.Parent>0 and r:Range(1.5,6)*(a.PolicyVersion and self.Config.BotPopulation.WhaleActivityScale or 1) or delay/math.max(0.0001,self.Config.WhaleFrequency) end
   if repairing then delay=r:Range(2,5)end
   a.Next=e.Time+delay
   e:ProcessStops()
  end
 end
 e:ProcessPlayerOrders()
end
return Participants
]====]):sub(2),Hash=([====[!5ab21a9a2ec4587906f2984f467634f94098327c80966ee5d192c2db466d006d]====]):sub(2),ExpectedHash=([====[!b9677f43e8c45881910670bd3bdbcdce925a69698b6f4555373df12ce53b6423]====]):sub(2)}
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
-- V18 persists the strategy-only policy and time-based signal histories. Older engines must
-- not resume these checkpoints with different entry rules. This migration never funds bots.
-- V19 archives settled legacy books and accounts outside the active simulation.
-- Their cash/equity/volume remain in the audit ledger; older writers must fail closed.
-- V20 removes private reversal signals and adds passive liquidity risk controls.
-- Restore changes policy only; balances, live orders and positions are preserved until the next decision.
-- V21 limits trading strategies to public data and retires saved private entry intent.
local Checkpoint={Version=21,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true,[17]=true,[18]=true,[19]=true,[20]=true,[21]=true}}
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
 local e={Accounts={},Books={},Orders={},Profiles=take(engine.Profiles or {}),MarketRetirement=take(engine.MarketRetirement)}
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
 local information=currentConfig.BotInformationVersion or 0
 assert((config.BotInformationVersion or 0)<=information,'Cannot downgrade bot information policy')
 config.BotInformationVersion=information>0 and information or nil
 local retirement=currentConfig.MarketRetirementVersion or 0
 assert((config.MarketRetirementVersion or 0)<=retirement,'Cannot downgrade market retirement policy')
 config.MarketRetirementVersion=retirement>0 and retirement or nil
 local savedSignals=config.BotSignals and config.BotSignals.Version or 0
 local currentSignals=currentConfig.BotSignals and currentConfig.BotSignals.Version or 0
 assert(savedSignals<=currentSignals,"Cannot downgrade bot signal policy")
 if savedSignals<currentSignals then config.BotSignals=clone(currentConfig.BotSignals)end
 local savedLiquidity=config.BotLiquidity and config.BotLiquidity.Version or 0
 local currentLiquidity=currentConfig.BotLiquidity and currentConfig.BotLiquidity.Version or 0
 assert(savedLiquidity<=currentLiquidity,'Cannot downgrade bot liquidity policy')
 if savedLiquidity<currentLiquidity then config.BotLiquidity=clone(currentConfig.BotLiquidity)end
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
 engine.MarketRetirement=clone(data.MarketRetirement)
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
 require(script.Parent.LegacyRetirement).Apply(engine,population)
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
]====]):sub(2),Hash=([====[!a51c482c8e3540eaa8da164f65edf49abce0a2a589759e451656ca1651e1fc39]====]):sub(2),ExpectedHash=([====[!1da1e5ca4b957c0ee5c7f52c0a7dc743e682124dd82bdef82e430485f49a6427]====]):sub(2)}
local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end
for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Bad release "..path);if item.ExpectedHash then assert(instance and instance:IsA("ModuleScript") and (hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash),"Source changed: "..path)else assert(not instance or instance:IsA("ModuleScript") and hash(instance.Source)==item.Hash,"New module collision: "..path)end end
local history=game:GetService("ChangeHistoryService");history:SetWaypoint("Before bot fairness fix")
local names={};for path in pairs(release)do table.insert(names,path)end;table.sort(names)
local rollback={};local installed={}
local ok,err=pcall(function()for _,path in ipairs(names)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new("ModuleScript");instance.Name=name;table.insert(rollback,{Instance=instance,New=true});instance.Source=item.Source;instance.Parent=parent else table.insert(rollback,{Instance=instance,Source=instance.Source});instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Verification failed: "..path);installed[path]=item.Hash end end)
if not ok then for i=#rollback,1,-1 do local row=rollback[i];if row.New then row.Instance:Destroy()else row.Instance.Source=row.Source end end;error(err)end
history:SetWaypoint("Passive liquidity, public reversal signals and bounded bot risk")
return {Installed=installed,Count=#names,Published=false,Saved=false}
