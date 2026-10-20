local fs=require('@lune/fs')
local serde=require('@lune/serde')
local P=require('./modules/Participants')
local config=require('./modules/MarketConfig')
local results={}
for _,kind in ipairs({'Liquidity','Value','Momentum','Reversion','Protective','Whale','Scalper'})do
 local account={Positions={},OpenOrders={},Locked=false}
 local b={Spec=config.Contracts.BX,Last=23000,Reference=23000,Volatility=1,Recent=table.create(64,23000),Bids={{Price=22999}},Asks={{Price=23001}}}
 local row={Kind=kind,EligibleDecisions=10000,Submissions=0,Market=0,Limit=0,Buy=0,Sell=0}
 local e={Time=0,Accounts={probe=account},Books={BX=b}}
 function e:_pruneBook()end
 function e:Cancel()end
 function e:Submit(_,request)
  row.Submissions+=1;row[request.Type]+=1;if request.Direction==1 then row.Buy+=1 else row.Sell+=1 end
  return true,{Filled=0,Remaining=request.Quantity}
 end
 local p=setmetatable({Engine=e,Config=config,Random=P.RNG.new(73521),Markets={BX={Fair=23000}},Regime={Volatility=0.45}},P)
 local a={Id='probe',Key='BX',Kind=kind,Size=kind=='Whale'and 30 or 2,Limit=40,Bias=0,Belief=23000,Aggression=.5,Stop=30,Target=kind=='Scalper'and 6 or 60,Patience=12,Parent=0,ParentSide=1,ReadyAt=0,Cooldown=10,Style='Momentum',Lookback=6}
 for _=1,row.EligibleDecisions do a.Belief=23000;a.ReadyAt=0;if kind=='Scalper'then p:_scalper(a)else p:_trader(a)end end
 results[kind]=row
end
fs.writeFile('output/bot-investigation-20261014/decision-probes.json',serde.encode('json',{Conditions='Fixed price, fair value equals last, zero trend, zero inventory, no fills, eligible flat-account decisions. Generic belief reset to fair before every decision; normal belief noise still applies.',Results=results},true))
print(serde.encode('json',results,true))
