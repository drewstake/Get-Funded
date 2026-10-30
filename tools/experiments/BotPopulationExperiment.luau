-- Isolated experiment. Caller supplies module copies; no storage/network access.
local Experiment={}
local function clone(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
local function percentile(values,q)table.sort(values);return values[math.max(1,math.ceil(#values*q))]or 0 end
function Experiment.Run(E,P,C,CP,options)
 local c=clone(C);local seed=options.Seed;local seconds=options.Seconds
 local e=E.new(c,seed);local p=P.new(e)
 if options.WithoutStrategyFixes then
  -- Population/capital/quote budgets unchanged: disable only value observations and scalper entry/hold changes.
  for _,a in ipairs(p.Agents)do
   if a.Kind=='Value'then a.PolicyVersion=nil;a.EntryThreshold=nil end
   if a.Kind=='Scalper'then a.PolicyVersion=nil;a.EntryThreshold=nil;a.Lookback=p.Random:Int(3,12);a.MaxHold/=4;a.Cooldown/=2 end
  end
 end
 local groups,agents={},{}
 for _,a in ipairs(p.Agents)do
  agents[a.Id]=a
  local g=groups[a.Kind]or {Count=0,Capital=0,Pnl=0,Realized=0,Equity=0,Profitable=0,Depleted=0,NoOneContractCapital=0,NoEntryCapacity=0,Submits=0,Rejected=0,Closes=0,TimedCloses=0,TimedPnl=0}
  groups[a.Kind]=g;g.Count+=1;g.Capital+=e.Accounts[a.Id].Base
 end
 local submit=e.Submit
 e.Submit=function(self,id,request,...)
  local g=agents[id]and groups[agents[id].Kind];if g then g.Submits+=1 end
  local ok,r=submit(self,id,request,...);if g and not ok then g.Rejected+=1 end;return ok,r
 end
 local scalper=p._scalper
 P._scalper=function(self,a)
  local pos=e.Accounts[a.Id].Positions[a.Key]
  e.TimedDiagnostic=pos and a.OpenedAt and e.Time-a.OpenedAt>=a.MaxHold and a.Id or nil
  scalper(self,a);e.TimedDiagnostic=nil
 end
 local fill=e._fillAccount
 e._fillAccount=function(self,o,price,qty,id)
  local ac=self.Accounts[o.Owner];local pos=ac.Positions[o.Contract];local closes=pos and pos.Direction~=o.Direction;local before=ac.Realized
  fill(self,o,price,qty,id)
  local g=agents[o.Owner]and groups[agents[o.Owner].Kind]
  if g and closes then g.Closes+=1;if self.TimedDiagnostic==o.Owner then g.TimedCloses+=1;g.TimedPnl+=ac.Realized-before end end
 end
 local matchingTime,matchingCalls,slip,slipQty=0,0,0,0
 local match=e._match
 e._match=function(self,...)
  local t=os.clock();local ok,r=match(self,...);matchingTime+=os.clock()-t;matchingCalls+=1
  if ok and r.Filled and r.Filled>0 then slip+=(r.Slippage or 0)*r.Filled;slipQty+=r.Filled end
  return ok,r
 end
 local market={};for _,key in ipairs(c.ContractOrder)do market[key]={Samples=0,TwoSided=0,SpreadTicks=0,Depth5=0,ProbeFilled=0,ProbeRequested=0,ProbeSlippageTicks=0}end
 local times,checkpointTimes={},{};local stepTime=0;local maxRaw,maxStored=0,0
 local start=os.clock();local checkpoints=0
 for i=1,math.floor(seconds/c.StepSeconds)do
  local t=os.clock();p:Step();local duration=os.clock()-t;stepTime+=duration;table.insert(times,duration)
  if i%20==0 then for _,key in ipairs(c.ContractOrder)do
   local b=e.Books[key];e:_pruneBook(b);local m=market[key];m.Samples+=1
   if b.Bids[1]and b.Asks[1]then m.TwoSided+=1;m.SpreadTicks+=b.Asks[1].Price-b.Bids[1].Price end
   for _,side in ipairs({b.Bids,b.Asks})do
    for depth=1,math.min(5,#side)do m.Depth5+=side[depth].Quantity end
    local remaining=100;m.ProbeRequested+=remaining
    for _,level in ipairs(side)do
     local qty=math.min(remaining,level.Quantity);m.ProbeFilled+=qty
     m.ProbeSlippageTicks+=qty*math.abs(level.Price-side[1].Price);remaining-=qty;if remaining==0 then break end
    end
   end
  end end
  if i%1080==0 then -- 15 wall-clock seconds at the configured 18x speed.
   local t2=os.clock();local record=CP.Encode(CP.Capture(e,p));table.insert(checkpointTimes,os.clock()-t2)
   checkpoints+=1;maxRaw=math.max(maxRaw,record.RawBytes);maxStored=math.max(maxStored,#record.Payload+4096)
   e:Audit()
  end
  if i%2400==0 and options.Progress then options.Progress(e.Time)end
  if options.Yield and i%100==0 then options.Yield()end
 end
 local equityTotal,maxEquity=0,0
 for _,a in ipairs(p.Agents)do
  local ac=e.Accounts[a.Id];local s=e:Summary(ac);local g=groups[a.Kind]
  g.Equity+=s.Equity;g.Pnl+=ac.Realized+s.Unrealized;g.Realized+=ac.Realized
  if s.Session>0 then g.Profitable+=1 end
  if s.Equity<=0 then g.Depleted+=1 end
  if s.Equity*ac.Risk<e.Books[a.Key].Spec.Margin then g.NoOneContractCapital+=1 end
  if ac.Locked or ac.Liquidating or not(e:Exposure(ac,a.Key,1,1)or e:Exposure(ac,a.Key,-1,1))then g.NoEntryCapacity+=1 end
  local positive=math.max(0,s.Equity);equityTotal+=positive;maxEquity=math.max(maxEquity,positive)
 end
 local hhi=0;for _,a in ipairs(p.Agents)do hhi+=(math.max(0,e:Summary(e.Accounts[a.Id]).Equity)/math.max(1,equityTotal))^2 end
 for _,g in pairs(groups)do g.Return=g.Pnl/g.Capital end
 for _,m in pairs(market)do
  m.AverageSpreadTicks=m.SpreadTicks/math.max(1,m.TwoSided);m.TwoSidedFraction=m.TwoSided/m.Samples
  m.AverageDepth5PerSide=m.Depth5/(m.Samples*2);m.ProbeFillFraction=m.ProbeFilled/m.ProbeRequested
  m.ProbeAverageSlippageTicks=m.ProbeSlippageTicks/math.max(1,m.ProbeFilled)
 end
 local checkpointTotal=0;for _,t in ipairs(checkpointTimes)do checkpointTotal+=t end
 P._scalper=scalper
 return {Seed=seed,Seconds=seconds,Variant=options.Variant,Groups=groups,Markets=market,Audit=e:Audit(),
  Concentration={LargestAccountShare=maxEquity/math.max(1,equityTotal),EquityHHI=hhi,ReserveShare=groups.Reserve.Equity/math.max(1,equityTotal)},
  Performance={ElapsedSeconds=os.clock()-start,StepSeconds=stepTime,StepP95Ms=percentile(times,.95)*1000,StepP99Ms=percentile(times,.99)*1000,
   MatchingSeconds=matchingTime,MatchingCalls=matchingCalls,CheckpointSeconds=checkpointTotal,CheckpointP95Ms=percentile(checkpointTimes,.95)*1000,
   Checkpoints=checkpoints,MaxRawBytes=maxRaw,MaxEncodedEstimate=maxStored,
   ComputeFractionAt18x=(stepTime+checkpointTotal)/(seconds/18)},
  ExecutionSlippage={WeightedReported=slip/math.max(1,slipQty),Contracts=slipQty},
  Notes='Fresh isolated populations, production retention, fixed seeds and equal durations. RNG consumption and market paths differ across configurations. Depth probes are hypothetical raw-book sweeps of 100 contracts, without player execution quotas. Matching time is a subset of step time. Checkpoint estimate includes 4096 bytes headroom. No human or legacy accounts.'}
end
return Experiment
