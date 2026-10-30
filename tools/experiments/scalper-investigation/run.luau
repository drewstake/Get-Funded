local fs=require('@lune/fs')
local serde=require('@lune/serde')
local process=require('@lune/process')
local E=require('./modules/MarketEngine')
local P=require('./modules/Participants')
local Default=require('./modules/MarketConfig')
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local seed=tonumber(process.args[1])or 19381
local seconds=tonumber(process.args[2])or 7200
local variant=process.args[3]or 'baseline'
if variant=='random_direction'then P=require('./modules/ParticipantsRandom')end
if variant=='random_unfiltered'then P=require('./modules/ParticipantsRandomUnfiltered')end
if variant=='public_fair'then P=require('./modules/ParticipantsPublic')end
if variant=='no_fair_filter'then P=require('./modules/ParticipantsNoFair')end
if variant=='fair_makers'then P=require('./modules/ParticipantsFairMaker')end
local c=clone(Default)
c.MaxTradeHistory=100;c.MaxOrderHistory=100;c.MaxAccountHistory=5;c.MaxCandles=200
if variant=='fast_makers'then c.MakerMinRestSeconds=.25;c.MakerRepriceTicks=1 end
if variant=='aggressive_only'then c.Scalper.AggressiveChance=1 end
if variant=='passive_only'then c.Scalper.AggressiveChance=0 end
local e=E.new(c,seed);local p=P.new(e)
p.DiagnosticRandom=P.RNG.new(seed+1000003)
local agents,rows,groups={},{},{}
local function empty()return {Bots=0,Positive=0,Negative=0,Pnl=0,Realized=0,Unrealized=0,Closes=0,Wins=0,Losses=0,Even=0,GrossWins=0,GrossLosses=0,ClosedContracts=0,FillContracts=0,Entries=0,PassiveEntries=0,EntryFairEdgeTicks=0,EntryMakerAge=0,MakerEntryCount=0,Reasons={},Counterparties={},ExitCounterparties={},HoldSeconds=0,MaxDrawdown=0,MinBotPnl=math.huge,MaxBotPnl=-math.huge}end
for _,a in ipairs(p.Agents)do
 agents[a.Id]=a
 if a.Kind=='Scalper'then
  rows[a.Id]=empty();local row=rows[a.Id];row.Id=a.Id;row.Market=a.Key;row.Style=a.Style;row.Peak=0;row.Target=a.Target;row.Stop=a.Stop;row.Size=a.Size
 end
end
local activeTrade
local trade=e._trade
e._trade=function(self,b,incoming,resting,qty)
 activeTrade={Incoming=incoming,Resting=resting}
 local result=trade(self,b,incoming,resting,qty);activeTrade=nil;return result
end
local fill=e._fillAccount
e._fillAccount=function(self,o,price,qty,id)
 local a=agents[o.Owner];local row=rows[o.Owner];local ac=self.Accounts[o.Owner]
 local held=ac.Positions[o.Contract];local closing=held and held.Direction~=o.Direction
 local closed=closing and math.min(qty,held.Quantity)or 0
 local before=ac.Realized;local reason
 local cp,restingAge,passive
 if row then
  reason=o.Protection or held and held.Triggered or (self.DiagnosticTimed==o.Owner and 'Timed exit')or(o.ReduceOnly and o.Type=='Limit'and 'Target')or 'Other'
  local other=activeTrade and(activeTrade.Incoming.Owner==o.Owner and activeTrade.Resting or activeTrade.Incoming)
  cp=other and agents[other.Owner]and agents[other.Owner].Kind or 'Other'
  passive=activeTrade and activeTrade.Resting==o
  restingAge=activeTrade and(self.Time-activeTrade.Resting.Time)or 0
 end
 local result=fill(self,o,price,qty,id)
 if row then
  row.FillContracts+=qty
  if closing then
   local pnl=ac.Realized-before
   row.Closes+=1;row.ClosedContracts+=closed
   if pnl>.005 then row.Wins+=1;row.GrossWins+=pnl elseif pnl<-.005 then row.Losses+=1;row.GrossLosses-=pnl else row.Even+=1 end
   local rr=row.Reasons[reason]or {Count=0,Pnl=0};row.Reasons[reason]=rr;rr.Count+=1;rr.Pnl+=pnl
   row.ExitCounterparties[cp]=(row.ExitCounterparties[cp]or 0)+closed
   if row.OpenedAt then row.HoldSeconds+=(self.Time-row.OpenedAt)*closed end
  else
   row.Entries+=1;if passive then row.PassiveEntries+=1 end
   row.EntryFairEdgeTicks+=(p.Markets[a.Key].Fair-price/self.Books[a.Key].Spec.Tick)*o.Direction
   row.Counterparties[cp]=(row.Counterparties[cp]or 0)+qty
   if cp=='Maker'and not passive then row.EntryMakerAge+=restingAge;row.MakerEntryCount+=1 end
   if not held then row.OpenedAt=self.Time end
  end
 end
 return result
end
local scalp=p._scalper
p._scalper=function(self,a)
 local pos=e.Accounts[a.Id].Positions[a.Key]
 e.DiagnosticTimed=pos and a.OpenedAt and e.Time-a.OpenedAt>=a.MaxHold and a.Id or nil
 scalp(self,a);e.DiagnosticTimed=nil
end
local samples={};local clock=os.clock()
for step=1,math.floor(seconds/c.StepSeconds)do
 p:Step()
 if step%40==0 then
  for id,row in pairs(rows)do
   local ac=e.Accounts[id];local pnl=ac.Realized+e:Summary(ac).Unrealized
   row.Peak=math.max(row.Peak,pnl);row.MaxDrawdown=math.max(row.MaxDrawdown,row.Peak-pnl)
  end
 end
 if step%2400==0 then
  local pnl,positive,negative=0,0,0
  for id in pairs(rows)do local ac=e.Accounts[id];local net=ac.Realized+e:Summary(ac).Unrealized;pnl+=net;if net>0 then positive+=1 elseif net<0 then negative+=1 end end
  table.insert(samples,{Time=e.Time,Pnl=pnl,Positive=positive,Negative=negative})
  e:Audit()
  print(variant,seed,e.Time,math.floor(os.clock()-clock),positive,pnl)
 end
end
local function add(g,row)
 g.Bots+=1;if row.Pnl>0 then g.Positive+=1 elseif row.Pnl<0 then g.Negative+=1 end
 for _,key in ipairs({'Pnl','Realized','Unrealized','Closes','Wins','Losses','Even','GrossWins','GrossLosses','ClosedContracts','FillContracts','Entries','PassiveEntries','EntryFairEdgeTicks','EntryMakerAge','MakerEntryCount','HoldSeconds'})do g[key]+=row[key]end
 g.MaxDrawdown=math.max(g.MaxDrawdown,row.MaxDrawdown);g.MinBotPnl=math.min(g.MinBotPnl,row.Pnl);g.MaxBotPnl=math.max(g.MaxBotPnl,row.Pnl)
 for key,v in pairs(row.Reasons)do local r=g.Reasons[key]or {Count=0,Pnl=0};g.Reasons[key]=r;r.Count+=v.Count;r.Pnl+=v.Pnl end
 for _,name in ipairs({'Counterparties','ExitCounterparties'})do for key,v in pairs(row[name])do g[name][key]=(g[name][key]or 0)+v end end
end
local bots={}
for id,row in pairs(rows)do
 local ac=e.Accounts[id];row.Realized=ac.Realized;row.Unrealized=e:Summary(ac).Unrealized;row.Pnl=row.Realized+row.Unrealized
 for _,key in ipairs({'Total',row.Style,row.Market,row.Market..':'..row.Style})do groups[key]=groups[key]or empty();add(groups[key],row)end
 table.insert(bots,row)
end
table.sort(bots,function(a,b)return a.Id<b.Id end)
local types={}
for _,a in ipairs(p.Agents)do local ac=e.Accounts[a.Id];types[a.Kind]=(types[a.Kind]or 0)+ac.Realized+e:Summary(ac).Unrealized end
local out={Seed=seed,Seconds=seconds,Variant=variant,Groups=groups,Bots=bots,Samples=samples,TypePnl=types,Audit=e:Audit(),Elapsed=os.clock()-clock,
 Scope='Fresh isolated current-source simulation; no refresh, player trades, persistence or network. Closing-fill win rates; mark-to-market P&L. Equal seeds are sensitivity comparisons, not identical price paths.'}
local path='output/scalper-investigation-20261019/'..variant..'-'..seed..'-'..seconds..'.json'
fs.writeFile(path,serde.encode('json',out,true));print('Saved',path)
