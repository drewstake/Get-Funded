-- Persistent, funded inventory objectives. This module only submits real orders.
-- State lives on each participant and is included in world checkpoints.
local Pressure={}
function Pressure.Enabled(p,a)
 local c=p.Config.BotOrderFlow
 return c and p.Config.BotPopulation and a.PolicyVersion and c.Kinds[a.Kind]==true
end
local function cancelEntries(e,a)
 local ids={}
 for id in pairs(e.Accounts[a.Id].OpenOrders)do
  local o=e.Orders[id]
  if o and not o.ReduceOnly then table.insert(ids,id)end
 end
 table.sort(ids)
 for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
end
function Pressure.Step(p,a)
 local e,r,c=p.Engine,p.Random,p.Config.BotOrderFlow
 local b,ac=e.Books[a.Key],e.Accounts[a.Id]
 if not Pressure.Enabled(p,a)then return end
 if a.OrderFlowPolicy~=c.Version then
  cancelEntries(e,a)
  a.OrderObjective=nil;a.FlowCooldownUntil=nil
  a.FlowPositionId=ac.Positions[a.Key]and ac.Positions[a.Key].Id
  a.OrderFlowPolicy=c.Version
  a.FlowNextDecision=e.Time+r:Range(c.StartDelay[1],c.StartDelay[2])
  return
 end
 if a.FlowCooldownUntil and e.Time<a.FlowCooldownUntil then
  a.FlowNextDecision=a.FlowCooldownUntil;return
 end
 a.FlowCooldownUntil=nil
 a.FlowNextDecision=e.Time+r:Range(c.SliceSeconds[1],c.SliceSeconds[2])
 if b.Spec.CloseOnly or a.Retiring or ac.Locked or ac.Liquidating then return end
 local position=ac.Positions[a.Key]
 if position and position.Triggered then return end
 -- A stopped/externally closed position ends its mandate; do not keep buying it back.
 if a.FlowPositionId and (not position or position.Id~=a.FlowPositionId)then
  a.OrderObjective=nil;a.FlowPositionId=position and position.Id
  a.FlowNextDecision=e.Time+r:Range(c.StopPauseSeconds[1],c.StopPauseSeconds[2])
  a.FlowCooldownUntil=a.FlowNextDecision
  return
 end
 local inventory=position and position.Quantity*position.Direction or 0
 local equity=e:Summary(ac).Equity
 local capacity=math.max(0,math.min(a.Limit,ac.Limit,
  math.floor(equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin)))
 local stressed=equity<=a.Budget*(1-c.MaxDrawdown)
 local objective=a.OrderObjective
 if objective and e.Time>=objective.ExpiresAt then
  a.OrderObjective=nil
  a.FlowNextDecision=e.Time+r:Range(c.PauseSeconds[1],c.PauseSeconds[2])
  a.FlowCooldownUntil=a.FlowNextDecision
  return
 end
 if not objective then
  local side=r:Next()<.5 and 1 or -1
  -- Investors may follow an already observed move; independent mandates have no shared direction.
  local history=p.Markets[a.Key].SignalHistory or {}
  local previous
  for i=#history,1,-1 do
   if history[i].Time<=e.Time-c.LookbackSeconds then previous=history[i].Price;break end
  end
  local move=previous and (b.Last or b.Reference)-previous or 0
  if a.Kind=='Momentum' and math.abs(move)>=c.FollowMoveTicks and r:Next()<c.FollowProbability then side=move>0 and 1 or -1 end
  local fraction=r:Range(c.TargetFraction[1],c.TargetFraction[2])
  objective={Target=stressed and 0 or side*math.floor(capacity*fraction),
   ExpiresAt=e.Time+r:Range(c.DurationSeconds[1],c.DurationSeconds[2]),StartedAt=e.Time,Filled=0}
  objective.PlannedQuantity=math.abs(objective.Target-inventory)
  a.OrderObjective=objective
 end
 local target=stressed and 0 or math.clamp(objective.Target,-capacity,capacity)
 local delta=target-inventory
 if delta==0 then
  -- Hold the completed mandate until its deadline instead of immediately flipping it.
  return
 end
 local side=delta>0 and 1 or -1
 local reducing=position~=nil and side==-position.Direction
 local slice=math.max(1,math.floor(a.Size*r:Range(c.SliceFraction[1],c.SliceFraction[2])))
 local size=math.min(math.abs(delta),slice)
 if objective.PlannedQuantity and not stressed then
  -- Spread the finite mandate over its lifetime. Only real fills advance this budget.
  local progress=math.clamp((e.Time-objective.StartedAt+c.SliceSeconds[2])/
   math.max(c.SliceSeconds[2],objective.ExpiresAt-objective.StartedAt),0,1)
  local due=math.ceil(objective.PlannedQuantity*progress)
  size=math.min(size,math.max(0,due-objective.Filled))
 end
 -- Finish the existing position before opening its opposite; never reverse a reduce-only exit.
 if reducing then size=math.min(size,position.Quantity)
 else size=p:_fit(a,side,size)end
 if size<1 then return end
 local bid,ask=e:PublicPrices(a.Key)
 local touch=side==1 and ask or bid
 if not touch then return end
 local tick=math.round(touch/b.Spec.Tick)+side*c.MaxSlippageTicks
 local request={Contract=a.Key,Direction=side,Quantity=size,Type='Limit',
  Price=math.max(1,tick)*b.Spec.Tick,ReduceOnly=reducing,Expires=e.Time+c.SliceSeconds[1]}
 if not reducing then request.StopTicks=a.Stop end
 local ok,result=e:Submit(a.Id,request)
 if ok then
  objective.Filled+=result.Filled
  local held=ac.Positions[a.Key];a.FlowPositionId=held and held.Id
  -- IOC-style child: an unfilled slice cannot outlive its objective or reserve duplicate risk.
  if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
 end
end
return Pressure

