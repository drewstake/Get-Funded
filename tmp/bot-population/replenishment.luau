local E=require('./proposed/MarketEngine');local P=require('./proposed/Participants');local C=require('./proposed/MarketConfig')
local replenish=require('../../tools/ReplenishBotCapital');local fs=require('@lune/fs');local serde=require('@lune/serde')
local e=E.new(C,3);local p=P.new(e);local a,b
for _,agent in ipairs(p.Agents)do if not next(e.Accounts[agent.Id].Positions)then if not a then a=agent elseif not b then b=agent end end end
local ac,bc=e.Accounts[a.Id],e.Accounts[b.Id]
ac.Realized-=1000;ac.Balance=ac.Base+ac.Realized;bc.Realized+=1000;bc.Balance=bc.Base+bc.Realized
local original=ac.StartingCapital;a.Retiring=true
replenish(e,p,'retiring-check');assert(ac.NetCapitalAdjustments==0 and ac.Balance==original-1000)
a.Retiring=nil;local receipt=replenish(e,p,'capital-ledger-check')
assert(ac.StartingCapital==original and ac.NetCapitalAdjustments==1000 and #ac.CapitalAdjustments==1 and ac.Realized==-1000)
assert(ac.Base==original+1000 and ac.Balance==original)
assert(replenish(e,p,'capital-ledger-check')==receipt and #ac.CapitalAdjustments==1)
e:Audit();fs.writeFile('output/bot-population-20261014/replenishment-test.json',serde.encode('json',{Passed=true,Detail='Manual deposits preserve trading P&L, record funding, skip retiring agents and retry idempotently.'},true))
print('Manual replenishment ledger PASS')
