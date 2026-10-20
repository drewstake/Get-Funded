-- Passive, finite liquidity. Risk is funded by existing equity, never a cash top-up.
local Liquidity={}
local Signals=require("./BotSignals")
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
 population:_publicInformation(a)
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
 local quote=Signals.Quote(population,a.Key);local bid,ask=quote.Bid,quote.Ask
 if not bid or not ask then
  for _,id in pairs(a.LiquidityQuotes)do if e.Orders[id]then e:Cancel(a.Id,id)end end
  a.LiquidityQuotes={};return
 end
 local inventory=p and p.Quantity*p.Direction or 0
 local half=math.max(2,math.ceil(b.Volatility))
 -- Ordinary liquidity traders use the same visible midpoint as players.
 local center=quote.Value-inventory/limit*half
 for _,side in ipairs({1,-1})do
  local slot=tostring(side)
  local tick=side==1 and math.min(bid,math.floor(center-half))or math.max(ask,math.ceil(center+half))
  tick=math.max(1,tick)
  local reducing=p~=nil and side==-p.Direction
  local size=reducing and math.min(a.Size,p.Quantity) or (p and 0 or math.min(1,a.Size,limit))
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
