local fs=require('@lune/fs')
local serde=require('@lune/serde')
local E=require('./modules/MarketEngine')
local d=serde.decode('json',fs.readFile('output/bot-investigation-20261014/live-evidence.json'))
local c=d.Config;c.ContractOrder={'BX','BT','BG'}
local e=E.new(c,1)
local result={FlatPositiveBalanceBlockedAtOne=0,FlatScalpersBlockedAtConfiguredSize=0,ScalpersThatCouldTradeOneButRequestTwo=0,Checks=0}
for _,b in ipairs(d.Bots)do if b.Inventory==0 then
 local a=e:AddAccount(b.Id,b.Base,b.Limit,b.Risk,false);a.Balance=b.Balance;a.Realized=b.Realized
 local one=e:Exposure(a,b.Key,1,1)
 local full=e:Exposure(a,b.Key,1,b.Size)
 assert(one==(b.CapacityFlat>=1),'One-contract classification mismatch')
 result.Checks+=1
 if b.Balance>0 and not one then result.FlatPositiveBalanceBlockedAtOne+=1 end
 if b.Kind=='Scalper'and not full then result.FlatScalpersBlockedAtConfiguredSize+=1;if one then result.ScalpersThatCouldTradeOneButRequestTwo+=1 end end
end end
fs.writeFile('output/bot-investigation-20261014/capacity-probes.json',serde.encode('json',result,true))
print(serde.encode('json',result,true))
