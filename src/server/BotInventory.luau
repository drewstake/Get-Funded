-- Position risk for inventory strategies. No funding, price writes or synthetic fills.
local Risk={}
local Signals=require(script.Parent.BotSignals)
local Retry=require(script.Parent.BotExitRetry)
function Risk.Config(p,a)
 local c=p.Config.BotInventory
 return p.Config.BotPopulation and a.PolicyVersion and c and c.Kinds[a.Kind]
end
function Risk.CancelEntries(p,a)
 local e=p.Engine;local ids={}
 for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id]
  if o and o.Contract==a.Key and not o.ReduceOnly then table.insert(ids,id)end
 end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
end
function Risk.Window(p,a)
 if not p.Config.BotSignals then return nil end
 local c=p.Config.BotInventory
 return Signals.Window(p,a.Key,c.LookbackSeconds,c.ConfirmationSeconds)
end
function Risk.Adverse(p,a,side,window)
 local c=p.Config.BotInventory
 return window and window.Move*side<=-c.AdverseMoveTicks and window.RecentMove*side<0
end
function Risk.StopTicks(p,a,window)
 local c=Risk.Config(p,a)
 return math.ceil(math.clamp((window and window.High-window.Low or 0)*c.RangeMultiplier,c.MinStopTicks,c.MaxStopTicks))
end
function Risk.Capacity(p,a,ticks)
 local e=p.Engine;local ac=e.Accounts[a.Id];local c=Risk.Config(p,a);local b=e.Books[a.Key]
 local equity=math.max(0,math.min(a.Budget,e:Summary(ac).Equity))
 local s=a.InventoryRisk;local scale=math.max(p.Config.BotInventory.LossSizeFloor,1/(1+(s and s.LossStreak or 0)))
 local affordable=math.max(0,math.floor(math.min(a.Limit,ac.Limit,
  a.Limit*c.InventoryFraction,equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin,
  equity*c.PositionRiskFraction/(ticks*b.Spec.Tick*b.Spec.Multiplier))))
 -- A bounded loss backoff must not strand an affordable one-contract strategy.
 -- Round the reduced size up to one only after the unscaled risk/margin check.
 return affordable>0 and math.max(1,math.floor(affordable*scale))or 0
end
function Risk.Fit(p,a,side,quantity,capacity)
 local e=p.Engine;local ac=e.Accounts[a.Id];local pos=ac.Positions[a.Key]
 local used=pos and math.max(0,pos.Quantity*pos.Direction*side)or 0
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id]
  if o and o.Contract==a.Key and o.Direction==side and not o.ReduceOnly then used+=o.Remaining end
 end
 return p:_fit(a,side,math.max(0,math.min(quantity,capacity-used)))
end
function Risk.Manage(p,a)
 local c=Risk.Config(p,a);if not c or not p.Config.BotPopulation or not a.PolicyVersion then return false end
 local e=p.Engine;local ac=e.Accounts[a.Id];local pos=ac.Positions[a.Key];local b=e.Books[a.Key]
 local s=a.InventoryRisk
 if not s or s.Version~=p.Config.BotInventory.Version then
  Risk.CancelEntries(p,a)
  s={Version=p.Config.BotInventory.Version,LossStreak=s and s.LossStreak or 0,LegacyPosition=pos and pos.Id};a.InventoryRisk=s
 end
 -- A complete stop-out can occur between decisions, before a position id was observed.
 local unobservedLoss=not s.PositionId and not pos and s.ObservedRealized and ac.Realized<s.ObservedRealized
 if unobservedLoss or s.PositionId and (not pos or s.PositionId~=pos.Id)then
  local lost=unobservedLoss or ac.Realized<(s.StartRealized or ac.Realized)
  s.LossStreak=lost and math.min(p.Config.BotInventory.MaxLossStreak,s.LossStreak+1)or 0
  s.ReadyAt=e.Time+(lost and c.LossCooldownSeconds*(1+s.LossStreak)or c.CooldownSeconds)
  s.PositionId=nil;s.OpenedAt=nil;s.Reducing=nil;s.StopTicks=nil
  Risk.CancelEntries(p,a)
 end
 s.ObservedRealized=ac.Realized
 if pos and not s.PositionId then
  s.PositionId=pos.Id;s.OpenedAt=e.Time;s.StartRealized=ac.Realized
  s.StopTicks=Risk.StopTicks(p,a,Risk.Window(p,a))
 end
 -- Falling equity, a loss streak or a wider observed range can shrink the risk budget.
 -- Withdraw over-budget entry intent before it can add to the remaining inventory.
 local capacity=Risk.Capacity(p,a,s.StopTicks or Risk.StopTicks(p,a,Risk.Window(p,a)))
 for _,side in ipairs({1,-1})do
  local used=pos and math.max(0,pos.Quantity*pos.Direction*side)or 0;local ids={}
  for id in pairs(ac.OpenOrders)do local o=e.Orders[id]
   if o and o.Contract==a.Key and o.Direction==side and not o.ReduceOnly then table.insert(ids,id)end
  end
  table.sort(ids)
  for _,id in ipairs(ids)do local o=e.Orders[id]
   if used+o.Remaining>capacity then e:Cancel(a.Id,id)else used+=o.Remaining end
  end
 end
 if pos then
  -- Retain every existing protection. Adopt unprotected legacy inventory on its decision.
  if not pos.Stop and not pos.ManualStop then
   local reference=s.LegacyPosition==pos.Id and (b.Last or b.Reference)or math.round(pos.Entry/b.Spec.Tick)
   pos.Stop=math.max(1,reference-pos.Direction*s.StopTicks)*b.Spec.Tick;ac.Revision+=1
  end
  if e.Time-s.OpenedAt>=c.MaxHoldSeconds or pos.Quantity>capacity and s.LegacyPosition~=pos.Id then s.Reducing=true end
  if pos.Triggered=='Take profit'and s.Reducing then
   e:CancelAll(a.Id,a.Key);pos.Triggered=nil;pos.Target=nil;pos.ExitOrder=nil;pos.BotExitRetry=nil;ac.Revision+=1
  elseif pos.Triggered then return true end
  if ((b.Last or b.Reference)*b.Spec.Tick-(pos.Stop or 0))*pos.Direction<=0 and pos.Stop then
   pos.Triggered='Stop loss';e:CancelAll(a.Id,a.Key)
   table.insert(e.PendingStops,{Owner=a.Id,Contract=a.Key,Position=pos.Id});e:ProcessStops();return true
  end
  if s.Reducing then
   e:CancelAll(a.Id,a.Key)
   if Retry.Ready(e,ac,a.Key,pos)then
    local ok,r=e:Submit(a.Id,{Contract=a.Key,Direction=-pos.Direction,Quantity=math.min(pos.Quantity,a.Size),Type='Market',ReduceOnly=true})
    if not ok or r.Filled==0 then Retry.Attempted(e,ac,a.Key,pos)end
   end
   return true
  end
 end
 if not pos and e.Time<(s.ReadyAt or 0)then Risk.CancelEntries(p,a);return true end
 return false
end
return Risk
