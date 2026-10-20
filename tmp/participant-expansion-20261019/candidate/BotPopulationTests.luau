local C=require("./MarketConfig")
local E=require("./MarketEngine")
local P=require("./Participants")
local CP=require("./WorldCheckpoint")
local Policy=require("./BotPopulation")
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
    assert(n==390 and sum==204000000 and styles.Momentum==36 and styles.Reversion==36);total+=sum
   end
   assert(total==612000000 and #p.Agents==1170)
   local n=0;for _ in pairs(nextTimes)do n+=1 end;assert(n>1150)
   n=0;for _ in pairs(observations)do n+=1 end;assert(n>1150)
   local e2=E.new(clone(C),seed);local p2=P.new(e2)
   equal(CP.Capture(e,p),CP.Capture(e2,p2));e:Audit()
  end
  return 'Three seeds: 1170 bots, $612M, 36/36 scalpers per market; independent reproducible schedules'
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
  local funded=require("./FundedAccounts").new(e,require("./ProgressionConfig"),c)
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
  return 'V14→V23 migration is pure on input, no trades on restore, idempotent funding and exact replay'
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
