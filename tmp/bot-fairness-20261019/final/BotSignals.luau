-- Server-only, bounded price observations in simulated seconds (not execution count).
-- Histories live in Participants.Markets, so checkpoints retain exact signal timing.
local Signals={}
Signals.InformationVersion=1
-- Best bid/ask are public even without the depth pass. Strategies use ticks internally.
-- A one-sided/empty book falls back to the observed last price, never generator state.
function Signals.Quote(population,key)
 local e=population.Engine;local b=e.Books[key];local depth=e:PublicDepth(key,1)
 local bid=depth.Bids[1]and depth.Bids[1].Price/b.Spec.Tick
 local ask=depth.Asks[1]and depth.Asks[1].Price/b.Spec.Tick
 return {Bid=bid,Ask=ask,Value=bid and ask and (bid+ask)/2 or b.Last or b.Reference}
end
function Signals.Sample(population,key)
 local c=population.Config.BotSignals;if not c then return end
 local market=population.Markets[key];local book=population.Engine.Books[key]
 if book.Spec.CloseOnly then return end
 local now=population.Engine.Time
 local history=market.SignalHistory or {};market.SignalHistory=history
 if #history>0 and now-history[#history].Time<c.SampleSeconds then return end
 table.insert(history,{Time=now,Price=book.Last or book.Reference})
 -- Retain one observation before the window boundary for an exact backward lookup.
 while #history>2 and history[2].Time<now-c.RetentionSeconds do table.remove(history,1)end
end
function Signals.Window(population,key,seconds,confirmationSeconds)
 local history=population.Markets[key].SignalHistory
 if not history or #history==0 then return nil end
 local now=population.Engine.Time
 if now-history[#history].Time>population.Config.BotSignals.SampleSeconds*2 then return nil end
 local previous,recent
 for i=#history,1,-1 do
  local point=history[i]
  if not recent and point.Time<=now-confirmationSeconds then recent=point end
  if point.Time<=now-seconds then previous=point;break end
 end
 if not previous or not recent then return nil end
 local book=population.Engine.Books[key];local last=book.Last or book.Reference
 local low,high=last,last
 local total,duration=0,0
 for i=#history,1,-1 do
  local point=history[i];if point.Time<previous.Time then break end
  low=math.min(low,point.Price);high=math.max(high,point.Price)
 end
 -- Time-weighted observed price, excluding the newest observation. No private generator state.
 for i=1,#history-1 do
  local point=history[i];local from=math.max(previous.Time,point.Time)
  local untilTime=math.min(now,history[i+1].Time)
  if untilTime>from then total+=point.Price*(untilTime-from);duration+=untilTime-from end
 end
 return {Move=last-previous.Price,RecentMove=last-recent.Price,Low=low,High=high,Last=last,
  Mean=duration>0 and total/duration or previous.Price}
end
function Signals.Reversal(population,key,window,spread,minDeviation,reversalTicks)
 if not window then return nil end
 local fair=window.Mean
 local required=math.max(minDeviation,spread*.5+reversalTicks)
 -- A rise/fall alone is not a bargain. Require current fair-value distance AND a turn.
 if fair-window.Last>=required and window.RecentMove>=reversalTicks
  and window.Last-window.Low>=reversalTicks then return 1 end
 if window.Last-fair>=required and window.RecentMove<=-reversalTicks
  and window.High-window.Last>=reversalTicks then return -1 end
 return nil
end
return Signals
