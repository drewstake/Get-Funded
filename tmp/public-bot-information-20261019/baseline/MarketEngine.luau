-- Deterministic, server-only price/time priority exchange. Prices are integer ticks internally.
local Engine = {}
Engine.__index = Engine
local TradeStats=require("./TradeStats")
local Protection=require("./TradeProtection")
local ContractLimits=require("./ContractLimits")
local PlayerExecution=require("./PlayerExecution")
local Protective=require("./ProtectiveOrders")
local BotExitRetry=require("./BotExitRetry")
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e12 end
local function integer(n) return finite(n) and n%1==0 end
local function sortedKeys(t)
 local keys={} for k in pairs(t) do table.insert(keys,k) end table.sort(keys) return keys
end
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
function Engine.new(config, seed)
 local self=setmetatable({Config=config,Seed=seed,Time=0,Step=0,Books={},Accounts={},AccountOrder={},Orders={},OrderArchive={},
  NextOrder=0,NextPriority=0,NextTrade=0,Trades={},PendingStops={},TotalVolume=0,TradeHash=0},Engine)
 for _,key in ipairs(config.ContractOrder) do
  local c=config.Contracts[key]
  local candles={} for _,tf in ipairs(config.Timeframes) do candles[tf[1]]={} end
  self.Books[key]={Key=key,Spec=c,Bids={},Asks={},Last=nil,Open=nil,Reference=math.round(c.Last/c.Tick),Volume=0,
   Candles=candles,CandleVolume={},Recent={},Up=0,Down=0,Volatility=1}
 end
 return self
end
function Engine:AddAccount(id,base,limit,risk,isPlayer)
 if self.Accounts[id] then return self.Accounts[id] end
 local a={Id=id,Base=base,Balance=base,Realized=0,CashFlow=0,Positions={},OpenOrders={},History={},Fills={},
  Limit=limit,Risk=risk,Player=isPlayer==true,Revision=0,Locked=false,LossLimit=base}
 -- Player accounts carry lifetime trading statistics from their first execution.
 if a.Player then a.Stats=TradeStats.New("Live");self:ContractLimit(a) end
 self.Accounts[id]=a table.insert(self.AccountOrder,id) return a
end
-- Recalculate from closed balance on every capacity read, including restored accounts.
-- Limit remains a cached field for checkpoint compatibility, never an authority for players.
function Engine:ContractLimit(a)
 if a.Player then a.Limit=ContractLimits.ForBalance(a.Balance) end
 return a.Limit
end
function Engine:Summary(a)
 local unrealized,count,margin=0,0,0
 for _,key in ipairs(self.Config.ContractOrder) do
  local b=self.Books[key] local p=a.Positions[key]
  if p then
   unrealized+=((b.Last or b.Reference)*b.Spec.Tick-(p.PnlEntry or p.Entry))*p.Quantity*p.Direction*b.Spec.Multiplier
   count+=1 margin+=p.Quantity*b.Spec.Margin
  end
 end
 -- Funded accounts liquidate on equity depletion; margin limits apply to new exposure.
 return {Balance=a.Balance,Equity=a.Balance+unrealized,Unrealized=unrealized,Session=a.Balance+unrealized-a.Base-(a.PnlBaseline or 0),
  Allowance=math.max(0,a.Balance+unrealized),Count=count,Margin=margin}
end
function Engine:Exposure(a,key,side,qty,summary)
 local limit=self:ContractLimit(a)
 local used,total=0,0
 local pending={}
 for id in pairs(a.OpenOrders)do
  local o=self.Orders[id]
  if o and not o.ReduceOnly then
   local held=pending[o.Contract]or {0,0};pending[o.Contract]=held
   local index=o.Direction==1 and 1 or 2;held[index]+=o.Remaining
  end
 end
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol] local net=p and p.Quantity*p.Direction or 0
  local held=pending[symbol];local buy,sell=held and held[1]or 0,held and held[2]or 0
  if symbol==key then if side==1 then buy+=qty else sell+=qty end end
  local worst=math.max(math.abs(net+buy),math.abs(net-sell))
  if worst>limit then return false end
  total+=worst
  used+=worst*self.Books[symbol].Spec.Margin
 end
 return (not a.Player or total<=limit) and used<=math.max(0,(summary or self:Summary(a)).Equity)*a.Risk
end
-- Maximum additional order in this direction, reserving worst-case independent entry fills.
-- Reduce-only exits cannot create exposure and do not consume entry capacity.
-- Players receive one contract per full $1,000 of closed balance, with a minimum of five.
-- Positions and working entries share that total across instruments. Open P&L and simulated
-- margin do not change it. Depleted accounts still cannot open new exposure.
function Engine:OrderCapacity(a,key,side,stopTicks,excludeOrder,summary)
 if a.Resetting then return 0,"Account reset is liquidating positions."end
 if (summary or self:Summary(a)).Equity<=0 then return 0,"Account equity reached $0." end -- failure rule: depletes on the next step
 local otherCount,net,same,opposite=0,0,0,0
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol] local position=p and p.Quantity*p.Direction or 0
  local buy,sell=0,0
  for id in pairs(a.OpenOrders) do
   local o=self.Orders[id]
   if id~=excludeOrder and o and not o.ReduceOnly and o.Contract==symbol then
    if o.Direction==1 then buy+=o.Remaining else sell+=o.Remaining end
   end
  end
  if symbol==key then net=position;same=side==1 and buy or sell;opposite=side==1 and sell or buy
  else otherCount+=math.max(math.abs(position+buy),math.abs(position-sell)) end
 end
 local limit=self:ContractLimit(a)
 local allowed=limit-otherCount
 local reason="Account contract limit ("..limit.." total), including working orders."
 if math.abs(net-side*opposite)>allowed then return 0,reason end
 local maximum=math.max(0,math.floor(allowed-side*net-same))
 return maximum,reason
end
function Engine:CapacityMessage(a,key,side,stopTicks)
 local maximum,reason=self:OrderCapacity(a,key,side,stopTicks)
 return reason.." Maximum currently available: "..maximum.." "..key.."."
end
-- Armed stop entries by contract. Derived from Orders (never saved), so a restored world rebuilds it.
function Engine:_stopIndex()
 if not self.Stops then
  self.Stops={}
  for id,o in pairs(self.Orders) do
   if o.Type=="Stop" then self.Stops[o.Contract]=self.Stops[o.Contract] or {} self.Stops[o.Contract][id]=true end
  end
 end
 return self.Stops
end
function Engine:_retire(o,status)
 if o.Type=="Limit"then local b=self.Books[o.Contract];b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1 end
 if o.Type=="Stop" and self.Stops and self.Stops[o.Contract] then self.Stops[o.Contract][o.Id]=nil end
 o.Status=status self.Accounts[o.Owner].OpenOrders[o.Id]=nil
 o.StatusHistory=o.StatusHistory or {}
 table.insert(o.StatusHistory,{Step=self.Step,Time=self.Time,Status=status,Reason=o.BlockedReason or status})
 if #o.StatusHistory>16 then table.remove(o.StatusHistory,1)end
 self.Orders[o.Id]=nil
 if o.Protection then Protective.Mark(self,self.Accounts[o.Owner],o.Contract)end
 table.insert(self.OrderArchive,o)
 if #self.OrderArchive>self.Config.MaxOrderHistory then table.remove(self.OrderArchive,1) end
end
function Engine:Cancel(owner,id)
 local o=self.Orders[id]
 if not o or o.Owner~=owner then return false,"Order is no longer working." end
 local p=self.Accounts[owner].Positions[o.Contract]
 if o.ReduceOnly and p and p.ExitOrder==o.Id and p.Triggered=="Player close"then p.ExitOrder=nil;p.Triggered=nil end
 self:_unrest(self.Books[o.Contract],o)
 o.Cancelled+=o.Remaining o.Remaining=0 self:_retire(o,"Cancelled")
 self.Accounts[owner].Revision+=1
 return true,"Order cancelled."
end
function Engine:CancelAll(owner,key)
 local a=self.Accounts[owner]
 for _,id in ipairs(sortedKeys(a.OpenOrders)) do
  local o=self.Orders[id] if o and (not key or o.Contract==key) then self:Cancel(owner,id) end
 end
end
function Engine:_cleanBook(b)
 for _,side in ipairs({b.Bids,b.Asks}) do
  for i=#side,1,-1 do
   local level=side[i] local quantity=0
   for j=#level.Orders,1,-1 do
    local o=level.Orders[j]
    if o.Remaining<=0 then table.remove(level.Orders,j) else quantity+=o.Remaining end
   end
   level.Quantity=quantity if quantity==0 then table.remove(side,i) end
  end
 end
end
function Engine:_rest(b,o)
 o.Queued=nil
 self:_blocked(o,not PlayerExecution.Allows(self,b,o.Price,-o.Direction)and "Waiting · price safeguard"or nil)
 b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
 local levels=o.Direction==1 and b.Bids or b.Asks
 -- Price levels are sorted; binary search avoids scanning every level on entry.
 local lo,hi=1,#levels
 while lo<=hi do
  local mid=math.floor((lo+hi)/2);local l=levels[mid]
  if l.Price==o.Price then
   local index=#l.Orders+1
   if l.Orders[#l.Orders]and (o.Priority or o.Id)<(l.Orders[#l.Orders].Priority or l.Orders[#l.Orders].Id)then
    local first,last=1,#l.Orders
    while first<=last do local mid=math.floor((first+last)/2);local held=l.Orders[mid]
     if (o.Priority or o.Id)<(held.Priority or held.Id)then last=mid-1 else first=mid+1 end
    end
    index=first
   end
   table.insert(l.Orders,index,o);l.Quantity+=o.Remaining;return
  end
  if (o.Price-l.Price)*o.Direction>0 then hi=mid-1 else lo=mid+1 end
 end
 table.insert(levels,lo,{Price=o.Price,Quantity=o.Remaining,Orders={o}})
end
function Engine:_fillAccount(o,price,qty,tradeId)
 self.EligibilityRevision=(self.EligibilityRevision or 0)+1
 self.ReductionDirty=self.ReductionDirty or {};self.ReductionDirty[o.Owner]=true
 local a=self.Accounts[o.Owner] local b=self.Books[o.Contract] local p=a.Positions[o.Contract]
 local side=o.Direction local oldNet=p and p.Quantity*p.Direction or 0 local delta=side*qty
 if o.Protection=="Take profit"and p then
  p.Triggered="Take profit";p.ExitOrder=o.Id;p.TargetFilled=(p.TargetFilled or 0)+qty
  table.insert(self.PendingStops,{Owner=a.Id,Contract=o.Contract,Position=p.Id})
 end
 a.CashFlow-=price*delta*b.Spec.Multiplier -- double-entry notional audit ledger; not spendable futures cash
 local realized=0 local closedRow
 if p and oldNet*delta<0 then
  local closed=math.min(math.abs(oldNet),qty)
  -- A saved account from before lifetime stats is migrated before this execution changes its ledger.
  if a.Player and (type(a.Stats)~="table" or a.Stats.V~=TradeStats.Version or a.Stats.DayV~=1) then TradeStats.Reconcile(self,a,os.time()) end
  realized=(price-(p.PnlEntry or p.Entry))*closed*p.Direction*b.Spec.Multiplier
  a.Realized+=realized;a.Balance=a.Base+(a.PnlBaseline or 0)+a.Realized
  self:ContractLimit(a)
  -- Persist eligibility independently of the bounded display history, including break-even closes.
  a.CompletedTrades=(a.CompletedTrades or #a.History)+1
  table.insert(a.History,1,{PositionId=p.Id,Contract=o.Contract,Direction=p.Direction,Quantity=closed,Entry=p.Entry,PnlEntry=p.PnlEntry,Exit=price,Pnl=realized,
   Time=string.format("%02d:%02d:%02d",math.floor(self.Time/3600)%24,math.floor(self.Time/60)%60,math.floor(self.Time)%60),ClosedAt=os.time(),TradeId=tradeId,
   Reason=o.Protection or p.Triggered or "Trade"})
  -- Lifetime counters update on the same execution; trimming the display history below never changes them.
  if a.Player then TradeStats.Add(a.Stats,a.History[1]) end
  closedRow=a.History[1]
  if #a.History>self.Config.MaxAccountHistory then table.remove(a.History) end
 end
 local net=oldNet+delta
 if net==0 then a.Positions[o.Contract]=nil
 elseif not p or oldNet*net<0 then
  p={Id=o.Id,Contract=o.Contract,Direction=net>0 and 1 or -1,Quantity=math.abs(net),Entry=price}
  a.Positions[o.Contract]=p
 else
  if oldNet*delta>0 then
   if p.PnlEntry then p.PnlEntry=(p.PnlEntry*math.abs(oldNet)+price*qty)/math.abs(net)end
   p.Entry=(p.Entry*math.abs(oldNet)+price*qty)/math.abs(net)
  end
  p.Quantity=math.abs(net)
 end
 p=a.Positions[o.Contract]
 if p and not o.ReduceOnly and p.Direction==side then
  -- Existing player protections keep their exact prices through every scale-in fill.
  -- Only absent levels initialize from the ticket; both cover the updated full quantity.
  if o.StopTicks and not p.ManualStop and (not a.Player or p.Stop==nil)then
   local stop=math.round((p.Entry-side*o.StopTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick
   -- Adding to a losing bot position must not move its existing stop farther away.
   if not p.Stop or (stop-p.Stop)*side>0 then p.Stop=stop end
  end
  if o.TargetTicks and not p.ManualTarget and (not a.Player or p.Target==nil)then p.Target=math.round((p.Entry+side*o.TargetTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick end
 end
 o.Remaining-=qty o.Filled+=qty o.Notional+=price*qty
 a.Revision+=1
 Protective.Mark(self,a,o.Contract)
 if a.Player then
  table.insert(a.Fills,1,{TradeId=tradeId,OrderId=o.Id,Contract=o.Contract,Direction=side,Quantity=qty,Price=price,
   Slippage=(price-o.Reference*b.Spec.Tick)*side,Time=self.Time})
  if #a.Fills>40 then table.remove(a.Fills) end
 end
 return closedRow
end
-- Notifications run only after BOTH ledger entries and tape/candle totals commit.
-- A UI/progression callback must not interrupt settlement between counterparties.
function Engine:_notifyClose(owner,row)
 if row and self.OnFundedClose then
  local ok,err=pcall(self.OnFundedClose,self.Accounts[owner],row)
  if not ok then
   self.CloseNotificationErrors=(self.CloseNotificationErrors or 0)+1
   self.LastCloseNotificationError={TradeId=row.TradeId,Owner=owner,Message=tostring(err)}
  end
 end
end
-- The historical house ledger is retained ONLY for atomic administrative migrations/resets.
-- Ordinary player orders use the same finite, executable book as participants.
Engine.HouseId="house:player-fills"
function Engine:_house()
 local h=self.Accounts[Engine.HouseId]
 if not h then h=self:AddAccount(Engine.HouseId,0,1e9,1,false) h.House=true end
 return h
end
function Engine:_touch(b,side)
 local level=(side==1 and b.Asks or b.Bids)[1]
 if level then return level.Price end
 -- The requested side is empty: fall back to the last trade/reference, but never through the opposite
 -- quote. A buy fallback is at least the best bid and a sell fallback at most the best ask, so the
 -- effective spread can never cross and an immediate round trip cannot profit from the fallback alone.
 -- Only trusted administrative settlement uses this fallback; ordinary closes/liquidations need liquidity.
 local fallback=b.Last or b.Reference
 local opposite=(side==1 and b.Bids or b.Asks)[1]
 if opposite and (opposite.Price-fallback)*side>0 then fallback=opposite.Price end
 return fallback
end
function Engine:_playerFill(o,ticks,qty)
 local b=self.Books[o.Contract]
 self.NextTrade+=1 -- fill ids share the trade sequence so history/stats ids stay monotonic; no tape entry
 local price=ticks*b.Spec.Tick
 local house=self:_house()
 local mirror={Id=o.Id,Owner=house.Id,Contract=o.Contract,Direction=-o.Direction,Remaining=qty,Filled=0,Notional=0,Reference=o.Reference}
 local own=self:_fillAccount(o,price,qty,self.NextTrade)
 local other=self:_fillAccount(mirror,price,qty,self.NextTrade)
 self.PlayerFills=(self.PlayerFills or 0)+1
 self:_notifyClose(o.Owner,own);self:_notifyClose(mirror.Owner,other)
end
-- Arrival priority is separate from the stable order id: repricing loses time priority.
function Engine:_priority()
 self.NextPriority=math.max(self.NextPriority or 0,self.NextOrder)+1
 return self.NextPriority
end
function Engine:_unrest(b,o)
 local levels=o.Direction==1 and b.Bids or b.Asks
 if o.Type~="Limit"then return end
 local lo,hi=1,#levels
 while lo<=hi do
  local mid=math.floor((lo+hi)/2);local level=levels[mid]
  if level.Price==o.Price then
   local index=table.find(level.Orders,o)
   if index then
    table.remove(level.Orders,index);level.Quantity-=o.Remaining
    if #level.Orders==0 then table.remove(levels,mid)end
    b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
   end
   return
  end
  if (o.Price-level.Price)*o.Direction>0 then hi=mid-1 else lo=mid+1 end
 end
end
function Engine:_available(o,resting,summaries)
 local a=self.Accounts[o.Owner]
 if not a or self.Orders[o.Id]~=o or o.Remaining<=0 then return 0,"Order is not active"end
 if o.Expires and o.Expires<=self.Time then return 0,"Order expired"end
 if a.Retired or a.LegacyRetired then return 0,"Account retired"end
 if self.Books[o.Contract].Spec.CloseOnly and not o.ReduceOnly then return 0,"Market is close-only"end
 if o.ProtectivePosition and not Protective.Valid(self,a,o)then return 0,"Protective position changed"end
 if a.Player and self.ConnectedOwners and not self.ConnectedOwners[a.Id]and (resting or not o.ReduceOnly)then return 0,"Owner disconnected"end
 if o.ReduceOnly then
  local p=a.Positions[o.Contract]
  if o.ReductionPosition and (not p or p.Id~=o.ReductionPosition)then return 0,"Reducing position changed"end
  return p and p.Direction~=o.Direction and math.min(o.Remaining,p.Quantity)or 0,"No position to reduce"
 end
 if a.Locked or a.Liquidating then return 0,"Account is closing positions"end
 local summary=summaries and summaries[a.Id]
 if not summary then summary=self:Summary(a);if summaries then summaries[a.Id]=summary end end
 if summary.Equity<=0 then return 0,"Account equity depleted"end
 if a.Player and self:OrderCapacity(a,o.Contract,o.Direction,o.StopTicks,o.Id,summary)<o.Remaining then return 0,"Account contract limit changed"end
 if not a.Player then
  if summary.OrdersEligible==nil then summary.OrdersEligible=self:Exposure(a,o.Contract,o.Direction,0,summary)end
  if not summary.OrdersEligible then return 0,"Insufficient margin or inventory capacity"end
 end
 return o.Remaining
end
function Engine:_syncReductions()
 local dirty=self.ReductionDirty;self.ReductionDirty=nil
 if not dirty then return end
 for _,owner in ipairs(sortedKeys(dirty))do
  local a=self.Accounts[owner]
  for _,id in ipairs(sortedKeys(a.OpenOrders))do
   local o=self.Orders[id]
   if o and o.ReduceOnly and o.Remaining>0 then
    local p=a.Positions[o.Contract]
    if not p or p.Direction==o.Direction or o.ReductionPosition and o.ReductionPosition~=p.Id then
     self:Cancel(owner,id)
    elseif o.Remaining>p.Quantity then
     o.Cancelled+=o.Remaining-p.Quantity;o.Remaining=p.Quantity
     self:_cleanBook(self.Books[o.Contract]);a.Revision+=1
     local b=self.Books[o.Contract];b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
    end
   end
  end
 end
end
-- Record transitions, not a row on every retry. The bounded order-local history is checkpointed.
function Engine:_blocked(o,reason)
 local status=reason and "Blocked"or o.Queued and "Waiting for matching"or "Working"
 if o.BlockedReason==reason and o.Status==status then return end
 o.BlockedReason=reason;o.Status=status
 o.StatusHistory=o.StatusHistory or {}
 table.insert(o.StatusHistory,{Step=self.Step,Time=self.Time,Reason=reason or "Eligible",Status=o.Status})
 if #o.StatusHistory>16 then table.remove(o.StatusHistory,1)end
 self.Accounts[o.Owner].Revision+=1
end
function Engine:OrderBlockReason(o)
 local available,reason=self:_available(o,not o.Queued)
 if available<=0 then return reason end
 if o.Type=="Limit"and not o.Queued then
  return not PlayerExecution.Allows(self,self.Books[o.Contract],o.Price,-o.Direction)and "Waiting · price safeguard"or nil
 end
 return o.BlockedReason
end
function Engine:_pruneBook(b)
 -- Eligibility cannot change during this non-yielding scan. Reuse each account's
 -- mark calculation only for this scan; no stale cache survives a fill or request.
 local summaries={}
 for _,side in ipairs({b.Bids,b.Asks})do for _,level in ipairs(side)do for _,o in ipairs(level.Orders)do
  if o.Remaining>0 then
   local available,reason=self:_available(o,true,summaries)
   if available<o.Remaining then
    o.Cancelled+=o.Remaining-available;o.Remaining=available;self.Accounts[o.Owner].Revision+=1
    if available==0 then self:_blocked(o,reason);self:_retire(o,"No longer eligible")end
   end
   if available>0 then self:_blocked(o,not PlayerExecution.Allows(self,b,o.Price,-o.Direction)and "Waiting · price safeguard"or nil)end
  end
 end end end
 self:_cleanBook(b)
end
-- A live server supplies connected owners. Offline positions keep protection, but their
-- resting orders are cancelled so they cannot appear as another connected player's liquidity.
function Engine:SetConnectedOwners(owners)
 self.ConnectedOwners=table.clone(owners)
 for _,id in ipairs(self.AccountOrder)do
  local a=self.Accounts[id]
  if a.Player and not owners[id]then self:CancelAll(id)end
  if a.Player then for key in pairs(a.Positions)do Protective.Mark(self,a,key)end end
 end
 Protective.Sync(self,true)
end
function Engine:SetConnected(owner,connected)
 if not self.ConnectedOwners then return end
 self.ConnectedOwners[owner]=connected and true or nil
 if not connected and self.Accounts[owner]then self:CancelAll(owner)end
 local a=self.Accounts[owner];if a then for key in pairs(a.Positions)do Protective.Mark(self,a,key)end end
 Protective.Sync(self,true)
end
function Engine:_trade(b,incoming,resting,qty)
 b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
 local tick=resting.Price local price=tick*b.Spec.Tick
 self.NextTrade+=1
 local trade={Id=self.NextTrade,Time=self.Time,Step=self.Step,Contract=b.Key,Price=price,Ticks=tick,Quantity=qty,
  IncomingOrder=incoming.Id,RestingOrder=resting.Id,Aggressor=incoming.Direction,FairReference=b.FairReference,
  RestingPriority=resting.Priority,IncomingPriority=incoming.Priority,
  Buyer=incoming.Direction==1 and incoming.Owner or resting.Owner,Seller=incoming.Direction==-1 and incoming.Owner or resting.Owner}
 local incomingClose=self:_fillAccount(incoming,price,qty,trade.Id)
 local restingClose=self:_fillAccount(resting,price,qty,trade.Id)
 PlayerExecution.Record(self,self.Accounts[incoming.Owner],b,incoming.Direction,qty,incoming)
 local prior=b.Last
 if prior then
  if tick>prior then b.Up+=1 elseif tick<prior then b.Down+=1 end
  b.Volatility=b.Volatility*0.96+math.abs(tick-prior)*0.04
 end
 -- Sole writer of last price. Quotes, regimes and news never set this field.
 b.Last=tick b.Open=b.Open or tick b.Volume+=qty self.TotalVolume+=qty
 table.insert(b.Recent,tick) if #b.Recent>64 then table.remove(b.Recent,1) end
 -- Stop entries latch on the execution that reaches them; ProcessStops submits them at market.
 local armed=self:_stopIndex()[b.Key]
 if armed and next(armed) then
  for id in pairs(armed) do
   local o=self.Orders[id]
   if o and not o.Triggered and (tick-o.Price)*o.Direction>=0 then o.Triggered=self.Time end
  end
 end
 table.insert(self.Trades,trade) if #self.Trades>self.Config.MaxTradeHistory then table.remove(self.Trades,1) end
 self.TradeHash=(self.TradeHash*31+tick*7+qty*13+trade.Id+self.Step)%2147483647
 for _,tf in ipairs(self.Config.Timeframes) do
  local series=b.Candles[tf[1]] local bucket=math.floor(self.Time/tf[2])*tf[2] local candle=series[#series]
  if not candle or candle.Time~=bucket then
   candle={Time=bucket,Open=price,High=price,Low=price,Close=price,Volume=0}
   table.insert(series,candle) if #series>self.Config.MaxCandles then table.remove(series,1) end
  end
  candle.High=math.max(candle.High,price) candle.Low=math.min(candle.Low,price) candle.Close=price candle.Volume+=qty
  b.CandleVolume[tf[1]]=(b.CandleVolume[tf[1]] or 0)+qty
 end
 -- Latch on each execution so an intrastep crossing cannot be missed.
 for _,id in ipairs(self.AccountOrder) do
  local account=self.Accounts[id]
  if account.Player and not account.Locked and self:Summary(account).Equity<=0 then
   account.Locked=true account.Liquidating=true account.Revision+=1
   -- One depletion per attempt: the marker is saved with the account and never re-counted.
   account.Depleted=true account.DepletedAt=account.DepletedAt or self.Time
   for symbol,position in pairs(account.Positions) do
    position.Triggered=account.Resetting and "Account reset"or "Account depleted" position.Stop=nil position.Target=nil
    table.insert(self.PendingStops,{Owner=id,Contract=symbol,Position=position.Id})
   end
  end
  local p=account.Positions[b.Key]
  if p and (not p.Triggered or account.Player and p.Triggered=="Take profit")then
   local reason
   if p.Stop and (price-p.Stop)*p.Direction<=0 then reason="Stop loss"
   elseif not p.Triggered and p.Target and (price-p.Target)*p.Direction>=0 then reason="Take profit" end
   if reason then
    p.Triggered=reason
    if reason=="Stop loss" then p.Target=nil elseif not account.Player then p.Stop=nil end
    account.Revision+=1;Protective.Mark(self,account,b.Key)
    table.insert(self.PendingStops,{Owner=id,Contract=b.Key,Position=p.Id})
   end
  end
 end
 self:_notifyClose(incoming.Owner,incomingClose);self:_notifyClose(resting.Owner,restingClose)
end
-- `internal` is engine-only; administrative settlement is never accepted from order requests.
function Engine:Submit(owner,request,internal)
 local ok,result=self:_submit(owner,request,internal)
 if not ok then
  self.ExecutionDiagnostics=self.ExecutionDiagnostics or {RejectedCount=0,RecentRejections={}}
  local diagnostics=self.ExecutionDiagnostics;diagnostics.RejectedCount+=1
  local row={Owner=owner,Step=self.Step,Time=self.Time,Reason=tostring(result)}
  if type(request)=="table"then row.Contract=request.Contract;row.Type=request.Type;row.Quantity=request.Quantity end
  table.insert(diagnostics.RecentRejections,row)
  if #diagnostics.RecentRejections>64 then table.remove(diagnostics.RecentRejections,1)end
 end
 return ok,result
end
function Engine:_submit(owner,request,internal)
 local a=self.Accounts[owner]
 if not a or type(request)~="table" then return false,"Unknown account." end
 if a.Resetting and not internal then return false,"Reset in progress. Wait for positions to finish liquidating."end
 if (a.LegacyRetired or a.Retired) and not internal then return false,"This account is archived and cannot trade." end
 local b=self.Books[request.Contract]
 local side,qty,kind=request.Direction,request.Quantity,request.Type
 if not b or (side~=1 and side~=-1) or not integer(qty) or qty<1 then return false,"Choose a market, Buy or Sell, and a whole number of contracts starting at 1." end
 if not a.Player and qty>(a.LiquidityProvider and 100000000 or 10000) then return false,"Invalid quantity." end
 if kind~="Market" and kind~="Limit" and kind~="Stop" then return false,"Use Market, Limit or Stop." end
 local execution=request.Execution or (request.ReduceOnly==true and "Sliced" or "Immediate")
 if execution~="Immediate"and execution~="Sliced"then return false,"Choose immediate or sliced execution."end
 local p=a.Positions[b.Key]
 local reducing=request.ReduceOnly==true
 local protection=internal and internal.Protection
 if protection and (not reducing or not p or internal.PositionId~=p.Id or side~=-p.Direction
  or not(protection=="Take profit"and p.Target==request.Price and kind=="Limit"and(not p.Triggered or p.Triggered==protection)
   or protection==p.Triggered and(protection=="Stop loss"or protection=="Account depleted"or protection=="Margin liquidation"or protection=="Account reset"and a.Resetting)))then
  return false,"Protective exit no longer matches its position."
 end
 if reducing and (not p or p.Direction==side or qty>p.Quantity) then return false,"No matching position to reduce." end
 if a.Player and self.ConnectedOwners and not self.ConnectedOwners[owner]and not reducing then return false,"Player is no longer connected."end
 if a.Locked and not reducing then return false,"Account failed. Maximum currently available: 0 "..b.Key..". Close positions only." end
 if b.Spec.CloseOnly and not reducing then return false,b.Key.." is a retired market and is close-only. Choose an available market for new trades." end
 if a.Liquidating and not reducing then return false,"Closing failed account positions. Maximum currently available: 0 "..b.Key..". Wait for positions to close." end
 local price=request.Price
 if kind=="Limit" or kind=="Stop" then
  if not finite(price) or price<=0 or math.abs(price/b.Spec.Tick-math.round(price/b.Spec.Tick))>0.00001 then return false,kind.." price must match the market's price increments (ticks)." end
  price=math.round(price/b.Spec.Tick)
  if not protection and math.abs(price-(b.Last or b.Reference))>(b.Last or b.Reference)*self.Config.PriceBandFraction then return false,kind.." is outside the price band." end
 end
 -- Stop entries wait off-book and become market orders when a trade reaches the stop price.
 -- A buy stop sits above the last trade and a sell stop below it; exits use SL/TP instead.
 if kind=="Stop" then
  if reducing or not a.Player then return false,"Stop orders are entry orders for player accounts. Use SL/TP to protect a position." end
  local last=b.Last or b.Reference
  if (price-last)*side<=0 then return false,side==1 and "Stop buy must be above the current price." or "Stop sell must be below the current price." end
 end
 -- Normalize once on the server; callers cannot smuggle conflicting distances.
 request=copy(request)
 for _,field in ipairs({"Stop","Target"}) do
  if request[field.."Dollars"]~=nil then
   if request[field.."Ticks"]~=nil then return false,"Use dollars or ticks, not both." end
   local resolved,err=Protection.Resolve(b.Spec,qty,request[field.."Dollars"])
   if not resolved then return false,err end
   request[field.."Ticks"]=resolved.Ticks
  end
 end
 for _,field in ipairs({"StopTicks","TargetTicks"}) do
  local v=request[field]
  if v~=nil and (not integer(v) or v<1 or v>Protection.MaximumTicks(b.Spec,qty))then
   return false,"Protection must use positive whole ticks within the $1,000,000,000 amount limit."
  end
 end
 if a.Player then
  local n=0 for id in pairs(a.OpenOrders) do if not self.Orders[id].Protection then n+=1 end end
  if n>=self.Config.MaxPlayerOrders and not reducing then return false,"Too many working orders. Maximum currently available: 0 "..b.Key..". Cancel an order first." end
  if not reducing then
   local maximum=self:OrderCapacity(a,b.Key,side,request.StopTicks)
   if qty>maximum then return false,self:CapacityMessage(a,b.Key,side,request.StopTicks) end
  end
 end
 if not a.Player and not reducing and not self:Exposure(a,b.Key,side,qty) then return false,"Insufficient margin or inventory capacity." end
 if kind=="Limit"and execution=="Immediate"and not PlayerExecution.StandardLimitAllowed(self,a,b,{Direction=side,Contract=b.Key},price,qty)then
  return false,"Limit order exceeds current execution safeguards. Choose a non-marketable price or reduce quantity. No order placed."
 end
 self:_pruneBook(b)
 local opposing=side==1 and b.Asks or b.Bids
 self.NextOrder+=1
 local o={Id=self.NextOrder,Priority=self:_priority(),Owner=owner,Contract=b.Key,Direction=side,Original=qty,Remaining=qty,Filled=0,Cancelled=0,Notional=0,
  Price=price,Type=kind,Status="Working",Time=self.Time,Reference=opposing[1] and opposing[1].Price or b.Last or b.Reference,
  SubmittedStep=self.Step,RequestSequence=self.RequestContext and self.RequestContext.Sequence,
  StopTicks=request.StopTicks,TargetTicks=request.TargetTicks,ReduceOnly=reducing,Expires=request.Expires,
  ReductionPosition=reducing and p.Id or nil,
  Execution=execution,Immediate=internal and internal.Immediate or nil,
  Protection=protection,ProtectivePosition=protection and p.Id or nil,
  Link=integer(request.Link) and request.Link or nil} -- server-set lead order id for copied orders
 self.Orders[o.Id]=o a.OpenOrders[o.Id]=true
 if protection=="Take profit"then p.TargetOrder=o.Id;if p.Triggered==protection then p.ExitOrder=o.Id end end
 if protection and internal.DeferProtection then
  local crossed=opposing[1]and(opposing[1].Price-price)*side<=0
  if crossed or self.ConnectedOwners and not self.ConnectedOwners[owner]or not PlayerExecution.Allows(self,b,price,side)then
   o.Queued=true;o.Status="Waiting for matching"
  else self:_rest(b,o)end
  return true,{Id=o.Id,Filled=0,Remaining=qty,Cancelled=0,Status=o.Status}
 end
 if kind=="Stop" then
  -- Armed, not matched: the order reserves capacity like a working limit until it triggers.
  o.Status="Armed" local index=self:_stopIndex() index[b.Key]=index[b.Key] or {} index[b.Key][o.Id]=true
  a.Revision+=1
  return true,{Id=o.Id,Filled=0,Remaining=o.Remaining,Cancelled=0,Average=nil,Status="Stop armed",Slippage=0}
 end
 if internal and internal.AdministrativeSettlement and a.Player and reducing then
  self:_playerFill(o,self:_touch(b,side),qty);self:_retire(o,"Filled")
  return true,{Id=o.Id,Filled=o.Filled,Remaining=0,Cancelled=0,Average=o.Notional/o.Filled,Status=o.Status}
 end
 return self:_match(a,b,o)
end
function Engine:_match(a,b,o)
 -- Check only orders reached by this match. Whole-book maintenance runs once at
 -- a simulation boundary; client snapshots never retire orders or affect replay.
 local wasQueued=o.Queued;o.Queued=nil
 local side=o.Direction;local reducing=o.ReduceOnly
 local managed=a.Player and self.Config.PlayerExecution
 local protected=Protective.Valid(self,a,o)
 local sliced=o.Execution=="Sliced"or wasQueued and o.Execution==nil
 local allowance=protected and math.huge or managed and math.min(sliced and self.Config.PlayerExecution.SliceContracts or math.huge,PlayerExecution.Budget(self,a,b,o))or math.huge
 local limited=false
 if not reducing and o.Type=="Limit"and not PlayerExecution.Allows(self,b,o.Price,side)then
  limited=true;self:_blocked(o,"Waiting · price safeguard")
 end
 local opposing=side==1 and b.Asks or b.Bids
 for _,level in ipairs(opposing)do
  if o.Remaining<=0 or self:_available(o,false)<=0 then break end
  if o.Type=="Limit"and (level.Price-o.Price)*side>0 then break end
  if allowance<=0 or not PlayerExecution.Allows(self,b,level.Price,side)then
   limited=true;self:_blocked(o,allowance<=0 and "Waiting · execution allowance"or "Waiting · price safeguard");break
  end
  for _,resting in ipairs(level.Orders)do
   local incoming=self:_available(o,false)
   if o.Remaining<=0 or incoming<=0 then break end
   if resting.Remaining>0 then
    local ra=self.Accounts[resting.Owner]
    if resting.Owner==o.Owner or (a.Group and ra.Group==a.Group)or (a.ProfileId and ra.ProfileId==a.ProfileId)then
     resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"Self-trade prevented");ra.Revision+=1
    else
     local available,reason=self:_available(resting,true)
     if available<=0 then
      self:_blocked(resting,reason);resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"No longer eligible");ra.Revision+=1
     else
      local quantity=math.min(incoming,available,allowance)
      if quantity<=0 then limited=true;break end
      self:_blocked(o,nil)
      self:_trade(b,o,resting,quantity);allowance-=quantity
      if allowance<=0 and o.Remaining>0 then limited=true end
      if resting.Remaining==0 then self:_retire(resting,"Filled")end
     end
    end
   end
  end
 end
 local available,unavailableReason=self:_available(o,false)
 if o.Remaining>0 and available<=0 then self:_blocked(o,unavailableReason)end
 self:_cleanBook(b)
 if o.Remaining==0 then if self.Orders[o.Id]then self:_retire(o,"Filled")end
 elseif not a.Player and reducing and o.Type=="Limit"and limited and self:_available(o,false)>0 then
  -- Keep a blocked bot TP's identity. The existing queue retries it without
  -- creating another order on every step, and it can never reduce a new position.
  o.Queued=true;o.Status="Waiting for matching"
 elseif protected and self:_available(o,false)>0 and (limited or o.Type=="Market"or self:_available(o,true)<=0)then
  o.Queued=true;o.Status="Waiting for matching";o.BlockedReason=o.BlockedReason or "Waiting for liquidity"
 elseif self:_available(o,true)>0 and managed and sliced and not o.Immediate
  and (o.Type=="Market"
   or o.Type=="Limit" and limited)then
  o.Queued=true;o.Status="Executing in slices"
 elseif o.Type=="Market"or self:_available(o,true)<=0 or limited and not(o.Type=="Limit"and o.Execution=="Immediate")then
  o.Cancelled+=o.Remaining;o.Remaining=0;self:_retire(o,o.Filled>0 and "Partial / IOC"or "No liquidity")
 elseif o.Type=="Limit"and opposing[1]and(opposing[1].Price-o.Price)*side<=0 then
  -- A guard-blocked crossing cannot leave a crossed resting book, for any owner.
  o.Cancelled+=o.Remaining;o.Remaining=0;self:_retire(o,"Price safeguard")
 else self:_rest(b,o)end
 a.Revision+=1
 self:_syncReductions()
 Protective.Sync(self)
 local average=o.Filled>0 and o.Notional/o.Filled or nil
 return true,{Id=o.Id,Filled=o.Filled,Remaining=o.Remaining,Cancelled=o.Cancelled,Average=average,Status=o.Status,Queued=o.Queued,
  Slippage=average and (average-o.Reference*b.Spec.Tick)*side or 0}
end
function Engine:ProcessPlayerOrders()PlayerExecution.Process(self)end
function Engine:ProcessStops()
 Protective.Sync(self)
 -- Bounded queue also handles cascades; deferred tails continue next scheduler step.
 local processed=0
 while #self.PendingStops>0 and processed<200 do
  local item=table.remove(self.PendingStops,1) local a=self.Accounts[item.Owner] local p=a and a.Positions[item.Contract]
  processed+=1
  if p and p.Id==item.Position and p.Triggered then
   if a.Player and p.Triggered=="Take profit"then
    -- Keep the residual TP and SL; cancel only competing entry/voluntary orders.
    for _,id in ipairs(sortedKeys(a.OpenOrders))do
     local o=self.Orders[id];if o and o.Contract==item.Contract and id~=p.TargetOrder then self:Cancel(a.Id,id)end
    end
    p.ExitOrder=p.TargetOrder
    local target=p.TargetOrder and self.Orders[p.TargetOrder]
    if target and target.Queued then self:_match(a,self.Books[item.Contract],target)end
    continue
   end
   local exit=p.ExitOrder and self.Orders[p.ExitOrder]
   if exit and exit.Protection and exit.Protection~=p.Triggered then self:Cancel(a.Id,exit.Id);exit=nil end
   if exit and exit.Protection and exit.Queued then self:_match(a,self.Books[item.Contract],exit)end
   if not exit then
    self:CancelAll(a.Id,item.Contract)
    if not BotExitRetry.Ready(self,a,item.Contract,p)then continue end
    local target=p.Triggered=="Take profit"and p.Target
    local ok,result=self:Submit(a.Id,{Contract=item.Contract,Direction=-p.Direction,
     Quantity=a.Player and self.Config.PlayerExecution and p.Quantity or math.min(p.Quantity,a.Player and self.Config.MaxPlayerQuantity or 10000),
     Type=target and "Limit"or "Market",Price=target,ReduceOnly=true},a.Player and p.Triggered~="Player close"and {Protection=p.Triggered,PositionId=p.Id}or nil)
    BotExitRetry.Attempted(self,a,item.Contract,p)
    if ok and result.Remaining>0 then p.ExitOrder=result.Id end
   end
  end
 end
 self:_triggerStops()
end
-- Triggered stop entries become ordinary market orders, in order-id sequence. While its market order is
-- checked the stop stops reserving capacity, so Submit applies every current rule once (contract cap, buying
-- power, depletion, order limits): a stop can never fill past the cap. A rejection ends the stop. If the
-- Explicit sliced stops retain their remainder in the execution queue. Standard stops cancel
-- unfilled quantity after their immediate attempt; the short retry path supports legacy orders.
Engine.StopRetrySeconds=5
function Engine:_triggerStops()
 local ready={}
 for _,ids in pairs(self:_stopIndex()) do for id in pairs(ids) do local o=self.Orders[id] if o and o.Triggered then table.insert(ready,id) end end end
 if #ready==0 then return end
 table.sort(ready)
 for _,id in ipairs(ready) do
  local o=self.Orders[id]
  if o then
   local a=self.Accounts[o.Owner] local b=self.Books[o.Contract]
   if self.Config.PlayerExecution and o.Execution=="Sliced"then
    local triggerPrice=o.Price*b.Spec.Tick
    self:_stopIndex()[o.Contract][o.Id]=nil
    o.Type="Market";o.Price=nil;o.Triggered=nil
    local _,result=self:_match(a,b,o)
    a.Triggers=a.Triggers or {}
    table.insert(a.Triggers,1,{Id=o.Id,Contract=o.Contract,Direction=o.Direction,Quantity=o.Original,Price=triggerPrice,
     Ok=result.Filled>0 or result.Queued==true,Filled=result.Filled,Average=result.Average,Queued=result.Queued,Remaining=result.Remaining,Time=self.Time})
    if #a.Triggers>8 then table.remove(a.Triggers)end
    continue
   end
   a.OpenOrders[o.Id]=nil
   local ok,result=self:Submit(o.Owner,{Contract=o.Contract,Direction=o.Direction,Quantity=o.Remaining,Type="Market",
    StopTicks=o.StopTicks,TargetTicks=o.TargetTicks,Link=o.Link},{Immediate=true})
   local filled=ok and result.Filled or 0
   if filled>0 then
    o.Remaining-=filled o.Cancelled+=filled -- converted into the child market order that holds the fill
    o.Converted=(o.Converted or 0)+filled o.ConvertedNotional=(o.ConvertedNotional or 0)+result.Average*filled
   end
   local waiting=ok and o.Execution~="Immediate"and o.Remaining>0 and self.Time-o.Triggered<Engine.StopRetrySeconds and not a.Locked
   if waiting then a.OpenOrders[o.Id]=true
   else
    local status=not ok and "Rejected" or o.Remaining>0 and (filled>0 or o.Converted) and "Partial / IOC" or o.Remaining>0 and "No liquidity" or "Triggered"
    local unfilled=o.Remaining o.Cancelled+=unfilled o.Remaining=0
    a.OpenOrders[o.Id]=true self:_retire(o,status)
    local done=o.Converted or 0
    a.Triggers=a.Triggers or {}
    table.insert(a.Triggers,1,{Id=o.Id,Contract=o.Contract,Direction=o.Direction,Quantity=o.Original,Price=o.Price*b.Spec.Tick,Ok=done>0,
     Filled=done,Average=done>0 and o.ConvertedNotional/done or nil,Message=not ok and result or unfilled>0 and ("No liquidity for "..unfilled) or nil,Time=self.Time})
    if #a.Triggers>8 then table.remove(a.Triggers) end
   end
   a.Revision+=1
  end
 end
end
function Engine:AdvanceClock(dt)
 self.Time+=dt self.Step+=1
 for _,id in ipairs(sortedKeys(self.Orders)) do
  local o=self.Orders[id] if o.Expires and o.Expires<=self.Time then self:Cancel(o.Owner,id) end
 end
 for _,id in ipairs(self.AccountOrder) do
  local a=self.Accounts[id]
  if a.House then continue end -- counterparty of player fills; it has no risk limits and never trades
  if a.Archive then continue end -- folded finished attempts: flat, retired ledger totals only
  local summary=self:Summary(a)
  if not next(a.Positions) then a.Liquidating=nil end
  if summary.Equity<=0 or (not a.Player and summary.Margin>math.max(0,summary.Equity)*1.05) then
   if summary.Equity<=0 then a.Locked=true if a.Player and not a.Depleted then a.Depleted=true a.DepletedAt=self.Time end end
   a.Liquidating=true self:CancelAll(id)
   for _,key in ipairs(self.Config.ContractOrder) do local p=a.Positions[key] if p then p.Triggered=a.Resetting and "Account reset"or a.Locked and "Account depleted" or "Margin liquidation" p.Stop=nil p.Target=nil end end
  end
  for _,key in ipairs(self.Config.ContractOrder) do
   local p=a.Positions[key] if p and p.Triggered then table.insert(self.PendingStops,{Owner=id,Contract=key,Position=p.Id}) end
  end
 end
 self:ProcessStops()
end
-- Atomic amendment: validate before touching the working order. Preserve its identity, quantity,
-- attached protection and copy links. A newly marketable price follows normal player-limit fills.
function Engine:AmendOrder(owner,request)
 local a=self.Accounts[owner]
 local o=type(request)=="table" and self.Orders[request.OrderId]
 if not a or not a.Player or not o or o.Protection or o.Owner~=owner or o.Contract~=request.Contract or o.Type~="Limit" or o.Remaining<=0 then
  return false,"Limit order is no longer working."
 end
 if a.Locked or a.Liquidating then return false,"Account failed. This limit order cannot be changed." end
 local b=self.Books[o.Contract] local tick=b.Spec.Tick
 if not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-o.Price*tick)>tick*.00001 or request.ExpectedQuantity~=o.Remaining then
  return false,"Limit order changed while dragging. Please try again."
 end
 local price=request.Price
 if not finite(price) or price<=0 or math.abs(price/tick-math.round(price/tick))>.00001 then return false,"Limit price must match the market's price increments (ticks)." end
 local ticks=math.round(price/tick) local last=b.Last or b.Reference
 local quantity=request.Quantity or o.Remaining
 if not integer(quantity)or quantity<1 then return false,"Amended remaining quantity must be a positive whole number."end
 if o.ReduceOnly then local p=a.Positions[o.Contract]
  if not p or p.Direction==o.Direction or quantity>p.Quantity then return false,"No matching position to reduce."end
 end
 if math.abs(ticks-last)>last*self.Config.PriceBandFraction then return false,"Limit is outside the price band." end
 if not o.ReduceOnly and self:OrderCapacity(a,o.Contract,o.Direction,o.StopTicks,o.Id)<quantity then return false,"Account contract limit changed. Cancel another order first." end
 if ticks==o.Price and quantity==o.Remaining then return true,"Limit price is unchanged."end
 if ticks==o.Price and quantity<o.Remaining then
  local removed=o.Remaining-quantity;o.Cancelled+=removed;o.Remaining=quantity;self:_cleanBook(b);a.Revision+=1
  b.ExitLiquidityRevision=(b.ExitLiquidityRevision or 0)+1
  return true,{Id=o.Id,Amended=true,Filled=0,Cancelled=removed,Remaining=quantity,Status=o.Status,Direction=o.Direction,Price=price}
 end
 if o.Execution=="Immediate"and not PlayerExecution.StandardLimitAllowed(self,a,b,o,ticks,quantity)then
  return false,"Move rejected by current execution safeguards. Your original limit order is unchanged. Try a non-marketable price or wait for capacity."
 end
 self:_unrest(b,o)
 if quantity>o.Remaining then o.Original+=quantity-o.Remaining else o.Cancelled+=o.Remaining-quantity end
 o.Remaining=quantity
 o.Price=ticks;o.Time=self.Time;o.Priority=self:_priority()
 local filled,notional,cancelled=o.Filled,o.Notional,o.Cancelled
 local ok,result=self:_match(a,b,o)
 -- Report only this amendment's executions, not fills from before the drag.
 -- Zero remaining can also mean cancellation; it does not prove a full fill.
 result.Filled=o.Filled-filled;result.Cancelled=o.Cancelled-cancelled
 result.Average=result.Filled>0 and (o.Notional-notional)/result.Filled or nil
 result.Amended=true;result.Direction=o.Direction;result.Price=price
 return ok,result
end
function Engine:AmendProtection(owner,request)
 local a=self.Accounts[owner]
 if not a or type(request)~="table" then return false,"Unknown account." end
 local field=request.Protection
 if field~="Stop" and field~="Target" then return false,"Invalid protection." end
 local b=self.Books[request.Contract] local p=a.Positions[request.Contract]
 if not b or not p or p.Id~=request.OrderId or p.Triggered or a.Locked then
  return false,"Protection already triggered, cancelled or position closed."
 end
 local creating=request.Create==true
 if request.ExpectedQuantity~=nil and request.ExpectedQuantity~=p.Quantity then return false,"Position size changed while dragging. Please try again."end
 if creating and (p[field]~=nil or request.ExpectedPrice~=nil or request.ExpectedQuantity~=p.Quantity)then return false,"Position or protection changed. Please try again."end
 if not creating and (not p[field] or not finite(request.ExpectedPrice) or math.abs(request.ExpectedPrice-p[field])>b.Spec.Tick*0.00001) then
  return false,"Protection changed while dragging. Please try again."
 end
 local price=request.Price local tick=b.Spec.Tick
 if not finite(price) or price<=0 or math.abs(price/tick-math.round(price/tick))>0.00001 then
  return false,"Protection price must match the market's price increments (ticks)."
 end
 price=math.round(price/tick)*tick
 local last=(b.Last or b.Reference)*tick
 -- SL/TP close an existing position. Ticket protections can already lie beyond
 -- the entry-order price band, so do not apply that band when creating or moving them.
 if creating then
  local fromEntry=(price-p.Entry)*p.Direction
  if field=="Stop" and fromEntry>=0 or field=="Target" and fromEntry<=0 then return false,"Choose the correct side of the entry price."end
 end
 local distance=(price-last)*p.Direction
 if (field=="Stop" and distance>=0) or (field=="Target" and distance<=0) then
  return false,field=="Stop" and "Place stop loss beyond the current price in the losing direction." or "Place take profit beyond the current price in the winning direction."
 end
 -- A valid stop may sit beyond the account's equity. Depletion is enforced from
 -- actual execution prices, independently of the configured protection level.
 p[field]=price p["Manual"..field]=true a.Revision+=1
 Protective.Mark(self,a,b.Key);Protective.Sync(self)
 return true,string.format("%s moved to %.2f.",field=="Stop" and "Stop loss" or "Take profit",price)
end
function Engine:CancelProtection(owner,id,field)
 if field~="Stop" and field~="Target" then return false,"Invalid protection." end
 for _,key in ipairs(self.Config.ContractOrder) do
  local p=self.Accounts[owner].Positions[key]
  if p and p.Id==id and not p.Triggered then
   p[field]=nil;p["Manual"..field]=nil;self.Accounts[owner].Revision+=1
   Protective.Mark(self,self.Accounts[owner],key);Protective.Sync(self)
   return true,"Protection cancelled."
  end
 end
 return false,"Protection already triggered or position closed."
end
function Engine:Snapshot(owner,key,timeframe,full)
 local a=self.Accounts[owner] local positions,orders={},{}
 local protectiveExits={}
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local p=a.Positions[symbol]
  if p then
   positions[symbol]=copy(p)
   positions[symbol].Unrealized=((self.Books[symbol].Last or self.Books[symbol].Reference)*self.Books[symbol].Spec.Tick-(p.PnlEntry or p.Entry))*p.Quantity*p.Direction*self.Books[symbol].Spec.Multiplier
   for _,field in ipairs({"Stop","Target"}) do if p[field] then
    local kind=field=="Stop"and "Stop loss"or "Take profit"
    local closing=p.Triggered==kind
    local exit=self.Orders[field=="Target"and p.TargetOrder or p.ExitOrder]
    if exit and exit.ReduceOnly and exit.Contract==symbol and (closing or field=="Target")then protectiveExits[exit.Id]=true end
    local status,filled=Protective.Status(self,a,p,field)
    table.insert(orders,{Id=p.Id,Contract=symbol,Quantity=p.Quantity,Filled=filled,
     Kind=kind..(closing and (p.Direction==-1 and " · closing short"or " · closing long")or ""),Price=p[field],Protection=field,
     Closing=closing,Status=status})
   end end
  end
 end
 for _,id in ipairs(sortedKeys(a.OpenOrders)) do
  local o=self.Orders[id] if o and not protectiveExits[id]then local blocked=self:OrderBlockReason(o);table.insert(orders,{Id=id,Contract=o.Contract,Quantity=o.Remaining,Original=o.Original,Filled=o.Filled,
   Kind=(o.Protection=="Account reset"and "Reset liquidation · "or "")..(o.Type=="Stop" and "Stop " or o.Type=="Market" and "Market " or "Limit ")..(o.Direction==1 and "Buy" or "Sell"),Type=o.Type,Direction=o.Direction,Queued=o.Queued,Execution=o.Execution,
   Price=o.Price and o.Price*self.Books[o.Contract].Spec.Tick or nil,BlockedReason=blocked,Status=o.Protection=="Account reset"and (o.Filled.." filled · "..o.Remaining.." remaining · "..(blocked or "Liquidating"))or blocked or o.Queued and "Executing in slices"or o.Type=="Stop" and (o.Triggered and "Triggered" or "Armed") or o.Filled>0 and "Partial" or "Working"}) end
 end
 local quotes={};local dayStart=math.floor(self.Time/86400)*86400
 for _,symbol in ipairs(self.Config.ContractOrder) do
  local b=self.Books[symbol] local tick=b.Spec.Tick
  if b.Spec.CloseOnly and not a.Positions[symbol] then continue end
  -- Read-only executable depth. Invalid/blocked quotes remain diagnosable in the
  -- owner's order status but are never advertised as available liquidity.
  local depth={Bids={},Asks={}};local summaries={}
  for _,side in ipairs({"Bids","Asks"})do
   local direction=side=="Asks"and 1 or -1
   for _,level in ipairs(b[side])do
    if not PlayerExecution.Allows(self,b,level.Price,direction)then break end
    local quantity=0;for _,o in ipairs(level.Orders)do quantity+=self:_available(o,true,summaries)end
    if quantity>0 then table.insert(depth[side],{Price=level.Price*tick,Quantity=quantity})end
    if #depth[side]>=(self.Config.DepthLevels or 5)then break end
   end
  end
  local bid=depth.Bids[1]and depth.Bids[1].Price local ask=depth.Asks[1]and depth.Asks[1].Price
  -- Use the executed daily candle, independent of the subscribed chart timeframe.
  -- Before today's first trade, the unchanged last price represents a flat day.
  local daily=b.Candles["1D"];local today=daily and daily[#daily]
  local dayOpen=today and today.Time==dayStart and today.Open or (b.Last and b.Last*tick)
  quotes[symbol]={Last=b.Last and b.Last*tick,Open=b.Open and b.Open*tick,Bid=bid,Ask=ask,Spread=bid and ask and ask-bid,
   DayOpen=dayOpen,DayStart=dayStart,
   Volume=b.Volume,TradeCount=b.Up+b.Down,Recent={},Depth=depth}
  for i=math.max(1,#b.Recent-15),#b.Recent do table.insert(quotes[symbol].Recent,b.Recent[i]*tick) end
 end
 local series=self.Books[key].Candles[timeframe] local candles={}
 for i=full and 1 or math.max(1,#series-1),#series do table.insert(candles,copy(series[i])) end
 -- Current maximum new order per instrument and side (the same rule Submit enforces), for the ticket and chart menu.
 local capacity
 if a.Player then
  capacity={}
  for _,symbol in ipairs(self.Config.ContractOrder) do
   if not self.Books[symbol].Spec.CloseOnly then
    local buy=a.Locked and 0 or (self:OrderCapacity(a,symbol,1)) local sell=a.Locked and 0 or (self:OrderCapacity(a,symbol,-1))
    capacity[symbol]={Buy=buy,Sell=sell}
   end
  end
 end
 return {Seed=self.Seed,Time=self.Time,Step=self.Step,Quotes=quotes,Positions=positions,Orders=orders,History=a.History,Fills=a.Fills,
  Base=a.Base,Summary=self:Summary(a),Contract=key,Timeframe=timeframe,Candles=candles,Full=full,Revision=a.Revision,Locked=a.Locked,
  Capacity=capacity,Limit=a.Player and self:ContractLimit(a) or nil,Triggers=a.Triggers}
end
function Engine:Audit()
 local cash,equity,inventory,volume=0,0,{},0
 for _,key in ipairs(self.Config.ContractOrder) do inventory[key]=0 end
 local accounts={}for _,id in ipairs(self.AccountOrder)do table.insert(accounts,self.Accounts[id])end
 local archive=self.MarketRetirement
 if archive then
  assert(archive.Version==self.Config.MarketRetirementVersion,'Retirement archive policy mismatch')
  for _,a in ipairs(archive.Accounts)do
   assert(not self.Accounts[a.Id]and a.Retired and not a.Player and not a.House and not a.Archive,'Invalid retired bot archive')
   assert(not next(a.Positions)and not next(a.OpenOrders),'Archived bot has exposure')
   table.insert(accounts,a)
  end
  for key,row in pairs(archive.Markets)do local b=row.Book
   assert(not self.Books[key]and b.Spec.CloseOnly and not b.Bids[1]and not b.Asks[1],'Archived market is active')
   volume+=b.Volume
   for _,tf in ipairs(self.Config.Timeframes)do assert((b.CandleVolume[tf[1]]or 0)==b.Volume,'Archived candle volume mismatch')end
  end
 end
 for _,a in ipairs(accounts)do
  cash+=a.CashFlow equity+=self:Summary(a).Equity-a.Base
  assert(math.abs(a.Balance-a.Base-(a.PnlBaseline or 0)-a.Realized)<0.001,"Balance / realized reconciliation")
  if a.PnlBaseline then
   assert(not a.Player and not a.House and not a.Archive,"Invalid bot accounting baseline")
   assert(math.abs(a.Base-a.StartingCapital-a.NetCapitalAdjustments)<0.001,"Bot capital reconciliation")
   local marked=a.CashFlow
   for key,p in pairs(a.Positions)do local b=self.Books[key]
    marked+=(b.Last or b.Reference)*b.Spec.Tick*p.Quantity*p.Direction*b.Spec.Multiplier
   end
   assert(math.abs(self:Summary(a).Equity-a.Base-marked)<0.01,"Bot cash / marked equity reconciliation")
  end
  local st=a.Stats
  if a.Player and type(st)=="table" then
   assert(math.abs(a.Realized-(st.Gains-st.Loss+st.UntrackedNet))<0.01,"Lifetime stats / realized reconciliation")
   assert(st.Trades==st.Wins+st.Losses+st.Even,"Lifetime stats trade classification")
  end
  for key,p in pairs(a.Positions) do inventory[key]+=p.Quantity*p.Direction end
 end
 assert(math.abs(cash)<0.01,"Notional cash is not conserved") assert(math.abs(equity)<0.01,"Total marked P&L is not zero")
 for _,key in ipairs(self.Config.ContractOrder) do
  assert(inventory[key]==0,"Inventory is not conserved") local b=self.Books[key] volume+=b.Volume
  for _,tf in ipairs(self.Config.Timeframes) do assert((b.CandleVolume[tf[1]] or 0)==b.Volume,"Candle volume mismatch") end
  for _,side in ipairs({b.Bids,b.Asks}) do
   for _,l in ipairs(side) do local total=0 local arrival=0 for _,o in ipairs(l.Orders) do
    assert(o.Remaining>0 and self.Orders[o.Id]==o,"Stale resting order") assert((o.Priority or o.Id)>arrival,"FIFO violated") arrival=o.Priority or o.Id total+=o.Remaining
   end assert(total==l.Quantity,"Level quantity mismatch") end
  end
  assert(not b.Bids[1] or not b.Asks[1] or b.Bids[1].Price<b.Asks[1].Price,"Crossed resting book")
 end
 for _,list in ipairs({self.Orders,self.OrderArchive}) do for _,o in pairs(list) do assert(o.Original==o.Filled+o.Remaining+o.Cancelled,"Order quantity mismatch") end end
 assert(volume==self.TotalVolume,"Total volume mismatch")
 return {CashError=cash,EquityError=equity,Inventory=inventory,Volume=volume,Trades=self.NextTrade,Hash=self.TradeHash}
end
return Engine
