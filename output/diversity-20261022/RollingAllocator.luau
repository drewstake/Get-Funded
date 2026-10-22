-- Called after the shared account/stop/recovery guards in D.Step.
-- Only a bounded private inventory target changes; every execution remains funded and matched.
function D.Allocate(p,a,s)
 local e,c=p.Engine,p.Config.BotDiversity;local rc=c.RollingPortfolio;local ac=e.Accounts[a.Id];local b=e.Books[a.Key]
 local pos=ac.Positions[a.Key];local inventory=pos and pos.Quantity*pos.Direction or 0
 local capacity=D.Capacity(p,a);local stressed=e:Summary(ac).Equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)
 if s.Phase=='Waiting'then
  if pos or stressed or capacity<1 or e.Time<s.ReadyAt then return end
  local quantity=math.floor(capacity*s.TargetFraction);if quantity<1 then return end
  s.Target=(random(s)<.5 and 1 or -1)*quantity;s.Phase='Allocating';s.ExitReason=nil
  s.EpisodeUntil=e.Time+s.EpisodeLifetime;s.ReviewAt=e.Time+s.ReviewPeriod
 elseif not s.EpisodeUntil then
  -- Retain adopted inventory and its protections; begin review without a forced opening trade.
  if s.Phase~='Reducing'then s.Target=inventory;s.Phase='Allocating'end
  s.EpisodeUntil=e.Time+s.EpisodeLifetime;s.ReviewAt=e.Time+s.ReviewPeriod
 end
 if stressed or pos and pos.Quantity>capacity then s.Phase='Reducing';s.ExitReason='Risk'
 elseif e.Time>=s.EpisodeUntil then s.Phase='Reducing';s.ExitReason='Time' end
 if s.Phase~='Reducing'and e.Time>=s.ReviewAt then
  local change=math.max(1,math.floor(capacity*s.TargetChange))*(random(s)<.5 and 1 or -1)
  local target=math.clamp(s.Target+change,-capacity,capacity)
  -- An opposite allocation first liquidates through capped reduce-only orders and cooldown.
  if pos and target*pos.Direction<=0 then s.Target=0;s.Phase='Reducing';s.ExitReason='Reallocation'
  else s.Target=target end
  s.ReviewAt=e.Time+s.ReviewPeriod*range(s,{.75,1.25})
 end
 local exiting=s.Phase=='Reducing'
 if exiting and not pos then pause(e,a,s,c,false);return end
 local target=exiting and 0 or math.clamp(s.Target,-capacity,capacity)
 local delta=target-inventory;if delta==0 then return end
 local side=delta>0 and 1 or -1;local reducing=pos and side~=pos.Direction or false
 local size=math.min(math.abs(delta),math.max(1,math.floor(a.Size*range(s,c.SliceFraction))))
 if reducing then
  cancelEntries(e,a);local available=pos.Quantity
  for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and o.Contract==a.Key and o.ReduceOnly then available-=o.Remaining end end
  size=math.min(size,math.max(0,available))
 else size=p:_fit(a,side,size)end
 if size<1 then return end
 local bid,ask=e:PublicPrices(a.Key);local touch=side==1 and ask or bid;if not touch then return end
 local tick=math.max(1,math.round(touch/b.Spec.Tick)+side*c.MaxSlippageTicks)
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type='Limit',Price=tick*b.Spec.Tick,
  ReduceOnly=reducing,StopTicks=not reducing and a.Stop or nil,Expires=e.Time+c.SliceSeconds[1]})
 if ok then
  if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  local held=ac.Positions[a.Key]
  if held then if not s.PositionId then s.OpenedAt=e.Time end;s.PositionId=held.Id
  elseif reducing then pause(e,a,s,c,false)end
 end
end
