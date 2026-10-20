local fs=require('@lune/fs')
local serde=require('@lune/serde')
local process=require('@lune/process')
local E=require('./baseline/MarketEngine')
local P=require('./baseline/Participants')
local Default=require('./baseline/MarketConfig')
local function clone(x)if type(x)~='table'then return x end;local y={}for k,v in pairs(x)do y[k]=clone(v)end;return y end
local seed=tonumber(process.args[1])or 73521
local seconds=tonumber(process.args[2])or 7200
local variant=process.args[3]or 'baseline'
if variant=='lower_noise'then P=require('./baseline/ParticipantsLowerNoise')end
if variant=='no_fade'then P=require('./baseline/ParticipantsNoFade')end
local c=clone(Default)
-- These display-only histories are not read by any decision/matching path.
c.MaxTradeHistory=100;c.MaxOrderHistory=100;c.MaxAccountHistory=5;c.MaxCandles=200
local e,p
if variant=='saved' then
 local CP=require('./baseline/WorldCheckpoint')
 local snapshot=require('./environment').game:GetService('HttpService'):JSONDecode(fs.readFile('backups/execution-integrity-20261015/private-preinstall-checkpoint.json')).Snapshot
 e,p=CP.Restore(snapshot,c)
 e.Config.MaxTradeHistory=100;e.Config.MaxOrderHistory=100;e.Config.MaxAccountHistory=5;e.Config.MaxCandles=200
else e=E.new(c,seed);p=P.new(e) end
local startTime=e.Time
if variant=='current_fair'then
 local trader=p._trader
 p._trader=function(self,a)
  if a.Kind=='Reversion'or a.Kind=='Protective'then a.Belief=self.Markets[a.Key].Fair end
  return trader(self,a)
 end
end
local agents,groups,baseline={},{},{}
local function group(a)
 local name=a.Kind
 if not groups[name]then groups[name]={Bots=0,Submits=0,Rejected=0,Rejections={},Fills=0,ClosedContracts=0,Closes=0,Wins=0,Losses=0,Reasons={},StartEquity=0,DeltaPnl=0,EndEquity=0,NoContractCapital=0,Orders=0,Positions=0,StopMovedAway=0,StopMovedCloser=0,StopSlipDollars=0,StopContracts=0}end
 return groups[name]
end
for _,a in ipairs(p.Agents)do
 if not e.Books[a.Key].Spec.CloseOnly and not a.Retiring then
  agents[a.Id]=a;local g=group(a);g.Bots+=1
  local ac=e.Accounts[a.Id];local s=e:Summary(ac);baseline[a.Id]=ac.Realized+s.Unrealized;g.StartEquity+=s.Equity
 end
end
local gates,windows={},{}
function p:DiagnosticGate(name,a)
 local key=a.Key;gates[key]=gates[key]or {};gates[key][name]=(gates[key][name]or 0)+1
 local index=math.floor((e.Time-startTime)/600)
 windows[index]=windows[index]or {Time=index*600,Decisions=0,Entries=0,MinMove=0,Closes=0,FlatSamples=0,Samples=0}
 if name=='Decisions'then windows[index].Decisions+=1 elseif name=='EntrySubmit'then windows[index].Entries+=1 elseif name=='MinMove'then windows[index].MinMove+=1 end
end
local submit=e.Submit
e.Submit=function(self,id,req,...)
 local a=agents[id];local g=a and group(a);if g then g.Submits+=1 end
 local ok,result=submit(self,id,req,...)
 if g and not ok then g.Rejected+=1;g.Rejections[tostring(result)]=(g.Rejections[tostring(result)]or 0)+1 end
 return ok,result
end
local fill=e._fillAccount
e._fillAccount=function(self,o,price,qty,id)
 local ac=self.Accounts[o.Owner];local a=agents[o.Owner];local g=a and group(a)
 local pos=ac.Positions[o.Contract];local closes=pos and pos.Direction~=o.Direction
 local oldStop,oldDir,oldId=pos and pos.Stop,pos and pos.Direction,pos and pos.Id
 local reason=o.Protection or pos and pos.Triggered or (self.DiagnosticTimed==o.Owner and 'Timed exit')or (a and a.Kind=='Scalper'and o.ReduceOnly and o.Type=='Limit'and 'Scalper target')or(self.DiagnosticRepair==o.Owner and 'Risk reduction')or 'Strategy trade'
 local before=ac.Realized;local closed=closes and math.min(qty,pos.Quantity)or 0
 local row=fill(self,o,price,qty,id)
 if variant=='fixed_stop'and a and(a.Kind=='Protective'or a.Kind=='Reversion')and not closes and oldStop then
  local held=ac.Positions[o.Contract]
  if held and held.Id==oldId then held.Stop=oldStop end
 end
 if g then
  g.Fills+=qty
  if closes then
   local pnl=ac.Realized-before;g.Closes+=1;g.ClosedContracts+=closed
   if pnl>.005 then g.Wins+=1 elseif pnl<-.005 then g.Losses+=1 end
   local rr=g.Reasons[reason]or {Count=0,Contracts=0,Pnl=0,Wins=0,Losses=0};g.Reasons[reason]=rr
   rr.Count+=1;rr.Contracts+=closed;rr.Pnl+=pnl;if pnl>.005 then rr.Wins+=1 elseif pnl<-.005 then rr.Losses+=1 end
   if reason=='Stop loss'and oldStop then g.StopSlipDollars+=(price-oldStop)*oldDir*closed*self.Books[o.Contract].Spec.Multiplier;g.StopContracts+=closed end
   if a.Kind=='Scalper'then local index=math.floor((e.Time-startTime)/600);if windows[index]then windows[index].Closes+=1 end end
  else
   local held=ac.Positions[o.Contract]
   if held and held.Id==oldId and oldStop and held.Stop and math.abs(held.Stop-oldStop)>.0001 then
    if(held.Stop-oldStop)*oldDir<0 then g.StopMovedAway+=1 else g.StopMovedCloser+=1 end
   end
  end
 end
 return row
end
local scalp=p._scalper
p._scalper=function(self,a)
 local pos=e.Accounts[a.Id].Positions[a.Key]
 self.Engine.DiagnosticTimed=pos and a.OpenedAt and e.Time-a.OpenedAt>=a.MaxHold and a.Id or nil
 scalp(self,a);self.Engine.DiagnosticTimed=nil
end
local repair=p._repairRisk
p._repairRisk=function(self,a)self.Engine.DiagnosticRepair=a.Id;local r=repair(self,a);self.Engine.DiagnosticRepair=nil;return r end
local samples={Count=0,AllScalpersFlat=0,AllScalpersIdle=0,AnyScalperOrders=0,Markets={}}
local clock=os.clock()
for step=1,math.floor(seconds/c.StepSeconds)do
 p:Step()
 if step%20==0 then
  samples.Count+=1;local flat=true;local orders=false
  for id,a in pairs(agents)do if a.Kind=='Scalper'then local ac=e.Accounts[id];if next(ac.Positions)then flat=false end;if next(ac.OpenOrders)then orders=true end end end
  if flat then samples.AllScalpersFlat+=1;if not orders then samples.AllScalpersIdle+=1 end end;if orders then samples.AnyScalperOrders+=1 end
  local w=windows[math.floor((e.Time-startTime)/600)];if w then w.Samples+=1;if flat then w.FlatSamples+=1 end end
  for _,key in ipairs(Default.ContractOrder)do
   local b=e.Books[key];local m=samples.Markets[key]or {Samples=0,Spread=0,TwoSided=0,RecentRange=0,Volatility=0};samples.Markets[key]=m;m.Samples+=1
   if b.Bids[1]and b.Asks[1]then m.TwoSided+=1;m.Spread+=b.Asks[1].Price-b.Bids[1].Price end
   local low,high=math.huge,-math.huge;for _,v in ipairs(b.Recent)do low=math.min(low,v);high=math.max(high,v)end
   if high>=low then m.RecentRange+=high-low end;m.Volatility+=b.Volatility
  end
 end
 if step%2400==0 then print(variant,seed,'simulated seconds',e.Time-startTime,'elapsed',os.clock()-clock)end
end
local profiles={}
for id,a in pairs(agents)do
 local ac=e.Accounts[id];local s=e:Summary(ac);local g=group(a)
 g.DeltaPnl+=ac.Realized+s.Unrealized-baseline[id];g.EndEquity+=s.Equity
 if s.Equity*ac.Risk<e.Books[a.Key].Spec.Margin then g.NoContractCapital+=1 end
 for _ in pairs(ac.OpenOrders)do g.Orders+=1 end;for _ in pairs(ac.Positions)do g.Positions+=1 end
 if a.Kind=='Scalper'then table.insert(profiles,{Market=a.Key,Style=a.Style,MinMove=a.MinMove,EntryBuffer=a.EntryBuffer,Threshold=a.EntryThreshold,Lookback=a.Lookback,Hold=a.MaxHold,Target=a.Target,Stop=a.Stop})end
end
local orderedWindows={};for _,w in pairs(windows)do table.insert(orderedWindows,w)end;table.sort(orderedWindows,function(a,b)return a.Time<b.Time end)
local result={Seed=seed,Variant=variant,StartTime=startTime,Seconds=seconds,Groups=groups,Gates=gates,Windows=orderedWindows,Samples=samples,ScalperProfiles=profiles,Audit=e:Audit(),Elapsed=os.clock()-clock,Note='Detached current-source simulation. No live world, player actions, or funding changes. saved variant uses a historical Studio checkpoint, not the user report.'}
local path='output/bot-strategy-20261018/'..variant..'-'..seed..'-'..seconds..'.json'
fs.writeFile(path,serde.encode('json',result,true));print('Saved',path)
