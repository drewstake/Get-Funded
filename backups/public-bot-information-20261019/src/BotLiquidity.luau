-- Passive, finite liquidity. Risk is funded by existing equity, never a cash top-up.
local Liquidity={}
function Liquidity.Protect(population,a)
 local e=population.Engine;local account=e.Accounts[a.Id];local p=account.Positions[a.Key]
 if not p or p.Triggered then return false end
 local c=population.Config.BotLiquidity;local b=e.Books[a.Key]
 local ticks=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))
 local stop=math.max(1,math.round(p.Entry/b.Spec.Tick)-p.Direction*ticks)*b.Spec.Tick
 -- Adopt legacy inventory on its next decision; never move an existing stop farther away.
 if not p.Stop or (stop-p.Stop)*p.Direction>0 then p.Stop=stop;account.Revision+=1 end
 return ((b.Last or b.Reference)*b.Spec.Tick-p.Stop)*p.Direction<=0
end
function Liquidity.Limit(population,a)
 local c=population.Config.BotLiquidity
 local e=population.Engine;local account=e.Accounts[a.Id];local b=e.Books[a.Key]
 local equity=e:Summary(account).Equity
 if equity<=a.Budget*(1-c.MaxDrawdown)then return 0 end
 local stop=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))
 return math.max(0,math.min(a.Limit,account.Limit,c.MaxInventory,
  math.floor(equity*account.Risk*c.MarginFraction/b.Spec.Margin),
  math.floor(equity*c.PositionRiskFraction/(stop*b.Spec.Tick*b.Spec.Multiplier))))
end
function Liquidity.Step(population,a)
 local e=population.Engine;local c=population.Config.BotLiquidity;local b=e.Books[a.Key]
 local account=e.Accounts[a.Id];local p=account.Positions[a.Key]
 if account.Locked or account.Liquidating or b.Spec.CloseOnly or p and p.Triggered then return end
 if a.LiquidityPolicy~=c.Version then
  -- Old random entry orders must not survive adoption. Preserve reduce-only exits.
  local ids={};for id in pairs(account.OpenOrders)do
   if not e.Orders[id].ReduceOnly then table.insert(ids,id)end
  end
  table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
  a.LiquidityQuotes={};a.LiquidityPolicy=c.Version
 end
 local limit=Liquidity.Limit(population,a);if limit<1 then return end
 e:_pruneBook(b)
 -- Exclude our own orders, so a lone stale quote cannot anchor its replacements.
 local bid,ask
 for _,o in ipairs(b.Bids)do if o.Owner~=a.Id then bid=o;break end end
 for _,o in ipairs(b.Asks)do if o.Owner~=a.Id then ask=o;break end end
 if not bid or not ask then
  for _,id in pairs(a.LiquidityQuotes)do if e.Orders[id]then e:Cancel(a.Id,id)end end
  a.LiquidityQuotes={};return
 end
 local inventory=p and p.Quantity*p.Direction or 0
 local half=math.max(1,math.ceil(b.Volatility*.5))
 -- Like reserve supply, value quotes against the generator's fundamental reference.
 -- Joining stale top-of-book prices simply transfers the old taker's losses to passive fills.
 local center=population.Markets[a.Key].Fair-inventory/limit*half
 for _,side in ipairs({1,-1})do
  local slot=tostring(side)
  local tick=side==1 and math.min(bid.Price,math.floor(center-half))or math.max(ask.Price,math.ceil(center+half))
  tick=math.max(1,tick)
  local reducing=p~=nil and side==-p.Direction
  local size=math.min(a.Size, reducing and p.Quantity or math.max(0,limit-math.abs(inventory)))
  local held=a.LiquidityQuotes[slot]and e.Orders[a.LiquidityQuotes[slot]]
  if held and (size==0 or held.ReduceOnly~=reducing or held.Remaining>size or math.abs(held.Price-tick)>=c.RepriceTicks)then
   e:Cancel(a.Id,held.Id);held=nil
  end
  if not held and size>0 then
   if not reducing then size=population:_fit(a,side,size)end
   if size>0 then
    local request={Contract=a.Key,Direction=side,Quantity=size,Type='Limit',Price=tick*b.Spec.Tick,
     ReduceOnly=reducing,Expires=e.Time+c.QuoteSeconds}
    if not reducing then request.StopTicks=math.max(c.MinStopTicks,math.min(a.Stop,c.MaxStopTicks))end
    local ok,result=e:Submit(a.Id,request)
    if ok and result.Remaining>0 then a.LiquidityQuotes[slot]=result.Id else a.LiquidityQuotes[slot]=nil end
   end
  end
 end
end
return Liquidity
