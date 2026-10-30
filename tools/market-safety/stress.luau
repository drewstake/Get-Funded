-- Adversarial detached simulation. No production or Studio writes.
local fs=require('@lune/fs');local serde=require('@lune/serde')
local C=require('./candidate/MarketConfig');local E=require('./candidate/MarketEngine')
local P=require('./candidate/Participants');local F=require('./candidate/FundedAccounts')
local Safety=require('./candidate/MarketSafety');local Policy=require('./candidate/PlayerExecution')
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local report={Scope='Detached, current production population and matching',Scenarios={}}
local selected=require('@lune/process').args[1]
local output=__OUTPUT__
local function run(seed,mode,side,seconds)
 if selected and selected~=mode then return end
 local started=os.clock();local c=copy(C);local e=E.new(c,seed);local p=P.new(e)
 for _=1,480 do p:Step()end
 local actors={};for i=1,(mode=='multi-owner'and 8 or 1)do
  local a=e:AddAccount('attacker:'..i,i==1 and 130000 or 500000000,100000,.8,true)
  if mode=='rich'then a.Base=500000000;a.Balance=a.Base end
  table.insert(actors,a)
 end
 local initial={};for _,key in ipairs(c.ContractOrder)do initial[key]=e.Books[key].Last end
 local stats={Seed=seed,Mode=mode,Direction=side,SimulatedSeconds=seconds,Accepted=0,Rejected=0,Closed=0,
  MaxPlayerContracts=0,MaxReserveContracts=0,MinReserveEquity=math.huge,MaxReserveDepleted=0,Trades=0,Prices={},Players={}}
 local original=e._trade
 e._trade=function(self,b,incoming,resting,qty)
  assert(Policy.Allows(self,b,resting.Price,incoming.Direction),'Trade escaped execution/rolling bands')
  original(self,b,incoming,resting,qty);stats.Trades+=1
  for _,o in ipairs({incoming,resting})do local a=self.Accounts[o.Owner];local pos=a.Positions[b.Key]
   if pos and a.Player then stats.MaxPlayerContracts=math.max(stats.MaxPlayerContracts,pos.Quantity);assert(pos.Quantity<=c.MarketSafety.PlayerContracts,'Player exceeded exposure cap')end
   if pos and a.ReserveMarket then stats.MaxReserveContracts=math.max(stats.MaxReserveContracts,pos.Quantity);assert(pos.Quantity<=c.MarketSafety.ReserveContracts,'Reserve exceeded inventory cap')end
  end
 end
 for i=1,seconds/c.StepSeconds do
  if i%16==1 then
   for _,a in ipairs(actors)do for _,key in ipairs(c.ContractOrder)do
    local b=e.Books[key];local pos=a.Positions[key];local tick=(b.Last or b.Reference)
    if pos and (mode=='cycle'or mode=='passive')and i%240==1 then
     local ok=F.Perform(e,a.Id,{Action='Close',Contract=key});if ok then stats.Closed+=1 end
    elseif not(pos and pos.Triggered)then
     e:CancelAll(a.Id,key)
     local qty=math.min(e:OrderCapacity(a,key,side),mode=='multi-owner'and 40 or 200)
     if qty>0 then
      local kind=mode=='passive'and 'Limit'or 'Market'
      local req={Contract=key,Direction=side,Quantity=qty,Type=kind,Execution='Sliced',Price=kind=='Limit'and(tick+side*3)*b.Spec.Tick or nil}
      -- Splitting/cancel spam uses the same real account and execution window.
      for _=1,4 do local ok,result=e:Submit(a.Id,req)
       if ok then stats.Accepted+=1;if e.Orders[result.Id]and not e.Orders[result.Id].ReduceOnly then e:Cancel(a.Id,result.Id)end else stats.Rejected+=1 end
      end
     end
    end
   end end
  end
  p:Step()
  if i%120==0 then
   local depleted=0
   for _,agent in ipairs(p.Agents)do if agent.Kind=='Reserve'then local ac=e.Accounts[agent.Id];local equity=e:Summary(ac).Equity
    stats.MinReserveEquity=math.min(stats.MinReserveEquity,equity);if equity<=0 then depleted+=1 end
   end end
   stats.MaxReserveDepleted=math.max(stats.MaxReserveDepleted,depleted)
   assert(depleted==0,'Attack depleted a reserve bot')
   e:Audit()
  end
 end
 for _,a in ipairs(actors)do
  for key in pairs(a.Positions)do assert(F.Perform(e,a.Id,{Action='Close',Contract=key}))end
 end
 local remaining
 for _=1,2400 do
  p:Step();remaining=0;for _,a in ipairs(actors)do for _,pos in pairs(a.Positions)do remaining+=pos.Quantity end end
  if remaining==0 then break end
 end
 stats.RemainingAfterClose=remaining
 if remaining>0 then
  local debug={Stats=stats,Players={},Markets={}}
  for _,a in ipairs(actors)do debug.Players[a.Id]=e:Snapshot(a.Id,'BX','1m',false);debug.Players[a.Id].Candles=nil end
  for _,key in ipairs(c.ContractOrder)do local b=e.Books[key];local lo,hi=Safety.Bounds(e,b)
   local row={Last=b.Last,Low=lo,High=hi,BidDepth=Policy.Liquidity(e,b,-1),AskDepth=Policy.Liquidity(e,b,1),BotPositions={}};debug.Markets[key]=row
   for _,agent in ipairs(p.Agents)do if agent.Key==key then local ac=e.Accounts[agent.Id];local pos=ac.Positions[key]
    if pos then table.insert(row.BotPositions,{Id=ac.Id,Kind=agent.Kind,Equity=e:Summary(ac).Equity,Position=pos})end
   end end
  end
  fs.writeFile(output..'/stress-failure.json',serde.encode('json',debug,true))
 end
 assert(remaining==0,'Attack left a player unable to exit')
 for _,a in ipairs(actors)do table.insert(stats.Players,{Id=a.Id,Balance=a.Balance,Profit=a.Realized})end
 for _,key in ipairs(c.ContractOrder)do local b=e.Books[key];stats.Prices[key]={Start=initial[key]*b.Spec.Tick,Finish=b.Last*b.Spec.Tick,BidContracts=Policy.Liquidity(e,b,-1),AskContracts=Policy.Liquidity(e,b,1)}end
 stats.Audit=e:Audit();stats.ComputeSeconds=os.clock()-started
 table.insert(report.Scenarios,stats);fs.writeFile(output..'/stress-results.json',serde.encode('json',report,true))
 print('PASS',mode,side,'max player',stats.MaxPlayerContracts,'max reserve',stats.MaxReserveContracts,'lowest reserve equity',stats.MinReserveEquity,'remaining',remaining,'seconds',stats.ComputeSeconds)
end
run(177,'buy',1,1800)
run(731,'sell',-1,1800)
run(919,'cycle',1,1800)
run(101,'passive',-1,1800)
run(4141,'multi-owner',1,1800)
run(193,'rich',1,1800)
