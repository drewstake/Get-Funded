-- Offline forensic replay. This harness cannot reach a production service.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local env=require('../bot-population/environment')
local Http=env.game:GetService('HttpService')
local CP=require('../bot-population/proposed/WorldCheckpoint')
local Config=require('../bot-population/proposed/MarketConfig')
local function decode(path)
 local data=serde.decode('json',fs.readFile(path))
 local function restore(v)
  if type(v)=='string' and v:sub(1,15)=='__forensic_num:' then return assert(tonumber(v:sub(16)))end
  if type(v)=='table'then for k,x in pairs(v)do v[k]=restore(x)end end
  return v
 end
 return restore(data)
end
local before=decode('backups/candle-investigation-20261015/private-before-local.json').Snapshot
local actual=decode('backups/candle-investigation-20261015/private-latest-local.json').Snapshot
local e,p=CP.Restore(before,Config)
local start=e.Time
local actualCandles={}
for _,c in ipairs(actual.Engine.Books.BX.Candles['1m'])do actualCandles[c.Time]=c end
local agents={}
for _,a in ipairs(p.Agents)do agents[a.Id]=a end
local function owner(id)local a=agents[id];return a and {Kind=a.Kind,Id=id}or{Kind=e.Accounts[id].Player and 'Player' or 'House'}end
local findings={Start=start,Target=1377240,Outliers={},Compared=0,Matched=0,Events={}}
local baseTrade=e._trade
e._trade=function(self,b,incoming,resting,qty)
 if b.Key=='BX' and math.abs(resting.Price-(b.Last or resting.Price))*b.Spec.Tick>=8 then
  table.insert(findings.Outliers,{Time=e.Time,TradeId=e.NextTrade+1,From=b.Last*b.Spec.Tick,To=resting.Price*b.Spec.Tick,Qty=qty,
   Fair=b.FairReference*b.Spec.Tick,Regime=p.Regime.Name,Incoming=owner(incoming.Owner),Resting=owner(resting.Owner),
   Order={Id=incoming.Id,Time=incoming.Time,Direction=incoming.Direction,Type=incoming.Type,Original=incoming.Original,Remaining=incoming.Remaining,Protection=incoming.Protection},
   RestingOrder={Id=resting.Id,Time=resting.Time,Original=resting.Original,Remaining=resting.Remaining,Protection=resting.Protection}})
 end
 return baseTrade(self,b,incoming,resting,qty)
end
local lastCompared=math.floor(start/60)*60
local n=0
while e.Time<1377240 do
 p:Step();n+=1
 local candles=e.Books.BX.Candles['1m'];local closed=candles[#candles-1]
 if closed and closed.Time>lastCompared then
  lastCompared=closed.Time;local real=actualCandles[closed.Time]
  if real then
   findings.Compared+=1;local same=true
   for _,k in ipairs({'Open','High','Low','Close','Volume'})do if real[k]~=closed[k]then same=false end end
   if same then findings.Matched+=1 elseif not findings.FirstDivergence then findings.FirstDivergence={Time=closed.Time,Actual=real,Replay=closed};print('First divergence at',closed.Time)end
  end
 end
 if n%4000==0 then
  print('Steps',n,'SimTime',e.Time,'Matched',findings.Matched,'Compared',findings.Compared,'Outliers',#findings.Outliers)
  fs.writeFile('output/candle-investigation-20261015/replay-progress.json',serde.encode('json',{Steps=n,Time=e.Time,Compared=findings.Compared,Matched=findings.Matched,Outliers=#findings.Outliers,FirstDivergence=findings.FirstDivergence}))
 end
end
findings.Finished=e.Time;findings.Events=p.Events
findings.Candles={}
for _,c in ipairs(e.Books.BX.Candles['1m'])do if c.Time>=1377060 then table.insert(findings.Candles,c)end end
fs.writeFile('output/candle-investigation-20261015/replay-result.json',serde.encode('json',findings))
print('Replay complete',findings.Matched,findings.Compared,#findings.Outliers)
