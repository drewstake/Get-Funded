-- Behavioral unit probes; no live/saved data and no network.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local P=require('./modules/Participants')
local E=require('./modules/MarketEngine')
local C=require('./modules/MarketConfig')
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local neutral={}
for _,kind in ipairs({'Protective','Reversion'})do
 for _,threshold in ipairs({.5,.85,1.2})do
  local config=clone(C);local last=23000
  local account={Positions={},OpenOrders={},Locked=false}
  local b={Spec=config.Contracts.BX,Last=last,Reference=last,Volatility=1,Recent=table.create(64,last),Bids={{Price=last-1}},Asks={{Price=last+1}}}
  local row={Kind=kind,Threshold=threshold,Decisions=10000,Submissions=0,Market=0,Limit=0,Buy=0,Sell=0,Protected=0}
  local e={Time=0,Accounts={probe=account},Books={BX=b},Seed=73521}
  function e:Exposure()return true end
  function e:Cancel()end
  function e:Submit(_,request)
   row.Submissions+=1;row[request.Type]+=1;if request.Direction==1 then row.Buy+=1 else row.Sell+=1 end
   if request.StopTicks then row.Protected+=1 end
   return true,{Filled=0,Remaining=request.Quantity}
  end
  local p=setmetatable({Engine=e,Config=config,Random=P.RNG.new(73521),Markets={BX={Fair=last}},Regime={Volatility=0}},P)
  local a={Id='probe',Key='BX',Kind=kind,Size=2,Limit=40,Bias=0,Belief=last,Aggression=.5,Stop=30,Target=60,Patience=12,Parent=0,ParentSide=1,Lookback=20,PolicyVersion=1,EntryThreshold=threshold}
  for _=1,row.Decisions do a.Belief=last;p:_trader(a)end
  table.insert(neutral,row)
 end
end
-- Verify exact scalper gating without changing RNG calls or decision code.
local scalper={}
for _,move in ipairs({0,1,2,3,4,5,6,7,8,10})do
 local config=clone(C);local e=E.new(config,73521);local p=P.new(e)
 for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
 local a;for _,agent in ipairs(p.Agents)do if agent.Kind=='Scalper'and agent.Key=='BX'then a=agent;break end end
 a.Style='Momentum';a.MinMove=3;a.EntryBuffer=4;a.EntryThreshold=.5;a.Lookback=20;a.Bias=0
 local b=e.Books.BX;local last=b.Last;b.Recent=table.create(64,last-move);b.Recent[64]=last;b.Volatility=1
 e:AddAccount('probe:buyer',1e7,1000,1,false);e:AddAccount('probe:seller',1e7,1000,1,false)
 assert(e:Submit('probe:buyer',{Contract='BX',Direction=1,Quantity=20,Type='Limit',Price=(last-1)*b.Spec.Tick}))
 assert(e:Submit('probe:seller',{Contract='BX',Direction=-1,Quantity=20,Type='Limit',Price=(last+1)*b.Spec.Tick}))
 local row={Move=move,Spread=2,RequiredMove=7,Decisions=1000,Gates={}}
 function p:DiagnosticGate(name)row.Gates[name]=(row.Gates[name]or 0)+1 end
 e.Submit=function()return true,{Filled=0,Remaining=1}end
 for _=1,row.Decisions do a.ReadyAt=0;p:_scalper(a)end
 table.insert(scalper,row)
end
local results={Neutral=neutral,Scalper=scalper,Notes='Neutral probes: flat position, zero bias, fair equals last, no recent price move, zero belief noise. Decision noise is unchanged. Scalper probes use spread 2, slippage allowance 1, entry buffer 4, MinMove 3.'}
fs.writeFile('output/bot-diagnostics-20261018/probes.json',serde.encode('json',results,true));print(serde.encode('json',results,true))
