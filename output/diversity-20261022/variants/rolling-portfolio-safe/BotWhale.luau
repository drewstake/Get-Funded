-- Patient funded mandates. Durable state is checkpointed on the participant.
-- No price writes, shared random draws, wall clocks, cash grants or private loops.
local W={}
local function random(s)s.RandomState=s.RandomState*48271%2147483647;return s.RandomState/2147483647 end
local function range(s,v)return v[1]+(v[2]-v[1])*random(s)end
local function seed(id,world)
 local n=math.floor(math.abs(world or 1))%2147483646+1
 for i=1,#id do n=(n*31+string.byte(id,i))%2147483646 end
 return n+1
end
local function counter(ac,side)return (side==1 and ac.BotBuyContracts or ac.BotSellContracts)or 0 end
local function cancelChild(e,a,s)
 if s.ChildId and e.Orders[s.ChildId]then e:Cancel(a.Id,s.ChildId)end
 s.ChildId=nil;s.ChildAt=nil;s.ChildPrice=nil
end
local function cancelEntries(e,a)
 local ids={};for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
end
function W.Enabled(p,a)
 return a.Kind=='Whale'and p.Config.BotWhale~=nil and p.Config.BotPopulation~=nil and a.PolicyVersion~=nil
end
function W.Adopt(p,a)
 local e,c=p.Engine,p.Config.BotWhale;local s=a.Whale
 if s and s.Version==c.Version then return s end
 local ac=e.Accounts[a.Id];cancelEntries(e,a)
 s={Version=c.Version,RandomState=seed(a.Id,e.Seed)}
 for _=1,6 do random(s)end
 s.BuildSeconds=range(s,c.BuildSeconds);s.HoldSeconds=range(s,c.HoldSeconds);s.ReduceSeconds=range(s,c.ReduceSeconds)
 s.TargetFraction=range(s,c.TargetFraction);s.Participation=range(s,c.Participation)
 s.QuoteSeconds=range(s,c.QuoteSeconds);s.PriceTolerance=math.max(c.MaxSlippageTicks,math.floor(a.Stop*range(s,c.PriceToleranceStops)))
 s.Recoveries=ac.ParticipationRecoveries or 0
 local pos=ac.Positions[a.Key];s.PositionId=pos and pos.Id;s.Phase=pos and 'Holding'or 'Waiting'
 s.HoldUntil=pos and e.Time+s.HoldSeconds;s.CooldownUntil=e.Time+range(s,c.StartDelay)
 a.Whale=s;a.OrderObjective=nil;a.FlowPositionId=nil;a.FlowCooldownUntil=s.CooldownUntil
 return s
end
local function pause(e,a,s,c,stopped)
 cancelChild(e,a,s);s.Phase='Waiting';s.PositionId=nil;s.Target=nil;s.Side=nil
 s.CooldownUntil=e.Time+range(s,stopped and c.StopCooldownSeconds or c.CooldownSeconds)
 a.FlowCooldownUntil=s.CooldownUntil
end
local function phase(e,a,s,c,name,side,quantity,duration)
 cancelChild(e,a,s)
 local ac=e.Accounts[a.Id];s.Phase=name;s.Side=side;s.Quantity=quantity;s.Filled=0
 s.StartedAt=e.Time;s.Duration=duration;s.Deadline=e.Time+duration
 s.StartSideFills=counter(ac,side);s.StartOwnFills=ac.BotFilledContracts or 0;s.StartVolume=e.Books[a.Key].Volume
 s.NextChildAt=e.Time+range(s,c.SliceSeconds)
end
function W.Budget(p,a,s)
 local e,c=p.Engine,p.Config.BotWhale;local ac=e.Accounts[a.Id]
 -- Cumulative account counters survive order retirement and checkpoint restoration.
 -- Only one child can be live. Protection fills may reduce the position, never create an entry budget.
 s.Filled=math.max(0,counter(ac,s.Side)-s.StartSideFills)
 local elapsed=math.max(0,e.Time-s.StartedAt)
 local external=math.max(0,e.Books[a.Key].Volume-s.StartVolume-((ac.BotFilledContracts or 0)-s.StartOwnFills))
 local allowed=math.floor(external*s.Participation)+1+math.floor(elapsed/c.QuietSeconds)
 local due=math.ceil(s.Quantity*math.clamp(elapsed/s.Duration,0,1))
 return math.max(0,math.min(s.Quantity,due,allowed)-s.Filled),external,allowed
end
function W.Step(p,a)
 if not W.Enabled(p,a)then return end
 local e,c=p.Engine,p.Config.BotWhale;local ac=e.Accounts[a.Id];local b=e.Books[a.Key]
 local s=W.Adopt(p,a);a.FlowNextDecision=e.Time+range(s,c.SliceSeconds)
 local pos=ac.Positions[a.Key]
 if ac.Locked or ac.Liquidating or a.Retiring or b.Spec.CloseOnly or (pos and pos.Triggered)then cancelEntries(e,a);return end
 if s.Recoveries~=(ac.ParticipationRecoveries or 0)then
  s.Recoveries=ac.ParticipationRecoveries or 0;pause(e,a,s,c,true);return
 end
 if s.PositionId and (not pos or pos.Id~=s.PositionId)then
  pause(e,a,s,c,not(s.Phase=='Reducing'and not pos));return
 end
 if (s.CooldownUntil or 0)>e.Time then a.FlowCooldownUntil=s.CooldownUntil;return end
 a.FlowCooldownUntil=nil
 if s.Phase=='Building'or s.Phase=='Reducing'then W.Budget(p,a,s)end
 -- A passive entry can fill and stop between decisions, before PositionId was observed.
 if s.Phase=='Building'and not pos and s.Filled>0 then pause(e,a,s,c,true);return end
 if pos and not s.PositionId then s.PositionId=pos.Id end
 local equity=e:Summary(ac).Equity
 local capacity=math.max(0,math.min(a.Limit,ac.Limit,math.floor(equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin)))
 local stressed=equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)
 if pos and s.ExitReason~='Risk'and (stressed or pos.Quantity>capacity)then
  cancelEntries(e,a);phase(e,a,s,c,'Reducing',-pos.Direction,pos.Quantity,s.ReduceSeconds);s.ExitReason='Risk'
 end
 if s.Phase=='Building'and (e.Time>=s.Deadline or s.Filled>=s.Quantity)then
  cancelChild(e,a,s)
  if pos then s.Phase='Holding';s.HoldUntil=e.Time+s.HoldSeconds else pause(e,a,s,c,false)end
 end
 if s.Phase=='Holding'then
  if not pos then pause(e,a,s,c,false);return end
  if e.Time<s.HoldUntil then return end
  phase(e,a,s,c,'Reducing',-pos.Direction,pos.Quantity,s.ReduceSeconds);s.ExitReason='Time'
 end
 if s.Phase=='Waiting'then
  if pos then s.Phase='Holding';s.HoldUntil=e.Time+s.HoldSeconds;return end
  if stressed then return end
  local riskCapacity=math.floor(math.max(0,equity)*c.PositionRiskFraction/(a.Stop*b.Spec.Tick*b.Spec.Multiplier))
  local quantity=math.min(math.floor(capacity*s.TargetFraction),riskCapacity)
  if quantity<1 then return end
  -- Independent portfolio mandates, not a shared trend signal or a scheduled reversal.
  local side=random(s)<.5 and 1 or -1
  phase(e,a,s,c,'Building',side,quantity,s.BuildSeconds)
  s.Target=quantity*side;s.Arrival=b.Last or b.Reference;s.ExitReason=nil
 end
 local reducing=s.Phase=='Reducing'
 if reducing and not pos then pause(e,a,s,c,false);return end
 local bid,ask=e:PublicPrices(a.Key)
 local ownTouch=s.Side==1 and bid or ask;local opposite=s.Side==1 and ask or bid
 if s.ChildId then
  local order=e.Orders[s.ChildId]
  if not order then
   cancelChild(e,a,s);s.NextChildAt=e.Time+range(s,c.RefillSeconds);return
  end
  -- Retain FIFO priority; only stale, meaningfully displaced children are withdrawn.
  if e.Time-s.ChildAt>=c.MinRestSeconds and ownTouch and math.abs(ownTouch/b.Spec.Tick-s.ChildPrice)>=c.RepriceTicks then
   cancelChild(e,a,s);s.NextChildAt=e.Time+range(s,c.RefillSeconds)
  end
  return
 end
 if e.Time<(s.NextChildAt or 0)then return end
 local budget=W.Budget(p,a,s)
 local urgency=math.clamp((e.Time-s.StartedAt)/s.Duration,0,1)
 local aggressive=s.ExitReason=='Risk'or random(s)<.30+urgency*(.65-.30)
 local touch=aggressive and opposite or ownTouch
 if not touch then return end
 local tick=math.round(touch/b.Spec.Tick)+(aggressive and s.Side*c.MaxSlippageTicks or 0)
 if not reducing then
  local tolerance=s.Arrival+s.Side*s.PriceTolerance
  tick=s.Side==1 and math.min(tick,tolerance)or math.max(tick,tolerance)
  if aggressive and (tick-opposite/b.Spec.Tick)*s.Side<0 then return end
 end
 -- Participation and gradual schedules cap voluntary execution; risk exits retain authority.
 if s.ExitReason=='Risk'then budget=pos.Quantity end
 local size=math.min(budget,math.max(1,math.floor(a.Size*range(s,c.SliceFraction))))
 if reducing then size=math.min(size,pos.Quantity)
 else size=math.min(size,math.max(0,capacity-(pos and pos.Quantity or 0)));size=p:_fit(a,s.Side,size)end
 if size<1 then return end
 local expires=e.Time+(aggressive and c.SliceSeconds[1]or s.QuoteSeconds)
 if not reducing then expires=math.min(expires,s.Deadline)end
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=s.Side,Quantity=size,Type='Limit',Price=math.max(1,tick)*b.Spec.Tick,
  ReduceOnly=reducing,StopTicks=not reducing and a.Stop or nil,Expires=expires})
 s.NextChildAt=e.Time+range(s,c.RefillSeconds)
 if ok then
  if aggressive then if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  elseif e.Orders[result.Id]then s.ChildId=result.Id;s.ChildAt=e.Time;s.ChildPrice=tick end
  W.Budget(p,a,s)
  local held=ac.Positions[a.Key];s.PositionId=held and held.Id
  if reducing and not held then pause(e,a,s,c,false)end
 end
end
return W
