local fs=require('@lune/fs')
local serde=require('@lune/serde')
local P=require('./modules/Participants')
local C=require('./modules/MarketConfig')
local results={}
for _,kind in ipairs({'Protective','Reversion'})do
 for _,trend in ipairs({-1,0,1})do
  for _,fresh in ipairs({false,true})do
   local account={Positions={},OpenOrders={},Locked=false}
   local last=23000
   local b={Spec=C.Contracts.BX,Last=last,Reference=last,Volatility=1,Recent=table.create(64,last),Bids={{Price=last-1}},Asks={{Price=last+1}}}
   local row={Kind=kind,TrendTicksPerDecision=trend,CurrentFairBelief=fresh,Decisions=10000,Submissions=0,Buy=0,Sell=0,BeliefLagSum=0,LagSamples=0}
   local e={Time=0,Accounts={probe=account},Books={BX=b}}
   function e:Exposure()return true end
   function e:Cancel()end
   function e:Submit(_,req)
    row.Submissions+=1;if req.Direction==1 then row.Buy+=1 else row.Sell+=1 end
    return true,{Filled=0,Remaining=req.Quantity}
   end
   local p=setmetatable({Engine=e,Config=C,Random=P.RNG.new(73521),Markets={BX={Fair=last}},Regime={Volatility=0}},P)
   local a={Id='probe',Key='BX',Kind=kind,Size=2,Limit=40,Bias=0,Belief=last,Aggression=.5,Stop=30,Target=60,Patience=12,Parent=0,ParentSide=1,Lookback=20,PolicyVersion=1,EntryThreshold=.85}
   for i=1,row.Decisions do
    e.Time=i*10;b.Last=last+i*trend;p.Markets.BX.Fair=b.Last
    table.insert(b.Recent,b.Last);table.remove(b.Recent,1);b.Bids[1].Price=b.Last-1;b.Asks[1].Price=b.Last+1
    if fresh then a.Belief=b.Last end
    p:_trader(a)
    if i>100 then row.BeliefLagSum+=b.Last-a.Belief;row.LagSamples+=1 end
   end
   row.MeanBeliefLagTicks=row.BeliefLagSum/row.LagSamples
   table.insert(results,row)
  end
 end
end
local data={Results=results,Notes='Synthetic decision-only probes: fair value equals trade price, no position or orders, zero bias, zero belief noise, normal decision noise. Price moves 1 tick per 10 simulated seconds with a 20-execution lookback. No simulated fills/P&L.'}
fs.writeFile('output/bot-diagnostics-20261018/direction-probes.json',serde.encode('json',data,true));print(serde.encode('json',data,true))
