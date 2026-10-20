-- Detached regression fixtures. No remote calls or DataStore writes.
local C=require("./MarketConfig")
local E=require("./MarketEngine")
local P=require("./Participants")
local CP=require("./WorldCheckpoint")
local R=require("./LegacyRetirement")
local Refresh=require("./BotRefresh")
local Tests={}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs: '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function near(a,b)assert(math.abs(a-b)<.001,tostring(a)..' ~= '..tostring(b))end
local function count(t)local n=0;for _ in pairs(t)do n+=1 end return n end
local function fixture(player)
 local c=copy(C);c.ContractOrder={'BX','RTY'};c.Contracts.RTY=copy(c.LegacyContracts.RTY);c.Contracts.RTY.CloseOnly=nil
 c.BotPopulation=nil;c.PlayerExecution=nil;c.MakersPerInstrument=0;c.ParticipantsPerInstrument=0;c.WhalesPerInstrument=0;c.ScalpersPerInstrument=0;c.Reserve.Count=0
 local e=E.new(c,913);local p=P.new(e)
 local long=e:AddAccount('legacy:long',100000,10,.8,player)
 local short=e:AddAccount('legacy:short',100000,10,.8,false)
 for _,a in ipairs({long,short})do if not a.Player then table.insert(p.Agents,{Id=a.Id,Key='RTY',Kind='Maker',Next=0})end end
 local current=e:AddAccount('bot:ES:Maker:1',100000,10,.8,false)
 table.insert(p.Agents,{Id=current.Id,Key='BX',Kind='Maker',Next=1e12})
 e:AddAccount('untouched:player',100000,10,.8,true)
 local mark=c.Contracts.RTY.Last
 assert(e:Submit(short.Id,{Contract='RTY',Direction=-1,Quantity=2,Type='Limit',Price=mark}))
 assert(e:Submit(long.Id,{Contract='RTY',Direction=1,Quantity=2,Type='Market'}))
 assert(e:Submit(short.Id,{Contract='RTY',Direction=-1,Quantity=1,Type='Limit',Price=mark+10}))
 assert(e:Submit(current.Id,{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=c.Contracts.BX.Last-10}))
 e.Books.RTY.Last+=5;c.Contracts.RTY.CloseOnly=true
 e:Audit();return e,p,long,short,current
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Cash settlement preserves both sides, current orders, equity, tape and random state',function()
  local e,p,long,short,current=fixture();local before=CP.Capture(e,p)
  local equities={};for id,a in pairs(e.Accounts)do equities[id]=e:Summary(a).Equity end
  local currentBefore=copy(current);local player=copy(e.Accounts['untouched:player']);local arch=R.Apply(e,p)
  assert(#arch.Settlements==2 and #arch.Accounts==2 and #arch.Agents==2 and #arch.CancelledOrders==1)
  assert(#p.Agents==1 and p.Agents[1].Id==current.Id and #e.Config.ContractOrder==1)
  assert(not e.Books.RTY and not p.Markets.RTY and not e.Accounts[long.Id]and not e.Accounts[short.Id])
  for _,a in ipairs(arch.Accounts)do near(a.Balance,equities[a.Id]);assert(not next(a.Positions)and not next(a.OpenOrders));assert(not a.CompletedTrades)end
  equal(currentBefore,current);equal(player,e.Accounts[player.Id]);equal(before.Engine.Books.BX,CP.Capture(e,p).Engine.Books.BX)
  for _,k in ipairs({'Step','Time','NextOrder','NextTrade','NextPriority','TotalVolume','TradeHash'})do equal(before.Engine[k],e[k],k)end
  assert(before.Population.RandomState==p.Random.State);e:Audit()
 end)
 test('Previously refreshed positions settle against their accounting basis without new funding',function()
  local e,p,long,short=fixture()
  -- A previous refresh crystallized the first two ticks of P&L at unchanged base capital.
  for _,a in ipairs({long,short})do
   local pos=a.Positions.RTY;local basis=pos.Entry+2*e.Books.RTY.Spec.Tick
   a.StartingCapital=a.Base;a.NetCapitalAdjustments=0;a.PnlBaseline=(basis-pos.Entry)*pos.Direction*pos.Quantity*e.Books.RTY.Spec.Multiplier
   a.Balance=a.Base+a.PnlBaseline;pos.PnlEntry=basis
  end
  local l,s=e:Summary(long).Equity,e:Summary(short).Equity;R.Apply(e,p)
  near(long.Balance,l);near(short.Balance,s);near(long.Realized,3*2*e.Config.Contracts.RTY.Tick*e.Config.Contracts.RTY.Multiplier)
  assert(long.NetCapitalAdjustments==0 and short.NetCapitalAdjustments==0);e:Audit()
 end)
 test('Unexpected player legacy exposure closes without fabricated trades or reward callbacks',function()
  local e,p,long=fixture(true);local equity=e:Summary(long).Equity;local trades=long.Stats.Trades;local fills=copy(long.Fills)
  e.OnPositionClosed=function()error('Must not trigger rewards')end
  R.Apply(e,p);assert(e.Accounts[long.Id]==long and not next(long.Positions));near(long.Balance,equity)
  assert(long.Stats.Trades==trades and not long.CompletedTrades);equal(fills,long.Fills);near(long.Stats.UntrackedNet,long.Realized);e:Audit()
 end)
 test('Closed markets reject new bot and player exposure, including previously resting entries',function()
  local e,p,long,short=fixture()
  for _,id in ipairs({long.Id,'untouched:player'})do
   local ok,msg=e:Submit(id,{Contract='RTY',Direction=1,Quantity=1,Type='Market'})
   assert(not ok and tostring(msg):find('close%-only'))
  end
  for _,o in pairs(e.Orders)do if o.Contract=='RTY'then local available=e:_available(o);assert(available==0)end end
  local ok=e:Submit(long.Id,{Contract='RTY',Direction=-1,Quantity=1,Type='Limit',Price=e.Config.Contracts.RTY.Last+20,ReduceOnly=true});assert(ok)
  local n=e.NextOrder;p:_maker(p.Agents[1]);assert(e.NextOrder==n)
  R.Apply(e,p);assert(not e:Submit(short.Id,{Contract='RTY',Direction=1,Quantity=1,Type='Market'}));e:Audit()
 end)
 test('Invalid inventory and cross-market obligations fail before mutation',function()
  for _,mixed in ipairs({false,true})do
   local e,p,long=fixture()
   if mixed then long.Positions.BX=copy(long.Positions.RTY)else long.Positions.RTY.Quantity+=1 end
   local before=CP.Capture(e,p);assert(not pcall(R.Apply,e,p));equal(before,CP.Capture(e,p))
  end
 end)
 test('Archive stays frozen across steps, repeat migration and funding preview',function()
  local e,p=fixture();R.Apply(e,p);local before=copy(e.MarketRetirement);local saved=CP.Capture(e,p)
  R.Apply(e,p);equal(saved,CP.Capture(e,p))
  e.Config.BotPopulation={Capital={Maker=750000}}
  local plan=Refresh.Prepare(e,p,1,1);assert(plan.Receipt.Count==1)
  local preview=Refresh.Preview(e,p,plan);equal(before,preview.MarketRetirement)
  e.Config.BotPopulation=nil
  for _=1,200 do p:Step()end
  equal(before,e.MarketRetirement);assert(#p.Agents==1 and count(e.Books)==1);e:Audit()
 end)
 test('Fresh worlds never spawn closed-market participants',function()
  local c=copy(C);c.Contracts.RTY=copy(c.LegacyContracts.RTY);table.insert(c.ContractOrder,'RTY')
  local e=E.new(c,914);local p=P.new(e);assert(#p.Agents==1170)
  for _,a in ipairs(p.Agents)do assert(a.Key~='RTY')end
  R.Apply(e,p);assert(#e.Config.ContractOrder==3);e:Audit()
 end)
 return rows
end
function Tests.Captured(snapshot,steps,yieldStep)
 local old=copy(C);old.MarketRetirementVersion=nil
 local before,bp=CP.Restore(snapshot,old);local untouched=copy(snapshot)
 local e,p=CP.Restore(snapshot,C);equal(untouched,snapshot)
 assert(#p.Agents==1170 and #bp.Agents==1434 and #e.Config.ContractOrder==3 and count(e.Books)==3)
 local a=e.MarketRetirement;assert(#a.Accounts==264 and #a.Agents==264 and count(a.Markets)==6)
 for _,key in ipairs({'BX','BT','BG'})do equal(before.Books[key],e.Books[key],'book.'..key);equal(bp.Markets[key],p.Markets[key],'signals.'..key)end
 local players=0;for id,account in pairs(e.Accounts)do equal(before.Accounts[id],account,'account.'..id);if account.Player then players+=1 end end
 for _,account in ipairs(a.Accounts)do
  local prior=before.Accounts[account.Id];near(before:Summary(prior).Equity,account.Balance)
  for _,key in ipairs({'Base','StartingCapital','NetCapitalAdjustments','CapitalAdjustments','PnlBaseline','CompletedTrades'})do equal(prior[key],account[key],account.Id..'.'..key)end
 end
 local agents={};for _,agent in ipairs(bp.Agents)do agents[agent.Id]=agent end
 for _,agent in ipairs(p.Agents)do equal(agents[agent.Id],agent,'agent.'..agent.Id)end
 local after=CP.Capture(e,p)
 for _,key in ipairs({'Step','Time','Seed','NextOrder','NextTrade','NextPriority','TotalVolume','TradeHash','Profiles','Execution','RequestJournal','EligibilityRevision'})do equal(before[key],e[key],key)end
 assert(bp.Random.State==p.Random.State)
 local encoded=CP.Encode(after);local re,rp=CP.Restore(CP.Decode(encoded),C);equal(after,CP.Capture(re,rp),'roundtrip')
 assert(not pcall(CP.Restore,after,old),'Retirement downgrade accepted')
 local future=copy(after);future.Version=CP.Version+1;assert(not pcall(CP.Restore,future,C))
 local plan=Refresh.Prepare(e,p,(p.BotRefreshReceipt and p.BotRefreshReceipt.Sequence or 0)+1,1)
 assert(plan.Receipt.Count==1170);local preview=Refresh.Preview(e,p,plan);equal(a,preview.MarketRetirement);preview:Audit()
 local frozen=copy(a);local initialAudit=e:Audit();local start=os.clock()
 for i=1,steps or 120 do p:Step();rp:Step();if yieldStep and i%20==0 then yieldStep()end end
 equal(CP.Capture(e,p),CP.Capture(re,rp),'replay');equal(frozen,e.MarketRetirement,'frozen archive')
 for _,o in pairs(e.Orders)do assert(e.Books[o.Contract]and not e.Books[o.Contract].Spec.CloseOnly)end
 return {Success=true,SourceVersion=snapshot.Version,CheckpointVersion=encoded.Version,SourceStep=snapshot.Engine.Step,
  AgentsBefore=#bp.Agents,AgentsAfter=#p.Agents,BooksBefore=#before.Config.ContractOrder,BooksAfter=#e.Config.ContractOrder,
  AccountsBefore=#before.AccountOrder,AccountsAfter=#e.AccountOrder,ArchivedBots=#a.Accounts,SettledPositions=#a.Settlements,
  CancelledOrders=#a.CancelledOrders,PlayersUnchanged=players,FundingEligible=plan.Receipt.Count,SettlementPrices=(function()local prices={}for key,row in pairs(a.Markets)do prices[key]=row.Price end return prices end)(),
  RawBytes=encoded.RawBytes,PayloadBytes=#encoded.Payload,ReplaySteps=steps or 120,ReplaySeconds=os.clock()-start,
  ExactReplay=true,ExactRoundtrip=true,CurrentMarketsPreserved=true,RetiredEquityPreserved=true,ArchiveFrozen=true,
  AuditBefore=initialAudit,AuditAfter=e:Audit()}
end
return Tests
