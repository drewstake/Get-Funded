-- A public estimate is a reservation price, not proof that a continuing move will reverse.
local Value={}
local Signals=require(script.Parent.BotSignals)
local Risk=require(script.Parent.BotInventory)
function Value.Step(p,a)
 local e=p.Engine;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local c=p.Config.BotValue
 if ac.Locked or ac.Liquidating or b.Spec.CloseOnly then return end
 if Risk.Manage(p,a)then return end
 local pos=ac.Positions[a.Key];local quote=Signals.Quote(p,a.Key);local bid,ask=quote.Bid,quote.Ask
 if (not bid or not ask)and not pos then Risk.CancelEntries(p,a);return end
 bid=bid or quote.Value;ask=ask or quote.Value
 if pos then
  -- Existing inventory is managed even if there is no new entry signal.
  Risk.CancelEntries(p,a)
  for id in pairs(ac.OpenOrders)do if e.Orders[id].ReduceOnly then return end end
  local fair=math.round(a.Belief)
  local tick=pos.Direction==1 and math.max(1,math.min(ask,fair))or math.max(bid,fair)
  e:Submit(a.Id,{Contract=a.Key,Direction=-pos.Direction,Quantity=pos.Quantity,Type='Limit',
   Price=tick*b.Spec.Tick,ReduceOnly=true})
  return
 end
 local window=Risk.Window(p,a)
 local side=Signals.Reversal(p,a.Key,window,ask-bid,a.EntryBuffer,c.ReversalTicks)
 local edge=side and (a.Belief-(side==1 and ask or bid))*side or 0
 if not side or edge<a.EntryBuffer then Risk.CancelEntries(p,a);return end
 local stop=Risk.StopTicks(p,a,window);local capacity=Risk.Capacity(p,a,stop)
 -- At most one working entry. Stale prices expire; unchanged entries retain FIFO.
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id]
  if o.Direction~=side or (a.Belief-o.Price)*side<a.EntryBuffer then e:Cancel(a.Id,id)
  else return end
 end
 local qty=Risk.Fit(p,a,side,a.Size,capacity);if qty<1 then return end
 local aggressive=p.Random:Next()<a.Aggression
 local tick=side==1 and (aggressive and math.min(ask+c.MaxSlippageTicks,math.floor(a.Belief-a.EntryBuffer))or bid)
  or (aggressive and math.max(bid-c.MaxSlippageTicks,math.ceil(a.Belief+a.EntryBuffer))or ask)
 e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=qty,Type='Limit',Price=math.max(1,tick)*b.Spec.Tick,
  StopTicks=stop,Expires=e.Time+math.min(a.Patience,c.EntrySeconds)})
end
return Value
