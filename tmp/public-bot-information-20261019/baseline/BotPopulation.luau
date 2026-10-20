-- Versioned bot funding and behavioral policy. No storage or network access.
local Policy={}
local function active(p,a)return not p.Engine.Books[a.Key].Spec.CloseOnly and not a.Retiring end
function Policy.Configure(p,a)
 local c=p.Config.BotPopulation;if not c or p.Engine.Books[a.Key].Spec.CloseOnly then return end
 local r=p.Random;local spec=p.Engine.Books[a.Key].Spec
 a.Budget=assert(c.Capital[a.Kind]);a.PolicyVersion=c.Version
 -- Scale by the generator's tick volatility in dollars; actual margin remains authoritative.
 local scale=math.clamp(c.ReferenceDollarVolatility/(spec.Tick*spec.Multiplier*spec.Scale),0.25,1)
 if a.Kind~='Reserve'then a.Size=math.max(1,math.floor(a.Size*scale))end
 a.Limit=math.max(a.Size,math.floor(a.Limit*scale))
 a.Lookback=r:Int(8,60);a.EntryThreshold=r:Range(.5,1.2)
 a.SignalWeight=r:Range(.6,1.5);a.ValueOffset=r:Noise()*3*spec.Scale
 a.BeliefHalfLife=r:Range(c.ValueHalfLife[1],c.ValueHalfLife[2])
 a.ObservationSeconds=r:Range(c.ValueObservationSeconds[1],c.ValueObservationSeconds[2])
 a.ObservationNoise=r:Range(c.ValueNoiseTicks[1],c.ValueNoiseTicks[2])*spec.Scale
 a.ObservedAt=p.Engine.Time;a.NextObservation=p.Engine.Time+r:Range(.25,a.ObservationSeconds)
 a.EntryBuffer=r:Range(2,6);a.MinMove=r:Range(c.ScalperMinMoveTicks[1],c.ScalperMinMoveTicks[2])
 if a.Kind=='Maker'then a.Speed*=c.MakerActivityScale
 elseif a.Kind=='Whale'then a.Speed*=c.WhaleActivityScale
 elseif a.Kind=='Reserve'then a.Limit=p.Config.Reserve.InventoryLimit
 elseif a.Kind=='Scalper'then a.Limit=a.Size;a.Lookback=r:Int(8,35)
 else a.Speed*=c.TraderActivityScale end
 a.Limit=math.min(a.Limit,math.floor(a.Budget*a.Risk*c.MarginFraction/spec.Margin))
 assert(a.Limit>=1 and a.Size>=1,'Bot funding cannot support a contract')
 a.Size=math.min(a.Size,a.Limit)
end
function Policy.Validate(p)
 local c=p.Config.BotPopulation;if not c then return end
 local seen,counts={},{}
 for _,a in ipairs(p.Agents)do
  assert(not seen[a.Id],'Duplicate participant id');seen[a.Id]=true
  assert(p.Engine.Accounts[a.Id] and not p.Engine.Accounts[a.Id].Player,'Invalid bot account')
  if active(p,a)then
   assert(c.Counts[a.Kind],'Unknown active bot group')
   local ac=p.Engine.Accounts[a.Id]
   assert(ac.StartingCapital and math.abs(ac.Base-ac.StartingCapital-(ac.NetCapitalAdjustments or 0))<.001,'Bot capital ledger differs')
   assert(ac.PolicyCapitalTarget==c.Capital[a.Kind]and a.Budget==c.Capital[a.Kind],'Bot funding policy differs')
   counts[a.Key]=counts[a.Key]or {};counts[a.Key][a.Kind]=(counts[a.Key][a.Kind]or 0)+1
  end
 end
 for _,key in ipairs(p.Config.ContractOrder)do if not p.Engine.Books[key].Spec.CloseOnly then
  for _,kind in ipairs(c.Order)do assert((counts[key]and counts[key][kind]or 0)==c.Counts[kind],key..' '..kind..' population differs')end
 end end
end
-- Pure inspection. Existing accounts are retained in sorted id order, including opaque renamed ids.
function Policy.Plan(p)
 local c=assert(p.Config.BotPopulation);local report={Version=c.Version,FromVersion=p.PolicyVersion or 0,
  Needed=(p.PolicyVersion or 0)<c.Version,Markets={},Accounts={},Add={},Retire={},FundingAdjustment=0}
 if not report.Needed then Policy.Validate(p);return report end
 local seen={}
 for _,a in ipairs(p.Agents)do assert(not seen[a.Id],'Duplicate participant id');seen[a.Id]=true end
 for _,key in ipairs(p.Config.ContractOrder)do if not p.Engine.Books[key].Spec.CloseOnly then
  local groups={};report.Markets[key]=groups
  for _,kind in ipairs(c.Order)do
   local list={};for _,a in ipairs(p.Agents)do if a.Key==key and a.Kind==kind and not a.Retiring then table.insert(list,a)end end
   table.sort(list,function(a,b)return a.Id<b.Id end)
   groups[kind]={Before=#list,Target=c.Counts[kind],TargetCapital=c.Counts[kind]*c.Capital[kind]}
   for i,a in ipairs(list)do
    local ac=p.Engine.Accounts[a.Id];assert(ac and not ac.Player,'Invalid migration account')
    local keep=i<=c.Counts[kind];local s=p.Engine:Summary(ac)
    local delta=keep and math.round((c.Capital[kind]-s.Equity)*100)/100 or 0
    local cancel,exits={},{}
    for id in pairs(ac.OpenOrders)do local o=p.Engine.Orders[id];table.insert(o.ReduceOnly and exits or cancel,id)end
    table.sort(cancel);table.sort(exits)
    local positions={};for symbol,pos in pairs(ac.Positions)do table.insert(positions,{Market=symbol,Quantity=pos.Quantity,Direction=pos.Direction,Entry=pos.Entry})end
    table.sort(positions,function(a,b)return a.Market<b.Market end)
    table.insert(report.Accounts,{Id=a.Id,Key=key,Kind=kind,Keep=keep,EquityBefore=s.Equity,BaseBefore=ac.Base,
     Realized=ac.Realized,Unrealized=s.Unrealized,FundingAdjustment=delta,TargetEquity=keep and c.Capital[kind]or nil,
     CancelEntryOrders=cancel,PreserveExitOrders=exits,Positions=positions})
    report.FundingAdjustment+=delta
    if not keep then table.insert(report.Retire,a.Id)end
   end
   local missing=math.max(0,c.Counts[kind]-#list)
   if missing>0 then table.insert(report.Add,{Key=key,Kind=kind,Count=missing,CapitalEach=c.Capital[kind]})end
  end
 end end
 return report
end
function Policy.Apply(p)
 local c=p.Config.BotPopulation;if not c then return end
 assert((p.PolicyVersion or 0)<=c.Version,'Cannot downgrade bot population policy')
 local report=Policy.Plan(p);if not report.Needed then return report end
 local byId={};for _,a in ipairs(p.Agents)do byId[a.Id]=a end
 for index,row in ipairs(report.Accounts)do
  local a,ac=byId[row.Id],p.Engine.Accounts[row.Id]
  for _,id in ipairs(row.CancelEntryOrders)do p.Engine:Cancel(a.Id,id)end
  a.Quotes={};a.ReplenishAt={};a.Parent=0
  if row.Keep then
   -- Refresh the profile from current ranges, preserving identity and live exit state.
   local fresh=p:_profile(a.Key,a.Kind,index)
   for key,value in pairs(fresh)do if key~='Id' and key~='Next' then a[key]=value end end
   a.Next=p.Engine.Time+p.Random:Range(.25,18)
   ac.StartingCapital=ac.StartingCapital or ac.Base
   ac.NetCapitalAdjustments=(ac.NetCapitalAdjustments or 0)+row.FundingAdjustment
   ac.CapitalAdjustments=ac.CapitalAdjustments or {}
   table.insert(ac.CapitalAdjustments,{Version=c.Version,Time=p.Engine.Time,Amount=row.FundingAdjustment,
    EquityBefore=row.EquityBefore,TargetEquity=row.TargetEquity,Reason='Bot population migration'})
   ac.Base=ac.StartingCapital+ac.NetCapitalAdjustments;ac.Balance=ac.Base+(ac.PnlBaseline or 0)+ac.Realized
   ac.PolicyCapitalTarget=c.Capital[a.Kind];ac.Limit=a.Limit;ac.Risk=a.Risk;ac.LossLimit=ac.Base
   ac.Locked=false;ac.Revision+=1
   -- Existing triggered liquidations and positions are preserved; repair happens through matching.
  else
   a.Retiring=true;a.Next=p.Engine.Time+p.Random:Range(.25,18)
  end
 end
 for _,row in ipairs(report.Add)do p:_ensurePopulation({row.Key},row.Kind,c.Counts[row.Kind])end
 -- Exactly half of every active market's scalpers use each style, including renamed old ids.
 for _,key in ipairs(p.Config.ContractOrder)do
  local scalpers={};for _,a in ipairs(p.Agents)do if a.Key==key and a.Kind=='Scalper' and active(p,a)then table.insert(scalpers,a)end end
  table.sort(scalpers,function(a,b)return a.Id<b.Id end)
  for i,a in ipairs(scalpers)do a.Style=i%2==0 and 'Momentum'or 'Reversion'end
 end
 p.PolicyVersion=c.Version;p.MigrationReport=report
 Policy.Validate(p)
 return report
end
return Policy
