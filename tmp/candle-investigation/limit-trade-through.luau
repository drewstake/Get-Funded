-- Detached reproduction of a reported live symptom; not a replay of the incident.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local E=require('../bot-population/proposed/MarketEngine')
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local c=copy(require('../bot-population/proposed/MarketConfig'))
c.Contracts.BX.Last=5848.5
local e=E.new(c,12345)
e:AddAccount('player',10000000,10000,.8,true)
e:AddAccount('seller',100000000,100000,.8,false)
e:AddAccount('buyer',100000000,100000,.8,false)
local b=e.Books.BX;b.FairReference=5848.5/c.Contracts.BX.Tick
assert(e:Submit('seller',{Contract='BX',Direction=-1,Type='Limit',Price=5848.5,Quantity=100}))
local ok,entry=e:Submit('player',{Contract='BX',Direction=1,Type='Market',Quantity=1})
assert(ok and entry.Filled==1,'Entry fixture failed')
e:CancelAll('seller')
local accepted,limit=e:Submit('player',{Contract='BX',Direction=-1,Type='Limit',Price=5848,Quantity=1})
assert(accepted and limit.Remaining==1 and not limit.Queued,'Sell fixture failed')
-- Fair value can change while an already accepted limit waits.
b.FairReference=5838/c.Contracts.BX.Tick
assert(e:Submit('seller',{Contract='BX',Direction=-1,Type='Limit',Price=5848.5,Quantity=1}))
local bought,result=e:Submit('buyer',{Contract='BX',Direction=1,Type='Market',Quantity=1})
assert(bought and result.Filled==1 and result.Average==5848.5,'Expected bot-to-bot trade above player limit')
assert(e.Orders[limit.Id]and e.Orders[limit.Id].Remaining==1,'Player limit unexpectedly filled')
e:Audit()
local report={Reproduction=true,HistoricalReplay=false,PlayerSellLimit=5848,InternalFairValue=5838,
 BotPurchasePrice=result.Average,PlayerSellStillWorking=true,PlayerContractsStillHeld=e.Accounts.player.Positions.BX.Quantity,
 Rule='Resting player ask skipped above fair + 20 ticks; bot ask has no equivalent guard.'}
fs.writeFile('output/candle-investigation-20261015/limit-trade-through-reproduction.json',serde.encode('json',report))
print(serde.encode('json',report))
