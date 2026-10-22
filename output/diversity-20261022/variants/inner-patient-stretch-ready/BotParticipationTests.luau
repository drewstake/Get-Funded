local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local H=require(script.Parent.BotParticipation)
local S=require(script.Parent.BotStats)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local function equal(a,b)
 assert(type(a)==type(b),'Type mismatch');if type(a)~='table'then assert(a==b,'Value mismatch '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end for k in pairs(b)do assert(a[k]~=nil,'Extra '..tostring(k))end
end
local function near(a,b)assert(math.abs(a-b)<.001,tostring(a)..' ~= '..tostring(b))end
local function fixture()
 local c=copy(C);local e=E.new(c,481);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(481),Agents={},Markets={BX={}}},P)
 local a=p:_agent('BX','Momentum',1);local d=p:_agent('BX','Value',1)
 local ac,dc=e.Accounts[a.Id],e.Accounts[d.Id]
 -- A balanced historical realized loss/profit fixture, with no fabricated trade in the test.
 ac.Realized=-100000;ac.Balance=ac.Base+ac.Realized;ac.CashFlow=-100000
 dc.Realized=100000;dc.Balance=dc.Base+dc.Realized;dc.CashFlow=100000
 e:Audit();return e,p,a,d,ac,dc
end
function T.Run()
 local out={};local function test(name,fn)local ok,err=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(err)})end
 test('Risk pause requires cooldown then a conserved transfer, preserving P&L and price',function()
  local e,p,a,d,ac,dc=fixture();local original=copy({Price=e.Books.BX.Last,Realized=ac.Realized,DonorPnl=dc.Realized,Volume=e.TotalVolume,Trades=e.NextTrade})
  H.Step(p,a);assert(a.RecoveryReadyAt>e.Time);H.Rebalance(p);near(ac.Balance,100000)
  e.Time=a.RecoveryReadyAt+31;H.Rebalance(p)
  near(ac.Balance,a.Budget*.9);near(ac.ParticipationCapitalNet,80000);near(dc.ParticipationCapitalNet,-80000)
  near(ac.Base+dc.Base,450000);assert(ac.ParticipationRecoveries==1 and a.ParticipationResumeAt>e.Time)
  equal(original,{Price=e.Books.BX.Last,Realized=ac.Realized,DonorPnl=dc.Realized,Volume=e.TotalVolume,Trades=e.NextTrade})
  assert(H.Step(p,a),'Resume must be staggered');e:Audit()
 end)
 test('No donor surplus means no cash creation, partial funding or false recovery',function()
  local e,p,a,d,ac,dc=fixture();d.Budget=dc.Balance
  H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p)
  assert(a.RecoveryReadyAt and not ac.ParticipationRecoveries);near(ac.Balance,100000);near(dc.Balance,350000);e:Audit()
 end)
 test('Player, house, archive, retired and other-market funds cannot recapitalize a bot',function()
  for _,flag in ipairs({'Player','House','Archive','Retiring','Market'})do
   local e,p,a,d,ac,dc=fixture()
   if flag=='Retiring'then d.Retiring=true elseif flag=='Market'then d.Key='BT'else dc[flag]=true end
   H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p);near(ac.Balance,100000);near(dc.Balance,350000)
  end
 end)
 test('Recovery closes through finite orders and never erases an unfilled position',function()
  local e,p,a,d,ac,dc=fixture();local b=e.Books.BX;local price=b.Reference*b.Spec.Tick
  assert(e:Submit(d.Id,{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=price}))
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Market'}))
  local volume=e.TotalVolume;H.Step(p,a);assert(ac.Positions.BX.Quantity==2 and e.TotalVolume==volume)
  e.Time=a.RecoveryReadyAt+31;H.Rebalance(p);assert(a.RecoveryReadyAt and not ac.ParticipationRecoveries)
  assert(e:Submit(d.Id,{Contract='BX',Direction=1,Quantity=2,Type='Limit',Price=price}))
  H.Step(p,a);assert(not ac.Positions.BX and e.TotalVolume==volume+2)
  e.Time+=31;H.Rebalance(p);assert(ac.ParticipationRecoveries==1);e:Audit()
 end)
 test('Existing triggered protection is preserved during recovery',function()
  local e,p,a,d,ac,dc=fixture();local price=e.Books.BX.Reference*e.Books.BX.Spec.Tick
  assert(e:Submit(d.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=price}))
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market',StopTicks=10}))
  ac.Positions.BX.Triggered='Stop loss';local pos=copy(ac.Positions);local n=e.NextOrder
  H.Step(p,a);equal(pos,ac.Positions);assert(e.NextOrder==n);e:Audit()
 end)
 test('Donor capital cannot consume margin reserved by open orders',function()
  local e,p,a,d,ac,dc=fixture();local price=e.Books.BX.Reference*e.Books.BX.Spec.Tick
  dc.Limit=1000;dc.Risk=.5;local qty=math.floor(dc.Balance*dc.Risk/e.Books.BX.Spec.Margin)
  assert(e:Submit(d.Id,{Contract='BX',Direction=1,Quantity=qty,Type='Limit',Price=price-10}))
  H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p)
  assert(not ac.ParticipationRecoveries and e:Exposure(dc,'BX',1,0));e:Audit()
 end)
 test('Unrealized profits alone are not recycled as spendable capital',function()
  local e,p,a,d,ac,dc=fixture();dc.Balance=d.Budget;dc.Realized=0
  local summary=e.Summary;e.Summary=function(self,account)local s=summary(self,account);if account==dc then s.Equity+=100000 end return s end
  H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p);assert(not ac.ParticipationRecoveries)
 end)
 test('Stats distinguish unknown activity, quotes, fills, cooldown, risk and insufficient capital',function()
  local e,p,a,d,ac,dc=fixture()
  assert(H.Inspect(e,a,e:Summary(ac))=='Risk paused')
  assert(H.Inspect(e,d,e:Summary(dc))=='Waiting')
  local price=e.Books.BX.Reference*e.Books.BX.Spec.Tick
  assert(e:Submit(d.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=price}))
  assert(H.Inspect(e,d,e:Summary(dc))=='Quoting')
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
  local state,recent,_,eligible=H.Inspect(e,a,e:Summary(ac));assert(state=='Risk paused'and recent and not eligible)
  assert(H.Inspect(e,d,e:Summary(dc))=='Trading');d.FlowCooldownUntil=e.Time+10;assert(H.Inspect(e,d,e:Summary(dc))=='Cooldown')
  ac.Balance=1;assert(H.Inspect(e,a,e:Summary(ac))=='Underfunded')
  local r=S.Capture(e,p);assert(r.Total.Trading==2 and r.Total.Active==0 and r.Total.Cooldown==1 and r.Total.Underfunded==1)
  e.Time+=301;local _,wasRecent=H.Inspect(e,d,e:Summary(dc));assert(not wasRecent)
 end)
 test('Expired or unfunded entry orders do not count as executable quotes',function()
  local e,p,a,d,ac,dc=fixture();local price=e.Books.BX.Reference*e.Books.BX.Spec.Tick
  assert(e:Submit(d.Id,{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=price-1,Expires=10}))
  e.Time=11;local _,_,quoting=H.Inspect(e,d,e:Summary(dc));assert(not quoting)
 end)
 test('A second loss cycle recovers again without erasing cumulative performance',function()
  local e,p,a,d,ac,dc=fixture();H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p)
  ac.Realized-=80000;ac.Balance-=80000;ac.CashFlow-=80000
  dc.Realized+=80000;dc.Balance+=80000;dc.CashFlow+=80000
  e.Time+=100;H.Step(p,a);e.Time=a.RecoveryReadyAt+31;H.Rebalance(p)
  assert(ac.ParticipationRecoveries==2);near(ac.Realized,-180000);near(ac.ParticipationCapitalNet,160000);e:Audit()
 end)
 test('V24 migration is read-only; recovery and fill telemetry continue exactly after checkpoint',function()
  local old=copy(C);old.BotParticipation=nil
  local e=E.new(old,411);local p=P.new(e);local snapshot=CP.Capture(e,p);snapshot.Version=24
  local before=copy(snapshot);local re,rp=CP.Restore(snapshot,C);equal(before,snapshot)
  for id,ac in pairs(e.Accounts)do near(ac.Balance,re.Accounts[id].Balance);equal(ac.Positions,re.Accounts[id].Positions)end
  local a=rp.Agents[1];a.RecoveryReadyAt=re.Time+400;re.Accounts[a.Id].LastBotFillAt=re.Time
  local saved=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(saved)),C)
  equal(saved,CP.Capture(rr,pr))
  for _=1,60 do rp:Step();pr:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local down=copy(C);down.BotParticipation=nil;assert(not pcall(CP.Restore,saved,down));assert(CP.Version==31)
 end)
 return out
end
return T