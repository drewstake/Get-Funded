local fs=require('@lune/fs')
local serde=require('@lune/serde')
local process=require('@lune/process')
local E=require('./modules/MarketEngine')
local P=require('./modules/Participants')
local live=serde.decode('json',fs.readFile('output/bot-investigation-20261014/live-evidence.json'))
local function clone(x)if type(x)~='table'then return x end local y={}for k,v in pairs(x)do y[k]=clone(v)end return y end
local seed=tonumber(process.args[1])or 73521
local seconds=tonumber(process.args[2])or 7200
local variant=process.args[3]or 'baseline'
local c=clone(live.Config);c.ContractOrder={'BX','BT','BG'}
-- Display-only retention does not feed participant decisions or matching.
c.MaxTradeHistory=100;c.MaxOrderHistory=100;c.MaxAccountHistory=2;c.MaxCandles=200
local e=E.new(c,seed)
local p=P.new(e)
if variant=='scalpers_follow' then for _,a in ipairs(p.Agents)do if a.Kind=='Scalper'then a.Style='Momentum'end end end
if variant=='maker_fast' then c.MakerMinRestSeconds=2;c.MakerRepriceTicks=1 end
if variant=='scalper_longer' then for _,a in ipairs(p.Agents)do if a.Kind=='Scalper'then a.MaxHold*=4 end end end
if variant=='value_fast' then
 local original=P._trader
 p._trader=function(self,a)if a.Kind=='Value'then a.Belief=self.Markets[a.Key].Fair end return original(self,a)end
end
local agents={}for _,a in ipairs(p.Agents)do agents[a.Id]=a end
local groups,flow,queue={},{},{}
local qi=1
local function label(a)
 return a.Kind=='Scalper' and 'Scalper/'..a.Style or a.Kind
end
local function group(name)
 if not groups[name]then groups[name]={Count=0,Base=0,Pnl=0,Realized=0,Unrealized=0,ProfitBots=0,NoOneContractCapacity=0,Submit=0,Rejected=0,Rejections={},FillContracts=0,TakerContracts=0,PassiveContracts=0,MidCost=0,MidVolume=0,Markout30=0,MarkoutVolume=0,TakerMarkout30=0,TakerMarkoutVolume=0,PassiveMarkout30=0,PassiveMarkoutVolume=0,Closes=0,Wins=0,Losses=0,ClosePnl=0,Reasons={},ByMarket={},ByDirection={},TakerMakerFills=0,AgainstReserve=0}end
 return groups[name]
end
local startPnl={}
for _,a in ipairs(p.Agents)do startPnl[a.Id]=e:Summary(e.Accounts[a.Id]).Session end
local originalSubmit=e.Submit
e.Submit=function(self,id,req,internal)
 local a=agents[id];local g=a and group(label(a));if g then g.Submit+=1 end
 local ok,result=originalSubmit(self,id,req,internal)
 if g and not ok then g.Rejected+=1;g.Rejections[tostring(result)]=(g.Rejections[tostring(result)]or 0)+1 end
 return ok,result
end
local originalScalper=P._scalper
p._scalper=function(self,a)
 local position=e.Accounts[a.Id].Positions[a.Key]
 local old=e.DiagnosticExit
 if position and a.OpenedAt and e.Time-a.OpenedAt>=a.MaxHold then e.DiagnosticExit=a.Id end
 originalScalper(self,a)
 e.DiagnosticExit=old
end
local originalFill=e._fillAccount
e._fillAccount=function(self,o,price,qty,id)
 local a=self.Accounts[o.Owner];local prior=a.Realized;local pos=a.Positions[o.Contract]
 local closes=pos and pos.Direction~=o.Direction
 local agent=agents[o.Owner]
 local reason=o.Protection or (pos and pos.Triggered) or (self.DiagnosticExit==o.Owner and 'Timed exit') or (agent and agent.Kind=='Scalper'and o.ReduceOnly and o.Type=='Limit'and 'Resting target') or 'Trade'
 local direction=pos and pos.Direction
 originalFill(self,o,price,qty,id)
 if agent and closes then
  local g=group(label(agent));local pnl=a.Realized-prior
  g.Closes+=1;g.ClosePnl+=pnl;if pnl>.005 then g.Wins+=1 elseif pnl<-.005 then g.Losses+=1 end
  local rr=g.Reasons[reason]or {Count=0,Pnl=0};g.Reasons[reason]=rr;rr.Count+=1;rr.Pnl+=pnl
  local dd=g.ByDirection[tostring(direction)]or {Count=0,Pnl=0};g.ByDirection[tostring(direction)]=dd;dd.Count+=1;dd.Pnl+=pnl
 end
end
local originalTrade=e._trade
e._trade=function(self,b,inc,rest,qty)
 local bid,ask=b.Bids[1],b.Asks[1];local mid=bid and ask and(bid.Price+ask.Price)/2
 local price=rest.Price*b.Spec.Tick
 local both={inc,rest}
 for index,o in ipairs(both)do
  local a=agents[o.Owner];local other=agents[both[3-index].Owner]
  if a then
   local name=label(a);local g=group(name);local taker=index==1
   g.FillContracts+=qty
   if not taker then g.QuoteAgeQuantity=(g.QuoteAgeQuantity or 0)+(self.Time-o.Time)*qty end
   if taker then g.TakerContracts+=qty else g.PassiveContracts+=qty end
   if mid then g.MidCost+=(rest.Price-mid)*o.Direction*qty*b.Spec.Tick*b.Spec.Multiplier;g.MidVolume+=qty end
   if other and other.Kind=='Reserve'then g.AgainstReserve+=qty end
   table.insert(queue,{Time=self.Time+30,Group=name,Key=b.Key,Price=price,Side=o.Direction,Qty=qty,Taker=taker})
   local otherName=other and label(other)or 'Other'
   flow[name]=flow[name]or {};flow[name][otherName]=flow[name][otherName]or {}
   local f=flow[name][otherName][b.Key]or {Net=0,Cash=0};flow[name][otherName][b.Key]=f
   f.Net+=o.Direction*qty;f.Cash-=o.Direction*qty*price*b.Spec.Multiplier
  end
 end
 return originalTrade(self,b,inc,rest,qty)
end
local sampled={Count=0,Spread=0,TwoSided=0,Missing=0,FairMove=0,LastFair={},TrendSeconds={},Series={}}
local cpu=os.clock()
for step=1,math.floor(seconds/c.StepSeconds)do
 p:Step()
 while queue[qi]and queue[qi].Time<=e.Time do
  local x=queue[qi];local b=e.Books[x.Key];local v=((b.Last or b.Reference)*b.Spec.Tick-x.Price)*x.Side*x.Qty*b.Spec.Multiplier
  local g=group(x.Group);g.Markout30+=v;g.MarkoutVolume+=x.Qty
  if x.Taker then g.TakerMarkout30+=v;g.TakerMarkoutVolume+=x.Qty else g.PassiveMarkout30+=v;g.PassiveMarkoutVolume+=x.Qty end
  qi+=1
 end
 if qi>2000 then local n={}for i=qi,#queue do table.insert(n,queue[i])end queue=n;qi=1 end
 sampled.TrendSeconds[p.Regime.Name]=(sampled.TrendSeconds[p.Regime.Name]or 0)+c.StepSeconds
 if step%20==0 then
  for _,key in ipairs(c.ContractOrder)do
   local b=e.Books[key];e:_pruneBook(b);sampled.Count+=1
   if b.Bids[1]and b.Asks[1]then sampled.Spread+=b.Asks[1].Price-b.Bids[1].Price;sampled.TwoSided+=1 else sampled.Missing+=1 end
  end
 end
 if step%2400==0 then
  local row={Time=e.Time,Pnl={},Fair={}}
  for _,a in ipairs(p.Agents)do local k=label(a);row.Pnl[k]=(row.Pnl[k]or 0)+e:Summary(e.Accounts[a.Id]).Session-startPnl[a.Id]end
  for _,key in ipairs(c.ContractOrder)do row.Fair[key]=p.Markets[key].Fair end
  table.insert(sampled.Series,row)
  print(seed,variant,'simulated',e.Time,'seconds; CPU',math.round(os.clock()-cpu))
 end
end
local flowPnl={}
for g,others in pairs(flow)do flowPnl[g]={}for other,markets in pairs(others)do
 local pnl=0
 for key,f in pairs(markets)do local b=e.Books[key];pnl+=f.Cash+f.Net*(b.Last or b.Reference)*b.Spec.Tick*b.Spec.Multiplier end
 flowPnl[g][other]=pnl
end end
for _,a in ipairs(p.Agents)do
 local ac=e.Accounts[a.Id];local s=e:Summary(ac);local g=group(label(a))
 g.Count+=1;g.Base+=ac.Base;g.Pnl+=s.Session-startPnl[a.Id];g.Realized+=ac.Realized;g.Unrealized+=s.Unrealized
 if s.Session>0.005 then g.ProfitBots+=1 end
 if s.Equity*ac.Risk<e.Books[a.Key].Spec.Margin then g.NoOneContractCapacity+=1 end
 g.ByMarket[a.Key]=(g.ByMarket[a.Key]or 0)+s.Session-startPnl[a.Id]
end
local result={MeasurementVersion=2,Seed=seed,Variant=variant,SimulatedSeconds=seconds,CpuSeconds=os.clock()-cpu,Groups=groups,CounterpartyMarkToMarket=flowPnl,Market=sampled,Audit=e:Audit(),Measurement='Fresh isolated simulation using saved Live config and local source. Initial auction excluded from Pnl/flow; startup realized remains in Realized. Markouts use last trade 30 simulated seconds after each fill; final 30s excluded.'}
local path='output/bot-investigation-20261014/'..variant..'-'..seed..'-'..seconds..'.json'
fs.writeFile(path,serde.encode('json',result,true))
print('DONE',path)

