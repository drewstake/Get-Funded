-- No DataStore writes, no Play/Stop action, no save or publication. Run only after stopping safely.
assert(not game:GetService("RunService"):IsRunning(),"Installation requires Edit mode; active positions/orders must be reviewed before stopping.")
local Encoding=game:GetService("EncodingService")
local function hash(source)local bytes=Encoding:ComputeStringHash(source:gsub("\r\n","\n"),Enum.HashAlgorithm.Sha256);return(bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end
local release={}
release[ ([====[!ServerScriptService.MarketReign.MarketEngine]====]):sub(2) ]={Source=([====[!-- Deterministic, server-only price/time priority exchange. Prices are integer ticks internally.
local Engine = {}
Engine.__index = Engine
local TradeStats=require(script.Parent.TradeStats)
local Protection=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local ContractLimits=require(game.ReplicatedStorage.MarketReign.ContractLimits)
local PlayerExecution=require(script.Parent.PlayerExecution)
local Protective=require(script.Parent.ProtectiveOrders)
local BotExitRetry=require(script.Parent.BotExitRetry)
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
   unrealized+=((b.Last or b.Reference)*b.Spec.Tick-p.Entry)*p.Quantity*p.Direction*b.Spec.Multiplier
   count+=1 margin+=p.Quantity*b.Spec.Margin
  end
 end
 -- Funded accounts liquidate on equity depletion; margin limits apply to new exposure.
 return {Balance=a.Balance,Equity=a.Balance+unrealized,Unrealized=unrealized,Session=a.Balance+unrealized-a.Base,
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
  realized=(price-p.Entry)*closed*p.Direction*b.Spec.Multiplier
  a.Realized+=realized;a.Balance=a.Base+a.Realized
  self:ContractLimit(a)
  -- Persist eligibility independently of the bounded display history, including break-even closes.
  a.CompletedTrades=(a.CompletedTrades or #a.History)+1
  table.insert(a.History,1,{PositionId=p.Id,Contract=o.Contract,Direction=p.Direction,Quantity=closed,Entry=p.Entry,Exit=price,Pnl=realized,
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
  if oldNet*delta>0 then p.Entry=(p.Entry*math.abs(oldNet)+price*qty)/math.abs(net) end
  p.Quantity=math.abs(net)
 end
 p=a.Positions[o.Contract]
 if p and not o.ReduceOnly and p.Direction==side then
  -- Existing player protections keep their exact prices through every scale-in fill.
  -- Only absent levels initialize from the ticket; both cover the updated full quantity.
  if o.StopTicks and not p.ManualStop and (not a.Player or p.Stop==nil)then p.Stop=math.round((p.Entry-side*o.StopTicks*b.Spec.Tick)/b.Spec.Tick)*b.Spec.Tick end
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
 if a.Player and b.Spec.CloseOnly and not reducing then return false,b.Key.." is a retired market and is close-only. Choose an available market for new trades." end
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
   positions[symbol].Unrealized=((self.Books[symbol].Last or self.Books[symbol].Reference)*self.Books[symbol].Spec.Tick-p.Entry)*p.Quantity*p.Direction*self.Books[symbol].Spec.Multiplier
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
 for _,id in ipairs(self.AccountOrder) do
  local a=self.Accounts[id] cash+=a.CashFlow equity+=self:Summary(a).Equity-a.Base
  assert(math.abs(a.Balance-a.Base-a.Realized)<0.001,"Balance / realized reconciliation")
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
]====]):sub(2),Hash=([====[!89be02e0df95783388b0510ba8e4efa3e71c89e6a049ce8ae07dbcac9c2f9f4d]====]):sub(2),ExpectedHash=([====[!129024f104e3cc18c9ef4de30ff437ea2f7864211711838ea4c28f2ea8e0e0a3]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.MarketServer]====]):sub(2) ]={Source=([====[!local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local root=ReplicatedStorage:WaitForChild("MarketReign")
local Config=require(root.MarketConfig)
local Progression=require(root.ProgressionConfig)
local World=require(script.Parent.WorldService)
local Funded=require(script.Parent.FundedAccounts)
local Leaderboards=require(script.Parent.LeaderboardService)
local Ranking=require(script.Parent.LeaderboardRanking)
local ReplyBuffer=require(script.Parent.ReplyBuffer)
local WorldSettings=require(script.Parent.WorldConfig)
local SimulationScheduler=require(script.Parent.SimulationScheduler)
local RequestJournal=require(script.Parent.RequestJournal)
local RequestQueue=require(script.Parent.RequestQueue)
local OwnerResetCommand=require(script.Parent.OwnerResetCommand)
local OwnerGiveCommand=require(script.Parent.OwnerGiveCommand)
local DepthAccess=require(script.Parent.MarketDepthAccess)
local depthAccess=DepthAccess.new()
Funded.Validate(Progression) -- Fail closed on invalid progression configuration.
local function remote(name)
 local old=root:FindFirstChild(name) if old then old:Destroy() end
 local r=Instance.new("RemoteEvent") r.Name=name r.Parent=root return r
end
local requestRemote=remote("OrderRequest") local updateRemote=remote("MarketUpdate")
local ownerNotice=remote("OwnerNotice")
local world=World.new(Config)
local leaderboard=Leaderboards.new({Studio=world.Studio})
world.CaptureProjection=function(engine)return Ranking.Capture(Funded.new(engine,Progression,Config))end
local oldLeaderboard=root:FindFirstChild("LeaderboardRequest") if oldLeaderboard then oldLeaderboard:Destroy() end
local leaderboardRemote=Instance.new("RemoteFunction") leaderboardRemote.Name="LeaderboardRequest" leaderboardRemote.Parent=root
local market,population,funded local epoch=-1
root:SetAttribute("SessionSeed",nil) root:SetAttribute("Ready",false)
local clients={} local queue={} local sequence=0 local actionLog={}
local resettingUid
-- Acknowledgements are bounded per connection by count and age (see ReplyBuffer).
local replies=ReplyBuffer.new(WorldSettings.MaxQueuedReplies,WorldSettings.ReplyMaxAgeSeconds)
-- Joining idempotently creates one $10,000 account for a new player.
local function resolve(player,state)
 if not funded or not world:CanRun() or state.ResetPending then return end
 funded:Join(state.Uid) funded:Return(state.Uid) funded:Evaluate(state.Uid)
 local p=funded:Profile(state.Uid)
 if p then
  p.PlayerName=player.Name;p.DisplayName=player.DisplayName
  -- A join restores history without replaying sounds for old/offline executions.
  local events={};for _,event in ipairs(p.Events or {})do if event.Kind~="TradeClosed"then table.insert(events,event)end end;p.Events=events
 end
 state.Owner=funded:Owner(state.Uid) state.Full=true state.PortfolioRevision=nil
 if state.RequestEngine~=market then
  state.RequestEngine=market;state.RequestSession=RequestJournal.Open(market,state.Uid)
 end
 if state.Owner then market:SetConnected(state.Owner,true)end
end
local function add(player)
 if clients[player] then return end
 clients[player]={Uid=Funded.Key(player.UserId),Contract=Config.ContractOrder[1],Timeframe="1m",Full=true,Tokens=20,TokenTime=os.clock(),
  Seen={},SeenOrder={},Replies={},ReplyTimes={},Subscribed=false,PortfolioAt=0,ResetPending=tostring(player.UserId)==resettingUid}
 depthAccess:Refresh(player)
 resolve(player,clients[player])
end
Players.PlayerAdded:Connect(add) for _,p in ipairs(Players:GetPlayers()) do add(p) end
-- The purchase event only triggers a fresh ownership query. Its boolean never grants access.
game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player,passId)
 if clients[player]and passId==depthAccess.PassId then depthAccess:Refresh(player,true)end
end)
leaderboardRemote.OnServerInvoke=function(player,tab)
 local state=clients[player]
 if not state or (tab~="Global" and tab~="Server") then return nil end
 -- Read-only endpoint; rate limits are independent of order traffic. No scores/ids accepted.
 local now=os.clock()
 if now<(state.LeaderboardAt or 0) then return {Tab=tab,State="Throttled"} end
 state.LeaderboardAt=now+2
 if not funded or not world:CanRun() then return {Tab=tab,State="Loading",Rows={},Studio=world.Studio} end
 if tab=="Server" then return leaderboard:Server(funded,Players:GetPlayers(),player) end
 local own=Ranking.Row(funded,state.Uid,player)
 return leaderboard:Global(own)
end
-- Portfolio + projection accompany each price batch. Closed and open amounts are one snapshot.
local function attachPortfolio(state,packet)
 if not funded then return end
 packet.Events=funded:TakeEvents(state.Uid)
 local profile=funded:Profile(state.Uid)
 local revision=profile and profile.Revision or 0 local now=os.clock()
 packet.Portfolio=funded:View(state.Uid) state.PortfolioRevision=revision state.PortfolioAt=now
 -- Lifetime stats: sent on join/refresh and whenever a counted value changes (a close, a depletion,
 -- a restart). A failure here is isolated from trading and reported to the Stats page.
 local key=funded:StatsKey(state.Uid)
 if state.Full or key~=state.StatsKey then
  local ok,stats=pcall(funded.Stats,funded,state.Uid)
  if not ok then warn("[Get Funded!] Stats unavailable: "..tostring(stats)) end
  packet.Stats=ok and stats or {Error="Stats are temporarily unavailable. Your trades and saved results are not affected."}
  state.StatsKey=key
 end
end
local function emit(player,state)
 depthAccess:Refresh(player)
 if funded and world:CanRun() and not funded:Owner(state.Uid) and os.clock()>=(state.JoinRetryAt or 0) then
  state.JoinRetryAt=os.clock()+5;resolve(player,state)
 end
 if funded then
  local owner=funded:Owner(state.Uid)
  if state.Owner~=owner then state.Owner=owner;state.Full=true;if owner then market:SetConnected(owner,true)end end
 end
 local unavailable=not market or world.Transaction or state.ResetPending or world.Mode=="Unavailable" or world.Mode=="Following" or world.Mode=="Loading"
 if unavailable or not state.Owner or not market.Accounts[state.Owner] then
  -- No trading account yet (first join) or the exchange is not ready: send status and portfolio only.
  local queued,dropped=replies:Take(state)
  local packet={StatusOnly=true,CanTrade=not unavailable and world:CanRun(),ConnectionStatus=world:Label(),Replies=queued,RepliesDropped=dropped,NoAccount=not unavailable or nil,RequestSession=state.RequestSession,RequestHigh=state.LastRequestId}
  if not unavailable then attachPortfolio(state,packet) state.Full=false end
  depthAccess:Apply(packet,player,state.Contract)
  updateRemote:FireClient(player,packet)
  return
 end
 local packet=market:Snapshot(state.Owner,state.Contract,state.Timeframe,state.Full)
 packet.Seed=nil -- The server's future random stream is private.
 packet.CanTrade=world:CanRun() packet.ConnectionStatus=world:Label() packet.PersistenceMode=world.Mode
 if market.Accounts[state.Owner].Resetting then
  packet.CanTrade=false;packet.ConnectionStatus="Resetting account · liquidating positions…"
 end
 -- Quotes/candles/P&L are frequent; unchanged order and trade histories are not resent.
 local orderParts={}
 for _,order in ipairs(packet.Orders)do
  table.insert(orderParts,table.concat({order.Id,order.Contract,order.Protection or "",order.Quantity,order.Price or "Market",order.Status},":"))
 end
 local orderSignature=table.concat(orderParts,"|")
 if not state.Full and state.SentRevision==packet.Revision and state.SentOwner==state.Owner then
  packet.History=nil packet.Fills=nil
 end
 -- OCO/trigger status can change before a closing execution changes the account revision.
 if not state.Full and state.SentOwner==state.Owner and state.SentOrders==orderSignature then
  packet.Orders=nil
 end
 depthAccess:Apply(packet,player,state.Contract)
 state.SentRevision=packet.Revision state.SentOwner=state.Owner state.SentOrders=orderSignature
 packet.Regime=population.Regime.Name packet.News=market.Time<population.NewsUntil and population.News or nil
 packet.Speed=Config.SimulationSpeed packet.Replies,packet.RepliesDropped=replies:Take(state)
 packet.AccountKey=(funded:Profile(state.Uid) or {}).Active
 packet.AccountToken=state.Owner -- identifies the exact attempt; checked, never used to choose an owner
 packet.RequestSession=state.RequestSession
 packet.RequestHigh=state.LastRequestId
 attachPortfolio(state,packet)
 updateRemote:FireClient(player,packet) state.Full=false
end
-- A packet failure for one connection must not stop every other player's feed.
local function safeEmit(player,state)
 local ok,err=pcall(emit,player,state)
 if not ok then
  state.Full=true
  local now=os.clock()
  if now>=(state.EmitWarningAt or 0)then
   state.EmitWarningAt=now+5;warn("[Get Funded!] Market update failed; retrying: "..tostring(err))
  end
 end
end
local function reply(state,id,ok,message,result,extra)
 local r={RequestId=id,Ok=ok,Message=message,Result=result}
 for k,v in pairs(extra or {})do r[k]=v end
 local active=state.ActiveJournal
 if active and active.Id==id then RequestJournal.Finish(market,state.Uid,active.Session,id,r)end
 replies:Push(state,r,os.clock())
end
local allowed={Place=true,Cancel=true,Close=true,Subscribe=true,AmendProtection=true,AmendOrder=true,
 Start=true,Restart=true,ResetAccount=true,AcknowledgeAway=true,Flag=true,Stats=true,ProtectionPreferences=true}
local fields={"RequestSession","ExpectedAccount","Contract","Timeframe","Direction","Quantity","Type","Price","StopTicks","TargetTicks","StopDollars","TargetDollars","ExpectedQuantity","OrderId","Protection","ExpectedPrice",
 "Stage","StopOn","TargetOn","Create","SummaryId","Execution"}
requestRemote.OnServerEvent:Connect(function(player,request)
 local state=clients[player]
 if not state or state.ResetPending or type(request)~="table" then return end
 local now=os.clock()
 -- Subscription recovery has its own allowance, so order spam cannot starve the feed.
 if request.Action=="Subscribe"or request.Action=="Stats"then
  state.ReadTokens=math.min(4,(state.ReadTokens or 4)+(now-(state.ReadTokenTime or now))*2);state.ReadTokenTime=now
  if state.ReadTokens<1 then return end;state.ReadTokens-=1
 else
  state.Tokens=math.min(20,state.Tokens+(now-state.TokenTime)*6);state.TokenTime=now
  if state.Tokens<1 then return end;state.Tokens-=1
 end
 if type(request.Id)~="number" or request.Id%1~=0 or request.Id<1 or request.Id>1e9 then return end
 if state.Seen[request.Id]then
  local cached=RequestJournal.Cached(market,state.Uid,request.RequestSession,request.Id)
  if cached then replies:Push(state,cached,now)else state.Full=true end
  return
 end
 if not allowed[request.Action] then return end
 -- Whitelist scalar inputs. ExpectedAccount detects a stale view; it never selects an owner.
 -- Execution prices, timestamps and account ownership remain server-owned.
 local clean={Id=request.Id,Action=request.Action}
 for _,field in ipairs(fields) do
  local value=request[field]
  if value~=nil then
   if field=="StopOn"or field=="TargetOn"or field=="Create"then
    if type(value)~="boolean"then return end
   elseif type(value)~="number" and type(value)~="string" then return end
   if type(value)=="number" and (value~=value or math.abs(value)>1e9) then return end
   if type(value)=="string" and #value>(field=="Followers" and 512 or field=="ExpectedAccount" and 64 or 32) then return end
   clean[field]=value
  end
 end
 if #queue>=RequestQueue.Capacity then reply(state,clean.Id,false,"Exchange busy. Please retry.") return end
 state.Seen[clean.Id]=true table.insert(state.SeenOrder,clean.Id)
 state.LastRequestId=math.max(state.LastRequestId or 0,clean.Id)
 if #state.SeenOrder>256 then state.Seen[table.remove(state.SeenOrder,1)]=nil end
 -- Read-only: resend the authoritative Stats packet with the next update (Stats page Retry).
 if clean.Action=="Stats"then state.StatsKey=nil return end
 if clean.Action=="Subscribe"then
  local valid=false for _,tf in ipairs(Config.Timeframes)do if tf[1]==clean.Timeframe then valid=true break end end
  if Config.Contracts[clean.Contract]and valid then
   state.Contract=clean.Contract state.Timeframe=clean.Timeframe state.Full=true state.Subscribed=true
   -- Coalesce rapid subscription changes into the next scheduled market packet.
  end
  return
 end
 if not world:CanRun()then reply(state,clean.Id,false,world:Label())return end
 sequence+=1 table.insert(queue,{Player=player,Request=clean,Sequence=sequence,Epoch=epoch,Owner=state.Owner})
end)
local function processCore(item)
 local state=clients[item.Player] if not state or state.ResetPending then return end
 if not world:CanRun() then reply(state,item.Request.Id,false,world:Label(),nil,{Kind=item.Request.Action}) return end
 if item.Epoch~=epoch then reply(state,item.Request.Id,false,"Exchange reconnected. Please submit your order again.")return end
 local req=item.Request local uid=state.Uid
 funded:Evaluate(uid)
 local owner=funded:Owner(uid)
 if state.Owner~=owner then
  state.Owner=owner;state.Full=true
  if owner then market:SetConnected(owner,true)end
  if req.Action=="Place" or req.Action=="Close" or req.Action=="Cancel" or req.Action=="AmendOrder" or req.Action=="AmendProtection" then
   reply(state,req.Id,false,"Your account has restarted. Check the current account and try again.") return
  end
 end
 -- Account lifecycle. Each is idempotent and validated against the saved profile.
 if req.Action=="Start" then
  local ok,message,created=funded:Start(uid)
  local profile=funded:Profile(uid);if profile then profile.PlayerName=item.Player.Name;profile.DisplayName=item.Player.DisplayName end
  state.Owner=funded:Owner(uid) state.Full=true;if state.Owner then market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Start",Created=created}) return
 elseif req.Action=="Restart" then
  local ok,message=funded:Restart(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid) state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Restart",Tier=req.Tier}) return
 elseif req.Action=="ResetAccount"then
  local ok,message=funded:ResetAccount(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid);state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="ResetAccount"});return
 elseif req.Action=="AcknowledgeAway"then
  local ok,message=funded:AcknowledgeAway(uid,req.SummaryId)
  reply(state,req.Id,ok,message,nil,{Kind="AcknowledgeAway"});return
 elseif req.Action=="Flag" then
  local ok,message=funded:Flag(uid,req.Stage)
  reply(state,req.Id,ok,message,nil,{Kind="Flag",Stage=req.Stage}) return
 elseif req.Action=="ProtectionPreferences"then
  local ok,message=funded:SetProtectionPreferences(uid,req)
  reply(state,req.Id,ok,message,nil,{Kind="ProtectionPreferences"}) return
 end
 -- Trading owner and current run token are resolved only on the server.
 local owner=state.Owner
 if item.Owner~=owner or req.ExpectedAccount~=owner then reply(state,req.Id,false,"Your account has changed. Check it and try again.") return end
 if not owner or not market.Accounts[owner] then reply(state,req.Id,false,"Your trading account is loading.") return end
 local ok,result=Funded.Perform(market,owner,req)
 market:ProcessStops()
 funded:Evaluate(uid)
 local message=type(result)=="table" and Funded.Describe(result) or result or "Request rejected."
 reply(state,req.Id,ok,message,type(result)=="table" and result or nil,{Kind=req.Action})
end
local function process(item)
 local state=clients[item.Player];if not state or state.ResetPending then return end
 local req=item.Request
 if not market then reply(state,req.Id,false,"Exchange is not ready.");return end
 local accepted,cached,message=RequestJournal.Begin(market,state.Uid,req.RequestSession,req.Id)
 if not accepted then
  if cached then replies:Push(state,cached,os.clock())else reply(state,req.Id,false,message)end
  state.Full=true;return
 end
 state.ActiveJournal={Id=req.Id,Session=req.RequestSession}
 market.RequestContext={Sequence=item.Sequence,Id=req.Id,Step=market.Step}
 local ok,err=pcall(processCore,item)
 market.RequestContext=nil
 if not ok then
  reply(state,req.Id,false,"Request interrupted. Check the account snapshot before placing another order.")
  state.Full=true;warn("[Get Funded!] Request processing failed: "..tostring(err))
 end
 state.ActiveJournal=nil
end
Players.PlayerRemoving:Connect(function(player)
 depthAccess:Forget(player)
 -- Leaving cancels working orders. Positions and their protective triggers remain on the exchange.
 local departing=clients[player]
 if market and departing and departing.Owner then funded:Depart(departing.Uid);market:SetConnected(departing.Owner,false)end
 -- Accept already-received preference edits even if the player leaves before the next market step.
 local remaining={}
 for _,item in ipairs(queue)do
  if item.Player==player and item.Request.Action=="ProtectionPreferences"then process(item)
  elseif item.Player==player and market and departing then
   local req=item.Request
   if RequestJournal.Begin(market,departing.Uid,req.RequestSession,req.Id)then
    RequestJournal.Finish(market,departing.Uid,req.RequestSession,req.Id,{RequestId=req.Id,Ok=false,Message="Disconnected before execution; request cancelled."})
   end
  elseif item.Player~=player then table.insert(remaining,item)end
 end
 queue=remaining;clients[player]=nil
end)
local routing={}
TeleportService.TeleportInitFailed:Connect(function(player)
 routing[player]=nil
 local state=clients[player]if state then state.NextRoute=os.clock()+10 end
end)
local function route(player,state)
 local owner=world.Owner
 if world.Studio or routing[player]or os.clock()<(state.NextRoute or 0)or not owner or
  owner.LeaseUntil<=os.time()or owner.JobId==""or owner.JobId==game.JobId then return end
 routing[player]=true state.NextRoute=os.clock()+15
 task.spawn(function()
  local ok,err=pcall(function()
   local options=Instance.new("TeleportOptions")options.ServerInstanceId=owner.JobId
   TeleportService:TeleportAsync(owner.PlaceId,{player},options)
  end)
  if not ok then routing[player]=nil warn("[Get Funded!] Exchange transfer will retry: "..tostring(err))end
 end)
end
Players.PlayerRemoving:Connect(function(player)routing[player]=nil end)
-- TextChatCommand intercepts the command; authorization and username resolution stay on the server.
-- The owner wipe remains separate from the player reset, which preserves lifetime progress.
local ownerCommand=OwnerResetCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared" and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=function(name)
  for _,player in ipairs(Players:GetPlayers())do
   if player.Name:lower()==name:lower()then return player.UserId,player.Name end
  end
  local uid=Players:GetUserIdFromNameAsync(name)
  return uid,Players:GetNameFromUserIdAsync(uid)
 end,
 Reset=function(userId,name)
  local uid=Funded.Key(userId)
  if not world.Engine or not world.Engine.Profiles[uid]then return false,"@"..name.." has no saved data to reset."end
  resettingUid=uid
  for _,state in pairs(clients)do if state.Uid==uid then state.ResetPending=true end end
  local ok=world:TransformSaved(function(engine)
   return Funded.new(engine,Progression,Config):ResetPlayer(uid)
  end)
  if not ok then
   resettingUid=nil
   for player,state in pairs(clients)do if state.Uid==uid then
    if not world.Engine then
     player:Kick("The exchange is checking saved data after an owner reset. Please rejoin shortly.")
    else state.ResetPending=nil;state.Full=true end
   end end
   return false,"Reset was not confirmed. Wait for the saved exchange to recover, then check @"..name.." before retrying."
  end
  -- Clear delayed actions and diagnostic copies belonging to the wiped profile.
  for i=#queue,1,-1 do if queue[i].Player.UserId==userId then table.remove(queue,i)end end
  for i=#actionLog,1,-1 do if actionLog[i].Player==userId then table.remove(actionLog,i)end end
  leaderboard:UseDurableProjection(world.DurableProjection)
  root:SetAttribute("LeaderboardRevision",(root:GetAttribute("LeaderboardRevision")or 0)+1)
  task.spawn(function()leaderboard.NextWrite=0;leaderboard:Flush()end)
  return true,"Reset saved for @"..name..". All trading history, ranks, titles and settings cleared. New $10,000 account ready."
 end,
 AfterReset=function(userId)
  -- Rejoining discards local drafts, tutorial state, preference retries and old request tokens.
  for _,player in ipairs(Players:GetPlayers())do
   if player.UserId==userId then player:Kick("The owner reset your Get Funded! data, including ranks, titles and trading history. Rejoin to start with $10,000 in-game money.")end
  end
  resettingUid=nil
 end,
})
local chat=game:GetService("TextChatService")
local oldCommand=chat:FindFirstChild("OwnerResetCommand");if oldCommand then oldCommand:Destroy()end
local resetCommand=Instance.new("TextChatCommand")
resetCommand.Name="OwnerResetCommand";resetCommand.PrimaryAlias="/reset";resetCommand.AutocompleteVisible=false
resetCommand.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then ownerCommand:Handle(player,text)end
end)
resetCommand.Parent=chat
local giveCommand=OwnerGiveCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared"and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=ownerCommand.Options.Resolve,
 Give=function(userId,name,amount,actor)
  local uid=Funded.Key(userId);local receipt=game:GetService("HttpService"):GenerateGUID(false)
  local ok,balance=world:TransformSaved(function(engine)
   local accounts=Funded.new(engine,Progression,Config,{Capacity=function(kind)return world:HasCapacity(kind)end})
   local result=accounts:GrantMoney(uid,amount,actor,receipt)
   local profile=accounts:Profile(uid);profile.PlayerName=name
   return result
  end)
  if not ok then
   if world:CanRun()then return false,"Grant not applied: "..tostring(balance)end
   return false,"Grant could not be confirmed. Wait for the saved exchange to recover and check @"..name.."'s balance before retrying."
  end
  local function money(n)return "$"..string.format("%.0f",n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")end
  return true,"Saved: gave "..money(amount).." to @"..name..". Balance: "..money(balance).."."
 end,
})
local oldGive=chat:FindFirstChild("OwnerGiveCommand");if oldGive then oldGive:Destroy()end
local giveChat=Instance.new("TextChatCommand");giveChat.Name="OwnerGiveCommand";giveChat.PrimaryAlias="/give";giveChat.AutocompleteVisible=false
giveChat.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then giveCommand:Handle(player,text)end
end)
giveChat.Parent=chat
task.spawn(function()world:Open()end)
game:BindToClose(function()
 if funded then for _,state in pairs(clients)do funded:Depart(state.Uid)end end
 world:Close()
 leaderboard:Queue(world.DurableProjection)
 -- Exchange durability comes first. A missed publish is rebuilt from its save on the next owner.
 leaderboard.NextWrite=0;leaderboard:Flush()
end)
task.spawn(function()
 while not world.Closing do
  task.wait(5)
  leaderboard:Queue(world.DurableProjection)
  leaderboard:Flush()
 end
end)
local elapsed,broadcast,maintenance=0,0,0
local performance={Frames=0,Steps=0,TotalMs=0,MaxMs=0,Backlog=0,BudgetHits=0}
RunService.Heartbeat:Connect(function(dt)
 local started=os.clock()
 debug.profilebegin("FundedMarketHeartbeat")
 if epoch~=world.Epoch then
  epoch=world.Epoch market=world.Engine population=world.Population elapsed=0
  funded=market and Funded.new(market,Progression,Config,{Capacity=function(kind) return world:HasCapacity(kind) end}) or nil
  if market and funded then
   local connected={}
   for _,state in pairs(clients)do local owner=funded:Owner(state.Uid);if owner then connected[owner]=true end end
   market:SetConnectedOwners(connected)
  end
  for player,state in pairs(clients)do state.Owner=nil resolve(player,state) end
 end
 local active=world:CanRun()
 root:SetAttribute("Ready",active)root:SetAttribute("PersistenceStatus",world:Label())
 if active then elapsed+=dt*Config.SimulationSpeed else elapsed=0 end
 broadcast+=dt maintenance+=dt local steps=0
 if active then
  local limited
  elapsed,steps,limited=SimulationScheduler.Advance(elapsed,Config,function()
   -- Bound request work, with a fixed FIFO batch for deterministic replay. Every
   -- accepted tail stays queued; the simulation still completes each atomic step.
   local pending;pending,queue=RequestQueue.Take(queue)
   for _,item in ipairs(pending) do
    table.insert(actionLog,{Step=market.Step,Sequence=item.Sequence,Player=item.Player.UserId,Request=item.Request})
    if #actionLog>5000 then table.remove(actionLog,1) end
    process(item)
   end
   if not world:CanRun()then return false end
   population:Step();funded:ProcessResets()
  end,os.clock,started)
  if limited then performance.BudgetHits+=1 end
 end
 if not active and #queue>0 then
  for _,item in ipairs(queue)do local state=clients[item.Player]if state then reply(state,item.Request.Id,false,world:Label())end end
  queue={}
 end
 if maintenance>=1 then
  maintenance=0 task.spawn(function()world:Maintain()end)
  -- SL/TP can execute while a player is away; unlocks are still earned once.
  if active and funded then
   -- Progress from offline protective fills is evaluated on the same saved profile.
   
   for uid in pairs(market.Profiles)do funded:Evaluate(uid) end
  end
  -- Idle connections release expired acknowledgements even if they never send or subscribe again.
  local clock=os.clock() for _,state in pairs(clients)do replies:Prune(state,clock) end
  if world.Mode=="Following"then for player,state in pairs(clients)do route(player,state)end end
 end
 -- Do not skip simulation steps under load; catch up over subsequent frames.
 if broadcast>=Config.BroadcastSeconds then
  broadcast=broadcast%Config.BroadcastSeconds
  for player,state in pairs(clients) do if state.Subscribed then safeEmit(player,state) end end
 end
 local ms=(os.clock()-started)*1000
 performance.Frames+=1 performance.Steps+=steps performance.TotalMs+=ms
 performance.MaxMs=math.max(performance.MaxMs,ms) performance.Backlog=elapsed
 performance.LastMs=ms;performance.LastSteps=steps
 debug.profileend()
end)
-- Read-only diagnostic access in Studio; never replicated to game clients.
if RunService:IsStudio() then
 local diagnostic=Instance.new("BindableFunction") diagnostic.Name="StudioDiagnostics" diagnostic.Parent=script.Parent
 diagnostic.OnInvoke=function(command,a,b)
  if command=="Tests" then return require(script.Parent.MarketTests).Run() end
  if command=="ContinuityTests"then return require(script.Parent.WorldTests).Run()end
  if command=="SingleAccountTests"then return require(script.Parent.SingleAccountTests).Run()end
  if command=="SecurityTests"then return require(script.Parent.SecurityTests).Run()end
  if command=="LeaderboardStatus"then return {Cached=leaderboard.Cache,ReadError=leaderboard.ReadError,WriteError=leaderboard.WriteError,Pending=leaderboard.Pending,Scope=Leaderboards.Scope(world.Studio)}end
  if command=="Performance"then local result=table.clone(performance);result.MeanMs=result.TotalMs/math.max(1,result.Frames);return result end
  if command=="Actions" then return actionLog end
  if not market then return {Mode=world.Mode,Status=world:Label(),Error=world.LastError}end
  if command=="Execution"then
   local key=Config.Contracts[a]and a or Config.ContractOrder[1];local book=market.Books[key]
   local orders,levels,trades={},{Bids={},Asks={}},{ }
   for _,side in ipairs({"Bids","Asks"})do for _,level in ipairs(book[side])do
    local ids={};for _,order in ipairs(level.Orders)do table.insert(ids,order.Id)end
    table.insert(levels[side],{Price=level.Price*book.Spec.Tick,Quantity=level.Quantity,Orders=ids})
   end end
   for _,order in pairs(market.Orders)do if order.Contract==key then
    local row=table.clone(order);row.Price=row.Price and row.Price*book.Spec.Tick or nil;row.BlockedReason=market:OrderBlockReason(order)
    table.insert(orders,row)
   end end
   table.sort(orders,function(x,y)return x.Priority<y.Priority end)
   for i=math.max(1,#market.Trades-199),#market.Trades do local trade=market.Trades[i];if trade.Contract==key then table.insert(trades,trade)end end
   return {Contract=key,Step=market.Step,Time=market.Time,FairValue=book.FairReference and book.FairReference*book.Spec.Tick,
    Rules=market.Config.PlayerExecution,PriceBandFraction=market.Config.PriceBandFraction,Book=levels,Orders=orders,Executions=trades,
    Diagnostics=market.ExecutionDiagnostics,LastCloseNotificationError=market.LastCloseNotificationError,RequestQueueDepth=#queue}
  end
  if command=="Profiles"then
   local views={} for uid in pairs(market.Profiles)do views[uid]={Saved=market.Profiles[uid],View=funded:View(uid)}end return views
  end
  if command=="Stats"then
   local views={} for uid in pairs(market.Profiles)do views[uid]=funded:Stats(uid)end return views
  end
  local books={}
  for _,key in ipairs(Config.ContractOrder) do
   local book=market.Books[key]
   books[key]={Last=book.Last and book.Last*book.Spec.Tick,Volume=book.Volume,Up=book.Up,Down=book.Down,Bids=#book.Bids,Asks=#book.Asks,Candles=#book.Candles["1m"]}
  end
  local accounts={}
  for _,id in ipairs(market.AccountOrder) do local account=market.Accounts[id] if account.Player then accounts[id]=market:Snapshot(id,Config.ContractOrder[1],"1m",false) end end
  return {Seed=market.Seed,Mode=world.Mode,Status=world:Label(),Step=market.Step,Time=market.Time,Audit=market:Audit(),Books=books,Accounts=accounts,Participants=#population.Agents,Regime=population.Regime.Name}
 end
end
]====]):sub(2),Hash=([====[!30dbf55cabf4a2e7383a6b73393245c039c3a1db598ed1902dd6ec6aa52cd655]====]):sub(2),ExpectedHash=([====[!54e3217db8bd97e7da3fa59aac8af70a377dc22d75a3d740a44f87ceac580aee]====]):sub(2),ClassName=([====[!Script]====]):sub(2)}
release[ ([====[!ReplicatedStorage.MarketReign.MarketClient]====]):sub(2) ]={Source=([====[!-- Read-only client view. All orders and balances are owned by MarketServer.

local root=script.Parent

local Config=require(root.MarketConfig)

local Progression=require(root.ProgressionConfig)

local Protection=require(root.TradeProtection)
local ContractLimits=require(root.ContractLimits)
local Market={DepthLevels=Config.DepthLevels or 5,Contracts=Config.Contracts,ContractOrder=Config.ContractOrder,Progression=Progression,ContractLimit=ContractLimits.ForBalance}
Market.Contracts=table.clone(Config.Contracts)

Market.PositionOrder=table.clone(Config.ContractOrder)

for _,key in ipairs(Config.LegacyOrder) do Market.Contracts[key]=Config.LegacyContracts[key];table.insert(Market.PositionOrder,key) end

function Market.Number(value)

 local raw=string.format("%.2f",math.abs(value or 0)) local whole,decimal=raw:match("^(%d+)%.(%d+)$")

 return ((value or 0)<0 and "-" or "")..whole:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","").."."..decimal

end

function Market.Money(value) return "$"..Market.Number(value) end

function Market.Signed(value) return (value<0 and "−" or "+")..Market.Money(math.abs(value)) end

function Market.Snap(value,key) return math.round(value/Config.Contracts[key].Tick)*Config.Contracts[key].Tick end

Market.Protection=Protection.Resolve

local Session={} Session.__index=Session

function Market.New(base,preview,previewData)

 base=base or Progression.StartingBalance

 local self=setmetatable({Base=base,Prices={},Quotes={},Positions={},Orders={},History={},Fills={},Cache={},
  ProtectionPreferences=Protection.Preferences(),ClosedEvents={},ClosedEventOrder={},
  Time=0,Regime="Connecting",EventBacklog={},Speed=Config.SimulationSpeed,Ready=false,CanTrade=false,NextId=0,Pending={},Contract=Config.ContractOrder[1],Timeframe="1m",

  Changed=Instance.new("BindableEvent"),Replies=Instance.new("BindableEvent"),Events=Instance.new("BindableEvent"),Preview=preview},Session)

 self.SummaryData={Balance=base,Equity=base,Unrealized=0,Session=0,Allowance=Progression.StartingBalance,Count=0,Margin=0}

 for _,key in ipairs(Market.ContractOrder) do self.Prices[key]=Market.Contracts[key].Last end

 if preview then

  self.Regime="Edit preview"

  if previewData then

   -- An offline snapshot generated by the real exchange, used only to author Studio's saved GUI.

   self.Quotes=previewData.Quotes self.Cache=previewData.CandlesBySeries

   self.Time=previewData.Time self.Step=previewData.Step

   for key,quote in pairs(self.Quotes) do if quote.Last then self.Prices[key]=quote.Last end end

  end

  return self

 end

 self.Remote=root:WaitForChild("OrderRequest",60)

 local update=root:WaitForChild("MarketUpdate",60)

 if not self.Remote or not update then self.Regime="Exchange unavailable" return self end

 self.Connection=update.OnClientEvent:Connect(function(packet)

  self.DepthAccess=packet.DepthAccess or {Allowed=false,State="Checking"}
  self.DepthReceivedAt=os.clock();self.DepthContract=packet.Contract
  self.DepthLive=not packet.StatusOnly and packet.CanTrade==true
  if not self.DepthAccess.Allowed or not self.DepthLive then
   for _,quote in pairs(self.Quotes)do quote.Depth=nil end
  end

  self.CanTrade=packet.CanTrade==true self.ConnectionStatus=packet.ConnectionStatus self.PersistenceMode=packet.PersistenceMode
 self.RequestSession=packet.RequestSession or self.RequestSession
 self.NextId=math.max(self.NextId,packet.RequestHigh or 0)

  -- Atomic funded portfolio and live unlock projection arrive with each price batch.

  if packet.Portfolio then
   self.Portfolio=packet.Portfolio
   if not self.PreferencesDirty and not self.PreferencesPending then
    self.ProtectionPreferences=Protection.Preferences(packet.Portfolio.ProtectionPreferences)
   end
  end
  -- Lifetime stats are computed and persisted by the server; sent when they change.

  if packet.Stats then self.Stats=packet.Stats self.StatsAt=os.clock() end

  if packet.StatusOnly then

   if packet.NoAccount then

    -- No trading account yet (first join): clear any previous account view.

    self.Ready=false self.AccountKey=nil self.AccountToken=nil self.Positions={} self.Orders={} self.History={} self.Fills={}

   end

   for _,reply in ipairs(packet.Replies or {})do self:_reply(reply)end
   for _,event in ipairs(packet.Events or {})do self:_event(event)end

   self:_flushPreferences();self.Changed:Fire()return
  end

  self.Ready=true self.Base=packet.Base self.AccountKey=packet.AccountKey self.AccountToken=packet.AccountToken self.Positions=packet.Positions

  self.Orders=packet.Orders or self.Orders self.History=packet.History or self.History self.Fills=packet.Fills or self.Fills

  self.SummaryData=packet.Summary self.Quotes=packet.Quotes self.Time=packet.Time
  if not self.DepthAccess.Allowed then for _,quote in pairs(self.Quotes)do quote.Depth=nil end end

  -- Server-computed maximum new order per instrument/side (same rule the exchange enforces).

  self.Capacity=packet.Capacity self.Limit=packet.Limit self.Triggers=packet.Triggers or {}

  self.Regime=packet.Regime self.News=packet.News self.Speed=packet.Speed self.Step=packet.Step

  for key,quote in pairs(packet.Quotes) do if quote.Last then self.Prices[key]=quote.Last end end

  local cacheKey=packet.Contract..":"..packet.Timeframe

  -- A subscription can be dropped by the server's request rate limit (fast contract/timeframe

  -- switching). If the server is still streaming another series, ask again instead of waiting forever.

  if(packet.Contract~=self.Contract or packet.Timeframe~=self.Timeframe)and os.clock()-(self.SubscribedAt or 0)>1.5 then

   self:Subscribe(self.Contract,self.Timeframe)

  end

  if packet.Full then self.Cache[cacheKey]=packet.Candles else

   local data=self.Cache[cacheKey] or {} self.Cache[cacheKey]=data

   for _,candle in ipairs(packet.Candles) do

    local found=false

    for i=math.max(1,#data-2),#data do if data[i].Time==candle.Time then data[i]=candle found=true break end end

    if not found then table.insert(data,candle) end

   end

   while #data>Config.MaxCandles do table.remove(data,1) end

  end

  for _,reply in ipairs(packet.Replies or {}) do self:_reply(reply) end
  for _,event in ipairs(packet.Events or {})do self:_event(event)end

  self:_flushPreferences();self.Changed:Fire()
 end)

 self:Subscribe(Config.ContractOrder[1],"1m")

 local start=os.clock() while not self.Ready and not self.ConnectionStatus and os.clock()-start<45 do task.wait(0.1) end

 return self

end

-- Server events (unlocks, depletion notices) are announced once. Events that arrive before the UI

-- listens (the first packets after joining or reconnecting) are kept and replayed to OnEvent.

function Session:_event(event)
 if (event.Kind=="RankUp" or event.Kind=="Milestone")and event.Id then
  self.ProgressionEvents=self.ProgressionEvents or {};local key=event.Kind..":"..event.Id
  if self.ProgressionEvents[key]then return end;self.ProgressionEvents[key]=true
 end
 if event.Kind=="TradeClosed"then
  -- Execution identity, not price or a disappearing position, is the source of confirmation.
  if not event.Account or not event.TradeId then return end
  local key=event.Account..":"..event.TradeId
  if self.ClosedEvents[key]then return end
  self.ClosedEvents[key]=true;table.insert(self.ClosedEventOrder,key)
  if #self.ClosedEventOrder>128 then self.ClosedEvents[table.remove(self.ClosedEventOrder,1)]=nil end
 end
 if self.EventHandler then self.EventHandler(event) else table.insert(self.EventBacklog,event) end

 self.Events:Fire(event)

end
function Session:_reply(reply)
 self.Pending[reply.RequestId]=nil
 local pending=self.PreferencesPending
 if pending and pending.Id==reply.RequestId then
  self.PreferencesPending=nil
  if reply.Ok and Protection.SamePreferences(self.ProtectionPreferences,pending.Value)then self.PreferencesDirty=false end
  -- A retry can be rejected during an exchange pause; retain the latest local intention.
  self.PreferencesRetryAt=os.clock()+(reply.Ok and 0 or 2)
 end
 self.Replies:Fire(reply)
end
function Session:_flushPreferences(force)
 if self.Preview or not self.PreferencesDirty or not self.CanTrade then return end
 if not force and os.clock()<(self.PreferencesRetryAt or 0)then return end
 local pending=self.PreferencesPending
 if not force and pending and os.clock()-pending.At<2 then return end
 if pending then self.Pending[pending.Id]=nil end
 local value=table.clone(self.ProtectionPreferences)
 local ok,_,_,id=self:Send("ProtectionPreferences",table.clone(value))
 if ok then self.PreferencesPending={Id=id,Value=value,At=os.clock()}end
end
function Session:SetProtectionPreferences(value)
 local clean=Protection.ValidatePreferences(value)
 if not clean then return false,"Check your stop loss and take profit settings. Use amounts greater than $0."end
 self.ProtectionPreferences=clean;self.PreferencesDirty=true;self:_flushPreferences(true)
 return true
end
function Session:OnEvent(fn)

 self.EventHandler=fn

 local backlog=self.EventBacklog self.EventBacklog={}

 for _,event in ipairs(backlog) do fn(event) end

end

function Session:Send(action,request,expectedAccount)

 if self.Preview then return false,"Edit preview only. Press Play to trade." end

 if not self.Remote then return false,"Connecting to the exchange. Try again in a moment." end

 if action~="Subscribe"and action~="Stats"and not self.CanTrade then return false,self.ConnectionStatus or "Waiting for the exchange."end

 local now=os.clock()
 -- Bound pending acknowledgements even when the server rate-limits or loses a reply.
 local pendingCount,oldestId,oldestAt=0,nil,math.huge
 for id,at in pairs(self.Pending)do
  if now-at>30 then self.Pending[id]=nil else
   pendingCount+=1;if at<oldestAt then oldestId=id;oldestAt=at end
  end
 end
 if action=="Place"then
  self.PlaceTokens=math.min(6,(self.PlaceTokens or 6)+(now-(self.PlaceTokenTime or now))*5);self.PlaceTokenTime=now
  if self.PlaceTokens<1 then return false,"Orders are arriving too quickly. Wait a moment before placing another."end
  self.PlaceTokens-=1
 end

 self.NextId+=1 request=request or {} request.Id=self.NextId request.Action=action
 request.RequestSession=self.RequestSession

 request.ExpectedAccount=expectedAccount or self.AccountToken

 -- These read requests are answered by a snapshot, not a request acknowledgement.
 if action~="Subscribe"and action~="Stats"then
  if pendingCount>=64 and oldestId then self.Pending[oldestId]=nil end
  self.Pending[self.NextId]=now
 end
 self.Remote:FireServer(request)

 return true,"Order sent to exchange.","Orders",self.NextId

end

function Session:Subscribe(key,tf)

 self.Contract=key self.Timeframe=tf self.SubscribedAt=os.clock() self:Send("Subscribe",{Contract=key,Timeframe=tf})

end

function Session:Candles(key,tf) return self.Cache[key..":"..tf] or {} end

function Session:Pnl(p) return p.Unrealized or 0 end

function Session:Summary() return self.SummaryData end

function Session:Working() return self.Orders end

function Session:Cancel(id,protection) return self:Send("Cancel",{OrderId=id,Protection=protection}) end

function Session:AmendProtection(key,id,field,price,expectedPrice,expectedQuantity)

 return self:Send("AmendProtection",{Contract=key,OrderId=id,Protection=field,Price=price,ExpectedPrice=expectedPrice,ExpectedQuantity=expectedQuantity})

end

function Session:AmendOrder(key,id,price,expectedPrice,expectedQuantity)

 return self:Send("AmendOrder",{Contract=key,OrderId=id,Price=price,ExpectedPrice=expectedPrice,ExpectedQuantity=expectedQuantity})

end

function Session:Close(key) return self:Send("Close",{Contract=key}) end

-- Lifecycle requests always include ExpectedAccount through Send.

function Session:Start() return self:Send("Start",{}) end

function Session:Restart() return self:Send("Restart",{}) end
function Session:ResetAccount(expectedAccount) return self:Send("ResetAccount",{},expectedAccount) end
function Session:AcknowledgeAway(id) return self:Send("AcknowledgeAway",{SummaryId=id})end
function Session:CreateProtection(key,id,field,price,quantity)
 return self:Send("AmendProtection",{Contract=key,OrderId=id,Protection=field,Price=price,Create=true,ExpectedQuantity=quantity})
end

function Session:Flag(stage) return self:Send("Flag",{Stage=stage}) end

function Session:RefreshStats() return self:Send("Stats",{}) end

-- orderType: "Market", "Limit" (price = limit) or "Stop" (price = stop trigger; an entry that becomes a

-- market order when a trade reaches it). The server validates every field.

function Session:Place(key,direction,quantity,orderType,price,stopDollars,targetDollars,execution)

 if not self.Ready then return false,"Connecting to the exchange. Try again in a moment." end

 return self:Send("Place",{Contract=key,Direction=direction,Quantity=quantity,Type=orderType,Execution=execution or "Immediate",

  Price=(orderType=="Limit" or orderType=="Stop") and price or nil,StopDollars=stopDollars,TargetDollars=targetDollars})

end

-- Largest order the exchange currently accepts for this instrument and side (nil until the first packet).

function Session:MaxOrder(key,direction)

 local c=self.Capacity and self.Capacity[key]

 return c and (direction>0 and c.Buy or c.Sell) or nil

end

function Session:Destroy()

 if self.Connection then self.Connection:Disconnect() end self.Changed:Destroy() self.Replies:Destroy() self.Events:Destroy()

end

return Market
]====]):sub(2),Hash=([====[!41a061384568f8a81045bff2f5c39ea76d0326f84d686fa28e50212e22dba8d6]====]):sub(2),ExpectedHash=([====[!ccd73f5971966ea1e6c6f1c9d8a9516e80d16b335348b12b404ff3a936b26ca0]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.PlayerExecution]====]):sub(2) ]={Source=([====[!-- Persistent aggregate execution budgets. Cancelling, splitting requests, changing
-- instruments, or switching accounts of the same profile does not reset the allowance.
local Policy={}
local Protective=require(script.Parent.ProtectiveOrders)
function Policy.Owner(a)return tostring(a.ProfileId or a.Group or a.Id)end
function Policy.Liquidity(e,b,side)
 local depth=0
 for _,level in ipairs(side==1 and b.Asks or b.Bids)do
  if Policy.Allows(e,b,level.Price,side)then for _,o in ipairs(level.Orders)do
   if not e.Accounts[o.Owner].Player then depth+=e:_available(o,true)end
  end end
 end
 return depth
end
function Policy.State(e)
 local c=e.Config.PlayerExecution
 if not c then return nil end
 local window=math.floor(e.Time/c.WindowSeconds)
 if not e.Execution or e.Execution.Window~=window then
  e.Execution={Window=window,Owners={},Markets={},Cursor=e.Execution and e.Execution.Cursor or ""}
 end
 return e.Execution
end
function Policy.Budget(e,a,b,o)
 local c=e.Config.PlayerExecution
 if not c or not a.Player then return math.huge end
 if Protective.Valid(e,a,o)then return math.huge end
 local state=Policy.State(e);local owner=Policy.Owner(a)..":"..o.Direction
 local market=b.Key..":"..o.Direction
 local budget=state.Markets[market]
 if not budget then
  local limit=c.MarketContracts
  if b.FairReference then
   local depth=Policy.Liquidity(e,b,o.Direction)
   limit=math.min(limit,math.floor(depth*c.BookFraction))
  end
  budget={Used=0,Limit=limit};state.Markets[market]=budget
 end
 -- New clicks join the queue behind other players already waiting on this side.
 if not e.ProcessingPlayerQueue then
  for _,other in pairs(e.Orders)do
   if other~=o and other.Queued and other.Contract==b.Key and other.Direction==o.Direction
    and Policy.Owner(e.Accounts[other.Owner])~=Policy.Owner(a)then return 0 end
  end
 end
 local available=math.max(0,math.min(c.OwnerContracts-(state.Owners[owner]or 0),budget.Limit-budget.Used))
 -- Recheck current real bot depth: withdrawals and player-owned spoof quotes
 -- cannot turn an earlier allowance into permission to consume the whole side.
 if available>0 and b.FairReference then available=math.min(available,math.floor(Policy.Liquidity(e,b,o.Direction)*c.BookFraction))end
 -- Share a thin market's allowance among the owners awaiting a turn. A fixed 5,000
 -- slice must not hand the entire small-book allowance to one owner per window.
 if e.ProcessingPlayerQueue and e.PlayerQueuePeers then
  available=math.min(available,math.max(1,math.floor(budget.Limit/math.min(c.OwnersPerStep,e.PlayerQueuePeers[market]or 1))))
 end
 return available
end
function Policy.Record(e,a,b,side,quantity,o)
 if not e.Config.PlayerExecution or not a.Player then return end
 -- The server stamps this field; a completed exit may already have removed its position.
 if o and o.ProtectivePosition then return end
 local s=Policy.State(e);local owner=Policy.Owner(a)..":"..side;local market=b.Key..":"..side
 s.Owners[owner]=(s.Owners[owner]or 0)+quantity
 if s.Markets[market]then s.Markets[market].Used+=quantity end
end
-- Standard limits must either finish matching the crossed liquidity or rest without
-- crossing the book. Reject a blocked submission/amendment before any fill or cancel.
function Policy.StandardLimitAllowed(e,a,b,o,price,quantity)
 if not e.Config.PlayerExecution then return true end
 local side=o.Direction
 if not Policy.Allows(e,b,price,side)then return false end
 if not a.Player then return true end
 local allowance=Policy.Budget(e,a,b,o)
 local needed=0
 for _,level in ipairs(side==1 and b.Asks or b.Bids)do
  if (level.Price-price)*side>0 then break end
  for _,resting in ipairs(level.Orders)do
   local ra=e.Accounts[resting.Owner]
   local same=resting.Owner==a.Id or a.Group and ra.Group==a.Group or a.ProfileId and ra.ProfileId==a.ProfileId
   local available=not same and e:_available(resting,true)or 0
   if available>0 then
    if not Policy.Allows(e,b,level.Price,side)then return false end
    needed+=math.min(available,quantity-needed)
    if needed>allowance then return false end
    if needed>=quantity then return true end
   end
  end
 end
 return true
end
function Policy.Allows(e,b,price,side)
 -- Execution-price collar for EVERY aggressor and counterparty. `side` is the
 -- incoming direction: buys cannot pay above fair + guard; sells cannot accept
 -- below fair - guard. Better prices remain eligible. Passive outliers retain
 -- priority while blocked; no worse level can bypass the same collar.
 local c=e.Config.PlayerExecution
 return not c or not b.FairReference or (price-b.FairReference)*side<=c.GuardTicks*math.max(1,b.Spec.Scale or 1)
end
function Policy.Process(e)
 local c=e.Config.PlayerExecution;if not c then return end
 local state=Policy.State(e);local pending={}
 for _,o in pairs(e.Orders)do if o.Queued then
  local a=e.Accounts[o.Owner];local owner=Policy.Owner(a);local old=pending[owner]
  -- Protective exits get priority within one player's queue, then oldest order first.
  if not old or o.ReduceOnly and not old.ReduceOnly or o.ReduceOnly==old.ReduceOnly and (o.Priority or o.Id)<(old.Priority or old.Id)then pending[owner]=o end
 end end
 local owners={}for owner in pairs(pending)do table.insert(owners,owner)end;table.sort(owners)
 if #owners==0 then return end
 local peers={};for _,o in pairs(pending)do local key=o.Contract..":"..o.Direction;peers[key]=(peers[key]or 0)+1 end
 e.PlayerQueuePeers=peers
 local start=1;for i,owner in ipairs(owners)do if owner>state.Cursor then start=i;break elseif i==#owners then start=1 end end
 e.ProcessingPlayerQueue=true
 for offset=0,math.min(#owners,c.OwnersPerStep)-1 do
  local owner=owners[(start+offset-1)%#owners+1];local o=pending[owner]
  if e.Orders[o.Id] and (e:_available(o,false)<=0 or Policy.Budget(e,e.Accounts[o.Owner],e.Books[o.Contract],o)>0)then
   local filled=o.Filled;e:_match(e.Accounts[o.Owner],e.Books[o.Contract],o)
   if o.Filled>filled then state.Cursor=owner end
  end
 end
 e.ProcessingPlayerQueue=nil;e.PlayerQueuePeers=nil
end
return Policy
]====]):sub(2),Hash=([====[!6c9be5f007f93d0151980fd497aa6bd705f30ff8c8164a8be354b37eedc6bfb3]====]):sub(2),ExpectedHash=([====[!b7250ba06b334ebd0587082d1341e3dc19a1e57c0afe9ad9617403dd71f130c8]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.ProtectiveOrders]====]):sub(2) ]={Source=([====[!-- Server-owned exits are tied to one position. Client ReduceOnly requests do not
-- acquire this authority. A working TP uses ordinary book price/time priority.
local Protection={}
function Protection.Valid(e,a,o)
 local p=a.Positions[o.Contract]
 if not o.ReduceOnly or not p or o.ProtectivePosition~=p.Id or o.Direction~=-p.Direction then return false end
 if o.Protection=="Take profit"then
  return p.Target~=nil and o.Type=="Limit"and o.Price==math.round(p.Target/e.Books[o.Contract].Spec.Tick)
   and (not p.Triggered or p.Triggered=="Take profit") and not a.Liquidating
 end
 return o.Protection==p.Triggered and (o.Protection=="Stop loss"or o.Protection=="Account depleted"or o.Protection=="Margin liquidation"or o.Protection=="Account reset"and a.Resetting==true)
end
function Protection.Mark(e,a,key)
 if not a.Player then return end
 e.ProtectionDirty=e.ProtectionDirty or {};e.ProtectionDirty[a.Id]=e.ProtectionDirty[a.Id]or {};e.ProtectionDirty[a.Id][key]=true
end
local function ensure(e,a,key,deferred)
 local p=a.Positions[key]
 local exit=p and p.ExitOrder and e.Orders[p.ExitOrder]
 if exit and exit.ReduceOnly and exit.Type=="Market"and exit.Direction==-p.Direction
  and(p.Triggered=="Stop loss"or p.Triggered=="Account depleted"or p.Triggered=="Margin liquidation"or p.Triggered=="Account reset"and a.Resetting)then
  exit.Protection=p.Triggered;exit.ProtectivePosition=p.Id
 end
 local wanted=p and p.Target and (not p.Triggered or p.Triggered=="Take profit")and not a.Locked and not a.Liquidating
 -- Adopt old triggered TP exits without replacing their identity or priority.
 local target=p and (p.TargetOrder or p.Triggered=="Take profit"and p.ExitOrder)
 local o=target and e.Orders[target]
 if wanted and o and o.ReduceOnly and o.Type=="Limit"and o.Direction==-p.Direction and o.Price==math.round(p.Target/e.Books[key].Spec.Tick)then
  o.Protection="Take profit";o.ProtectivePosition=p.Id;p.TargetOrder=o.Id
 end
 local ids={};for id in pairs(a.OpenOrders)do table.insert(ids,id)end;table.sort(ids)
 for _,id in ipairs(ids)do
  local child=e.Orders[id]
  if child and child.Contract==key and child.Protection=="Take profit"then
   if not wanted or child~=o or not Protection.Valid(e,a,child)or child.Remaining<p.Quantity then
    e:Cancel(a.Id,id);if child==o then o=nil end
   elseif child.Remaining>p.Quantity then
    child.Cancelled+=child.Remaining-p.Quantity;child.Remaining=p.Quantity;e:_cleanBook(e.Books[key])
   end
  end
 end
 if not wanted then if p then p.TargetOrder=nil end;return end
 if not o or not e.Orders[o.Id]then
  p.TargetOrder=nil
  local ok,result=e:Submit(a.Id,{Contract=key,Direction=-p.Direction,Quantity=p.Quantity,Type="Limit",Price=p.Target,ReduceOnly=true},
   {Protection="Take profit",PositionId=p.Id,DeferProtection=deferred})
  assert(ok,"Cannot create protective target: "..tostring(result))
 elseif p.Triggered=="Take profit"then p.ExitOrder=o.Id end
end
function Protection.Sync(e,deferred)
 if e.SyncingProtection then return end
 e.SyncingProtection=true
 -- A fill can dirty the same position again while its new target matches.
 local passes=0
 while e.ProtectionDirty and next(e.ProtectionDirty)and passes<200 do
  local dirty=e.ProtectionDirty;e.ProtectionDirty=nil;passes+=1
  local owners={};for owner in pairs(dirty)do table.insert(owners,owner)end;table.sort(owners)
  for _,owner in ipairs(owners)do
   local a=e.Accounts[owner]
   -- Reset can retire an account after cancelling its target marked it dirty.
   if a then for _,key in ipairs(e.Config.ContractOrder)do if dirty[owner][key]then ensure(e,a,key,deferred)end end end
  end
 end
 e.SyncingProtection=nil
end
function Protection.Status(e,a,p,field)
 local closing=p.Triggered==(field=="Target"and "Take profit"or "Stop loss")
 local o=e.Orders[field=="Target"and p.TargetOrder or p.ExitOrder]
 local filled=field=="Target"and(p.TargetFilled or 0)or closing and o and o.Protection=="Stop loss"and o.Filled or 0
 if not closing then return field=="Target"and (o and e:OrderBlockReason(o)or "Working · awaiting price")or "Armed",filled end
 local reason=o and e:OrderBlockReason(o)or "Waiting for liquidity"
 if field=="Target"and o and not o.Queued then
  local Policy=require(script.Parent.PlayerExecution)
  reason=Policy.Allows(e,e.Books[o.Contract],o.Price,p.Direction)and "Waiting for liquidity at target"or "Waiting · price safeguard"
 end
 return (filled>0 and filled.." filled · "or "")..p.Quantity.." remaining · "..reason,filled
end
return Protection
]====]):sub(2),Hash=([====[!8341574ef876874e6b4ebbb4eee23550580c7aeb053d3954f8eb1e5678532a88]====]):sub(2),ExpectedHash=([====[!131979f9d20e0d2d5e56fe396fba087c9d11142809c49d093f7762e43567dae7]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.ProtectiveOrdersTests]====]):sub(2) ]={Source=([====[!local E=require(script.Parent.MarketEngine)
local C=table.clone(require(game.ReplicatedStorage.MarketReign.MarketConfig))
C.BotPopulation=nil -- This fixture intentionally has no autonomous population.
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Policy=require(script.Parent.PlayerExecution)
local F=require(script.Parent.FundedAccounts)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function order(e,id,side,qty,price,extra)
 local r={Contract="BX",Direction=side,Quantity=qty,Type=price and "Limit"or "Market",Price=price}
 for k,v in pairs(extra or {})do r[k]=v end
 local ok,result=e:Submit(id,r);assert(ok,tostring(result));return result
end
local function fresh(side,qty,entry,targetTicks)
 local c=clone(C);local e=E.new(c,731)
 for _,id in ipairs({"maker","other"})do e:AddAccount(id,1e9,10000,.9,false)end
 local a=e:AddAccount("user",1e9,1000000,.9,true)
 order(e,"maker",-side,qty,entry)
 assert(order(e,a.Id,side,qty,nil,{StopTicks=4,TargetTicks=targetTicks or 4}).Filled==qty)
 return e,a,a.Positions.BX,c
end
local function capture(e)
 return CP.Capture(e,setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(731),Agents={}},P))
end
local function same(a,b)
 assert(type(a)==type(b),"Different types")
 if type(a)~="table"then assert(a==b,"Different values: "..tostring(a).." / "..tostring(b));return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Extra key: "..tostring(k))end
end
function Tests.Run()
 local results={};local function test(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
 test("Reset with a working or partially filled target permits subsequent market updates and protection",function()
  for _,side in ipairs({-1,1})do for _,partial in ipairs({false,true})do
   local e=E.new(C,731);local f=F.new(e,L,C);f:Join("101")
   for _,id in ipairs({"maker","other"})do e:AddAccount(id,1e9,10000,.9,false)end
   local a=e.Accounts[f:Owner("101")]
   order(e,"maker",-side,3,5825)
   order(e,a.Id,side,3,nil,{StopTicks=8,TargetTicks=4})
   local p=a.Positions.BX;local target=p.TargetOrder
   if partial then order(e,"maker",side,1,p.Target)end
   local remaining=p.Quantity;local volume=e.TotalVolume
   local used=Policy.State(e).Owners["101:"..side]
   order(e,"maker",side,remaining,5825)
   assert(f:ResetAccount("101",a.Id))
   assert(not e.Accounts[a.Id]and not e.Orders[target])
   assert(e.TotalVolume==volume+remaining,"Reset did not trade its remaining exposure")
   assert(not e.Accounts["house:reset-exposure"],"Reset parked exposure off-market")
   assert(Policy.State(e).Owners["101:"..side]==used,"Reset replenished the entry allowance")
   e:ProcessStops();e:AdvanceClock(.25);e:ProcessPlayerOrders();e:Audit()
   local nextA=e.Accounts[f:Owner("101")]
   order(e,"maker",-side,1,5825)
   order(e,nextA.Id,side,1,nil,{StopTicks=8,TargetTicks=4})
   local nextP=nextA.Positions.BX;assert(nextP and e.Orders[nextP.TargetOrder],"Protection stopped syncing after reset")
   order(e,"other",side,1,nextP.Target)
   assert(not nextA.Positions.BX);e:Audit()
  end end
 end)
 for _,side in ipairs({-1,1})do
  test(side..": 307-contract target fills in thin liquidity with exhausted entry allowance",function()
   local e,a,p,c=fresh(side,307,5939.75,107);local target=p.Target;local stop=p.Stop
   local child=e.Orders[p.TargetOrder];assert(child and child.Remaining==307 and not child.Queued and not p.Triggered)
   local state=Policy.State(e);state.Markets["BX:"..(-side)]={Used=0,Limit=0};state.Owners["user:"..(-side)]=c.PlayerExecution.OwnerContracts
   e.Books.BX.FairReference=target/.25
   local before=e.TotalVolume
   order(e,"maker",side,9,target)
   assert(p.Quantity==298 and p.TargetFilled==9 and p.Stop==stop and p.Triggered=="Take profit")
   assert(e.TotalVolume==before+9 and e.Books.BX.Last*.25==target)
   order(e,"other",side,298,target+side*.25)
   assert(not a.Positions.BX and not e.Orders[child.Id],"Target was skipped or exposure reversed")
   assert(a.History[1].Reason=="Take profit"and a.History[1].Exit==target)
   assert(state.Markets["BX:"..(-side)].Used==0,"Protection consumed entry allowance")
   e:Audit();return {Contracts=307,Target=target,FirstFill=9,FinalPosition=0}
  end)
  test(side..": partial TP keeps stop and stop closes only the residual",function()
   local e,a,p=fresh(side,3,5825);local stop,target=p.Stop,p.Target;local tp=p.TargetOrder
   order(e,"maker",side,1,target);e:ProcessStops()
   assert(p.Quantity==2 and p.Stop==stop and e.Orders[tp].Remaining==2)
   local snap=e:Snapshot(a.Id,"BX","1m",true);assert(#snap.Orders==2)
   local found=false;for _,o in ipairs(snap.Orders)do if o.Protection=="Target"then
    assert(o.Filled==1 and o.Quantity==2 and o.Closing and o.Status:find("1 filled",1,true));found=true
   end end;assert(found)
   order(e,"maker",side,3,stop);order(e,"other",-side,1);e:ProcessStops();e:ProcessPlayerOrders()
   assert(not a.Positions.BX and not e.Orders[tp]and not next(a.OpenOrders))
   assert(a.History[1].Reason=="Stop loss"and a.History[1].Quantity==2)
   e:Audit()
  end)
  test(side..": saved working/partial targets retain FIFO and residual stop",function()
   local e,a,p,c=fresh(side,5,5825);order(e,"maker",side,2,p.Target);e:ProcessStops()
   local before=capture(e);local restored=CP.Restore(CP.Decode(CP.Encode(before)),c)
   same(before.Engine, capture(restored).Engine)
   local saved=restored.Accounts.user.Positions.BX
   assert(saved.Stop==p.Stop and saved.TargetFilled==2 and restored.Orders[saved.TargetOrder].Priority==e.Orders[p.TargetOrder].Priority)
   order(restored,"maker",side,3,saved.Target);assert(not restored.Accounts.user.Positions.BX);restored:Audit()
  end)
 end
 test("Resting TP observes FIFO and a later ordinary order cannot trade through it",function()
  local e,a,p=fresh(-1,3,5825);local target=p.Target
  local later=order(e,"other",1,2,target)
  order(e,"maker",-1,4,target-.25)
  assert(not a.Positions.BX and e.Orders[later.Id].Remaining==1)
  assert(e.Trades[#e.Trades-1].Buyer==a.Id and e.Trades[#e.Trades].Buyer=="other");e:Audit()
 end)
 test("Target resizing preserves prices, reduces quantity, and removes orphan orders on reversal",function()
  local e,a,p=fresh(1,3,5825);local target,stop=p.Target,p.Stop;local old=e.Orders[p.TargetOrder]
  order(e,"maker",-1,2,5825);order(e,a.Id,1,2)
  assert(p.Quantity==5 and p.Target==target and p.Stop==stop and e.Orders[p.TargetOrder].Remaining==5)
  assert(not e.Orders[old.Id],"Adding size retained old FIFO priority")
  local resized=e.Orders[p.TargetOrder];local priority=resized.Priority
  order(e,"maker",1,1,5825);order(e,a.Id,-1,1,nil,{ReduceOnly=true})
  assert(p.Quantity==4 and e.Orders[p.TargetOrder]==resized and resized.Remaining==4 and resized.Priority==priority)
  order(e,"maker",1,5,5825);order(e,a.Id,-1,5,nil,{StopTicks=8,TargetTicks=12})
  local reversed=a.Positions.BX;assert(reversed.Id~=p.Id and reversed.Quantity==1 and reversed.Direction==-1)
  assert(not e.Orders[resized.Id]and e.Orders[reversed.TargetOrder].ProtectivePosition==reversed.Id);e:Audit()
 end)
 test("Moving/cancelling a TP updates the book without printing a trade",function()
  local e,a,p=fresh(1,3,5825);local old=p.TargetOrder;local price=p.Target;local volume=e.TotalVolume
  assert(e:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=price+.25,ExpectedPrice=price}))
  assert(not e.Orders[old]and e.Orders[p.TargetOrder].Price==(price+.25)/.25 and e.TotalVolume==volume)
  assert(not e:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=price+.5,ExpectedPrice=price}))
  assert(not e:AmendOrder(a.Id,{Contract="BX",OrderId=p.TargetOrder,Price=price,ExpectedPrice=price+.25,ExpectedQuantity=3}))
  assert(not F.Perform(e,a.Id,{Action="Cancel",OrderId=p.TargetOrder}),"Raw child-id cancellation bypassed protection controls")
  local target=p.TargetOrder;assert(e:CancelProtection(a.Id,p.Id,"Target"));assert(not p.Target and not e.Orders[target]and p.Stop)
  e:ProcessStops();assert(not p.TargetOrder);e:Audit()
 end)
 test("Legacy queued TP migrates without fills then ignores exhausted entry budget",function()
  local e,a,p,c=fresh(-1,307,5939.75,107);local target=p.Target
  local state=Policy.State(e);state.Markets["BX:1"]={Used=0,Limit=0}
  local child=e.Orders[p.TargetOrder];e:_unrest(e.Books.BX,child);child.Queued=true;child.Protection=nil;child.ProtectivePosition=nil
  p.Triggered="Take profit";p.ExitOrder=child.Id;p.TargetOrder=nil
  e.Books.BX.FairReference=target/.25;order(e,"maker",-1,9,target-.25)
  local saved=capture(e);saved.Version=12
  local restored=CP.Restore(saved,c);local migrated=restored.Accounts.user.Positions.BX
  assert(restored.TotalVolume==e.TotalVolume and migrated.Quantity==307 and migrated.TargetOrder==child.Id)
  restored:ProcessPlayerOrders();assert(migrated.Quantity==298 and migrated.TargetFilled==9)
  assert(restored.Accounts.user.History[1].Exit==target-.25);restored:Audit()
 end)
 test("Fake protective fields and voluntary reduce-only orders cannot bypass entry budgets",function()
  local e,a,p,c=fresh(-1,3,5825);local state=Policy.State(e)
  state.Owners["user:1"]=c.PlayerExecution.OwnerContracts
  order(e,"maker",-1,3,5825)
  local r=order(e,a.Id,1,3,nil,{ReduceOnly=true,Execution="Immediate",Protection="Take profit",ProtectivePosition=p.Id})
  assert(r.Filled==0 and p.Quantity==3);assert(not next(a.History));e:Audit()
 end)
 test("Protective exits retain actual-price safeguards and report the reason",function()
  local e,a,p=fresh(-1,3,5825);local b=e.Books.BX
  -- Existing queued target is marketable against real quotes, but buying there is outside the guard.
  local child=e.Orders[p.TargetOrder];e:_unrest(b,child);child.Queued=true
  b.FairReference=(p.Target-10)/.25;p.Triggered="Take profit";p.ExitOrder=child.Id
  order(e,"maker",-1,2,p.Target-.25);e:ProcessPlayerOrders()
  assert(p.Quantity==3 and child.Queued and child.BlockedReason:find("price safeguard",1,true))
  local snap=e:Snapshot(a.Id,"BX","1m",true);local found=false
  for _,o in ipairs(snap.Orders)do if o.Protection=="Target"then found=o.Status:find("price safeguard",1,true)~=nil end end;assert(found)
  b.FairReference=p.Target/.25;e:ProcessPlayerOrders();assert(p.Quantity==1);e:Audit()
 end)
 test("Disconnected TP leaves depth but can close against connected liquidity",function()
  local e,a,p=fresh(-1,3,5825);e:SetConnectedOwners({user=true});e:SetConnected(a.Id,false)
  assert(#e.Books.BX.Bids==0 and e.Orders[p.TargetOrder].Queued)
  order(e,"maker",-1,2,p.Target);e:ProcessPlayerOrders();assert(p.Quantity==1 and p.Stop and p.TargetFilled==2)
  e:SetConnected(a.Id,true);e:ProcessPlayerOrders();assert(#e.Books.BX.Bids==1 and e.Orders[p.TargetOrder].Remaining==1)
  order(e,"maker",-1,1,p.Target);assert(not a.Positions.BX);e:Audit()
 end)
 test("A zero-liquidity market never fabricates a protective fill",function()
  local e,a,p=fresh(-1,307,5939.75,107);local volume=e.TotalVolume
  for _=1,5 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(p.Quantity==307 and e.TotalVolume==volume and not next(a.History));e:Audit()
 end)
 test("A bot limit cannot cross a target blocked by the price safeguard",function()
  local e,a,p=fresh(1,3,5825,100);e.Books.BX.FairReference=5825/.25
  local n=e.NextOrder
  local ok,message=e:Submit("maker",{Contract="BX",Direction=1,Quantity=2,Type="Limit",Price=p.Target})
  assert(not ok and message:find("No order placed",1,true)and e.NextOrder==n and p.Quantity==3);e:Audit()
 end)
 test("A stop consumes thin liquidity despite an exhausted entry budget",function()
  local e,a,p,c=fresh(1,3,5825);local stop=p.Stop
  local state=Policy.State(e);state.Markets["BX:-1"]={Used=0,Limit=0}
  state.Owners["user:-1"]=c.PlayerExecution.OwnerContracts;e.Books.BX.FairReference=stop/.25
  order(e,"maker",1,4,stop);order(e,"other",-1,1);e:ProcessStops()
  assert(not a.Positions.BX and a.History[1].Reason=="Stop loss");e:Audit()
 end)
 return results
end
return Tests
]====]):sub(2),Hash=([====[!a578e31885793d47df7e804e398aab50e51ad1829f98e2f74345659c9cb48567]====]):sub(2),ExpectedHash=([====[!c2fc8bfeaf62d3772dffd1a1fa353da9395da529e5b579711b3643897ac16749]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.Participants]====]):sub(2) ]={Source=([====[!-- One deterministic scheduler; participants never own task loops or modify trade prices.
local Participants={}
local BotPopulation=require(script.Parent.BotPopulation)
local BotExitRetry=require(script.Parent.BotExitRetry)
Participants.__index=Participants
local RNG={} RNG.__index=RNG
function RNG.new(seed) return setmetatable({State=math.floor(math.abs(seed))%2147483646+1},RNG) end
function RNG:Next() self.State=self.State*48271%2147483647 return self.State/2147483647 end
function RNG:Range(a,b) return a+(b-a)*self:Next() end
function RNG:Int(a,b) return math.floor(self:Range(a,b+1)) end
function RNG:Noise() return (self:Next()+self:Next()+self:Next()-1.5)*2 end
Participants.RNG=RNG
function Participants.new(engine)
 local self=setmetatable({Engine=engine,Config=engine.Config,Random=RNG.new(engine.Seed),Agents={},Markets={},Regime=nil,
  NextRegime=0,NextNews=80,NextBeliefs=0,News="No synthetic news",NewsUntil=0,Events={}},Participants)
 local r=self.Random
 self:_regime()
 for _,key in ipairs(self.Config.ContractOrder) do
  local book=engine.Books[key]
  self.Markets[key]={Fair=book.Reference,Anchor=book.Reference,Impulse=0}
  book.FairReference=book.Reference
  for i=1,self.Config.MakersPerInstrument do self:_agent(key,"Maker",i) end
  self:_ordinary(key)
  if self.Config.WhaleFrequency>0 then for i=1,self.Config.WhalesPerInstrument do self:_agent(key,"Whale",i) end end
  if not book.Spec.CloseOnly then for i=1,self.Config.ScalpersPerInstrument or 0 do self:_agent(key,"Scalper",i) end end
  if self.Config.Reserve and not book.Spec.CloseOnly then for i=1,self.Config.Reserve.Count do self:_agent(key,"Reserve",i)end end
 end
 self.PolicyVersion=self.Config.BotPopulation and self.Config.BotPopulation.Version or nil
 BotPopulation.Validate(self)
 -- A genuine opening auction: finite makers post, and a participant crosses a quote.
 for _,a in ipairs(self.Agents) do if a.Kind=="Maker" then self:_maker(a) end end
 for _,a in ipairs(self.Agents) do if a.Kind=="Reserve" then self:_reserve(a)end end
 for _,key in ipairs(self.Config.ContractOrder) do
  for _,a in ipairs(self.Agents) do if a.Key==key and a.Kind~="Maker" and a.Kind~="Reserve"then
   engine:Submit(a.Id,{Contract=key,Direction=r:Next()<0.5 and 1 or -1,Quantity=1,Type="Market"}) break
  end end
 end
 return self
end
function Participants:_ordinary(key)
 local kinds={"Liquidity","Momentum","Value","Reversion","Protective"}
 if self.Config.BotPopulation and not self.Engine.Books[key].Spec.CloseOnly then
  for _,kind in ipairs(kinds)do for i=1,self.Config.BotPopulation.Counts[kind]do self:_agent(key,kind,i)end end
 else
  for i=1,self.Config.ParticipantsPerInstrument do
   local total=0;for _,kind in ipairs(kinds)do total+=self.Config.BehaviorWeights[kind]or 0 end
   local draw=self.Random:Range(0,total);local chosen="Liquidity"
   for _,kind in ipairs(kinds)do draw-=self.Config.BehaviorWeights[kind]or 0;if draw<=0 then chosen=kind;break end end
   self:_agent(key,chosen,i)
  end
 end
end
function Participants:_profile(key,kind,index)
 local r=self.Random local maker=kind=="Maker" local whale=kind=="Whale"
 local id="bot:"..key..":"..kind..":"..index
 local budget=r:Int(maker and 350000 or whale and 600000 or 50000,maker and 650000 or whale and 1100000 or 160000)
 local a={Id=id,Key=key,Kind=kind,Budget=budget,Risk=r:Range(0.45,0.85),Limit=r:Int(maker and 140 or whale and 180 or 16,maker and 250 or whale and 350 or 60),
  Speed=r:Range(maker and 1.5 or whale and 28 or 2.5,maker and 4.5 or whale and 100 or 13),Size=r:Int(maker and 3 or whale and 18 or 1,maker and 9 or whale and 60 or 5),
  Bias=r:Range(-0.55,0.55),Belief=self.Markets[key].Fair+r:Noise()*9,Patience=r:Range(4,35),Aggression=r:Range(0.2,0.8),
  Next=r:Range(0.2,18),Stop=r:Int(16,85),Target=r:Int(20,140),Parent=0,ParentSide=1}
 if whale then a.Bias=index%2==0 and -0.3 or 0.3 end
 if kind=="Scalper" then
  local s=assert(self.Config.Scalper,"Scalper settings required")
  a.Size=r:Int(s.Size[1],s.Size[2]);a.Limit=a.Size
  a.Speed=r:Range(s.DecisionSeconds[1],s.DecisionSeconds[2])
  a.Stop=r:Int(s.StopTicks[1],s.StopTicks[2]);a.Target=r:Int(s.TargetTicks[1],s.TargetTicks[2])
  a.MaxHold=r:Range(s.HoldSeconds[1],s.HoldSeconds[2])
  a.Patience=r:Range(s.OrderLifetimeSeconds[1],s.OrderLifetimeSeconds[2])
  a.Cooldown=r:Range(s.CooldownSeconds[1],s.CooldownSeconds[2])
  a.Style=index%2==0 and "Momentum" or "Reversion"
  a.Lookback=r:Int(3,12);a.ReadyAt=0
 end
 if kind=="Reserve"then
  local c=self.Config.Reserve;budget=c.Capital;a.Budget=budget;a.Risk=.8;a.Limit=c.InventoryLimit
  a.Size=c.QuoteSizes and c.QuoteSizes[key]or c.QuoteSize;a.Speed=c.DecisionSeconds
  a.ReservePolicy=self.Config.ReservePopulationVersion
 end
 BotPopulation.Configure(self,a)
 return a
end
function Participants:_agent(key,kind,index)
 local a=self:_profile(key,kind,index)
 assert(not self.Engine.Accounts[a.Id],"Duplicate bot account")
 local account=self.Engine:AddAccount(a.Id,a.Budget,a.Limit,a.Risk,false)
 account.StartingCapital=a.Budget;account.NetCapitalAdjustments=0
 account.PolicyCapitalTarget=a.Budget
 if kind=="Reserve"then account.LiquidityProvider=true end
 table.insert(self.Agents,a)
 return a
end
-- Append missing makers to active markets. Saved agent ids may still use a retired symbol;
-- count by Key/Kind and never reuse an existing account. Quotes begin on normal future steps,
-- so restoring a world cannot execute trades or rewrite its tape just by adding liquidity.
function Participants:EnsureMakers(keys,target)
 return self:_ensurePopulation(keys,"Maker",target)
end
function Participants:EnsureScalpers(keys,target)
 return self:_ensurePopulation(keys,"Scalper",target)
end
function Participants:EnsureReserves(keys)
 return self:_ensurePopulation(keys,"Reserve",self.Config.Reserve and self.Config.Reserve.Count or 0)
end
-- Withdraw obsolete bot quotes on upgrade without executing trades or resetting ledgers.
-- Replacement sizes come from the current policy even for already-saved agents.
function Participants:RefreshReservePolicy()
 local c=self.Config.Reserve;if not c then return end
 for _,a in ipairs(self.Agents)do if a.Kind=="Reserve"and a.ReservePolicy~=self.Config.ReservePopulationVersion then
  self.Engine:CancelAll(a.Id,a.Key);a.Quotes={}
  a.Size=c.QuoteSizes and c.QuoteSizes[a.Key]or c.QuoteSize;a.Speed=c.DecisionSeconds
  a.ReservePolicy=self.Config.ReservePopulationVersion
  a.Next=self.Engine.Time+c.DecisionSeconds
 end end
end
function Participants:_ensurePopulation(keys,kind,target)
 local e=self.Engine local added=0
 for _,key in ipairs(keys) do
  if e.Books[key] and not e.Books[key].Spec.CloseOnly then
   local count=0
   for _,a in ipairs(self.Agents) do if a.Key==key and a.Kind==kind and not a.Retiring then count+=1 end end
   local index=count+1
   while count<target do
    while e.Accounts["bot:"..key..":"..kind..":"..index] do index+=1 end
    local a=self:_agent(key,kind,index)
    a.Next+=e.Time
    count+=1 index+=1 added+=1
   end
  end
 end
 return added
end
-- Add a new market on migration without reseeding or advancing the saved exchange.
-- Retired (close-only) books keep their original participants and economics until positions close.
function Participants:AddMarket(key)
 local e=self.Engine local r=self.Random local first=#self.Agents+1
 local book=e.Books[key]
 self.Markets[key]={Fair=book.Reference,Anchor=book.Reference,Impulse=0}
 book.FairReference=book.Reference
 for i=1,self.Config.MakersPerInstrument do self:_agent(key,"Maker",i) end
 self:_ordinary(key)
 if self.Config.WhaleFrequency>0 then for i=1,self.Config.WhalesPerInstrument do self:_agent(key,"Whale",i) end end
 if not book.Spec.CloseOnly then for i=1,self.Config.ScalpersPerInstrument or 0 do self:_agent(key,"Scalper",i) end end
 if self.Config.Reserve and not book.Spec.CloseOnly then for i=1,self.Config.Reserve.Count do self:_agent(key,"Reserve",i)end end
 for i=first,#self.Agents do
  local a=self.Agents[i] a.Next+=e.Time
  if a.Kind=="Maker" then self:_maker(a) end
  if a.Kind=="Reserve"then self:_reserve(a)end
 end
 for i=first,#self.Agents do
  local a=self.Agents[i]
  if a.Kind~="Maker" and a.Kind~="Reserve"then e:Submit(a.Id,{Contract=key,Direction=r:Next()<0.5 and 1 or -1,Quantity=1,Type="Market"}) break end
 end
end
function Participants:_regime()
 local r=self.Random local total=0 for _,regime in ipairs(self.Config.Regimes) do total+=regime.Weight end
 local draw=r:Range(0,total) local chosen=self.Config.Regimes[1]
 for _,regime in ipairs(self.Config.Regimes) do draw-=regime.Weight if draw<=0 then chosen=regime break end end
 self.Regime=chosen self.Direction=r:Next()<0.5 and 1 or -1
 self.NextRegime=self.Engine.Time+r:Range(self.Config.RegimeSeconds[1],self.Config.RegimeSeconds[2])
 table.insert(self.Events,{Step=self.Engine.Step,Kind="Regime",Name=chosen.Name,Direction=self.Direction})
 if #self.Events>40 then table.remove(self.Events,1) end
end
function Participants:_fit(a,side,quantity)
 local e=self.Engine;local ac=e.Accounts[a.Id];local lo,hi=0,math.max(0,math.floor(quantity))
 if e:Exposure(ac,a.Key,side,hi)then return hi end
 while lo<hi do local mid=math.ceil((lo+hi)/2);if e:Exposure(ac,a.Key,side,mid)then lo=mid else hi=mid-1 end end
 return lo
end
-- Migration never fabricates a closing fill. Excess/retiring positions work down through finite quotes.
function Participants:_repairRisk(a)
 local e=self.Engine;local ac=e.Accounts[a.Id]
 local retiring=a.Retiring;local needs=retiring
 for key,pos in pairs(ac.Positions)do
  -- ProcessStops owns triggered exits, including their retry schedule.
  if pos.Triggered then needs=true;continue end
  local maximum=retiring and 0 or math.min(ac.Limit,math.max(0,math.floor(e:Summary(ac).Equity*ac.Risk/e.Books[key].Spec.Margin)))
  if pos.Quantity>maximum then
   needs=true;e:CancelAll(a.Id,key)
   if BotExitRetry.Ready(e,ac,key,pos)then
    local ok,result=e:Submit(a.Id,{Contract=key,Direction=-pos.Direction,Quantity=math.min(64,pos.Quantity-maximum),Type='Market',ReduceOnly=true})
    if not ok or result.Filled==0 then BotExitRetry.Attempted(e,ac,key,pos)end
   end
  end
 end
 if retiring and not next(ac.Positions)then e:CancelAll(a.Id);a.Retired=true end
 return needs
end
function Participants:_observe(a)
 if not a.PolicyVersion or a.Kind~='Value' or self.Engine.Time<a.NextObservation then return end
 local now=self.Engine.Time;local elapsed=math.max(0,now-a.ObservedAt)
 local observation=self.Markets[a.Key].Fair+a.ValueOffset+self.Random:Noise()*a.ObservationNoise
 a.Belief+=(observation-a.Belief)*(1-math.exp(-math.log(2)*elapsed/a.BeliefHalfLife))
 a.ObservedAt=now;a.NextObservation=now+a.ObservationSeconds*self.Random:Range(.7,1.3)
end
-- Funded reserve liquidity follows independent fair value, never the last player fill.
-- Quotes are passive and finite. Each replacement reserves real inventory and margin.
function Participants:_reserve(a)
 local e=self.Engine;local b=e.Books[a.Key];local c=self.Config.Reserve;local account=e.Accounts[a.Id]
 if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 a.Quotes=a.Quotes or {}
 local position=account.Positions[a.Key];local inventory=position and position.Quantity*position.Direction or 0
 local fair=math.round(self.Markets[a.Key].Fair);b.FairReference=fair
 local scale=c.SpacingTicks or math.max(1,b.Spec.Scale or 1)
 local stress=math.max(.25,math.min(1,self.Regime.Liquidity))
 local skew=math.clamp(math.round(inventory/a.Limit*4),-4,4)
 for depth,offset in ipairs(c.Offsets)do for _,side in ipairs({1,-1})do
  local slot=side..":"..depth;local held=a.Quotes[slot]and e.Orders[a.Quotes[slot]]
  local tick=math.max(1,fair-skew-side*math.ceil(offset*scale))
  if held and e.Time-held.Time>=c.RestSeconds and math.abs(held.Price-tick)>=c.RepriceTicks then
   e:Cancel(a.Id,held.Id);held=nil
  end
  if not held then
   a.Quotes[slot]=nil
   local opposing=side==1 and b.Asks[1]or b.Bids[1]
   if not opposing or (tick-opposing.Price)*side<0 then
    local variation=c.SizeVariation and self.Random:Range(c.SizeVariation[1],c.SizeVariation[2])or 1
    local size=math.max(1,math.floor(a.Size*variation*stress*(1+(depth-1)*(c.DepthGrowth or .5))*(1-inventory/a.Limit*side*.8)))
    local lo,hi=0,math.max(0,size)
    if not e:Exposure(account,a.Key,side,hi)then
     while lo<hi do local mid=math.ceil((lo+hi)/2);if e:Exposure(account,a.Key,side,mid)then lo=mid else hi=mid-1 end end
     size=lo
    end
    if size>0 then
     local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",Price=tick*b.Spec.Tick,Expires=e.Time+c.RestSeconds*30})
     if ok and result.Remaining>0 then a.Quotes[slot]=result.Id end
    end
   end
  end
 end end
end
function Participants:_maker(a)
 local e=self.Engine local b=e.Books[a.Key] local r=self.Random local c=b.Spec local market=self.Markets[a.Key]
 local account=e.Accounts[a.Id] if account.Locked or account.Liquidating then e:CancelAll(a.Id,a.Key);return end
 local policy=self.Config.MakerQuotePolicyVersion or 2
 if a.QuotePolicy~=policy then e:CancelAll(a.Id,a.Key);a.Quotes={};a.ReplenishAt={};a.QuotePolicy=policy end
 local p=account.Positions[a.Key] local inventory=p and p.Quantity*p.Direction or 0
 local stress=self.Regime.Volatility*self.Config.Volatility+math.min(6,b.Volatility)*0.2
 local center=(b.Last or b.Reference)*0.83+market.Fair*0.17-inventory/a.Limit*(5+stress*5)
 local spread=math.max(1,math.floor(stress*0.8+b.Volatility*0.2))
 local liquidity=self.Regime.Liquidity*self.Config.Liquidity
 if self.Engine.Time<self.NewsUntil then liquidity*=0.6 end
 local minRest=self.Config.MakerMinRestSeconds or 18
 local reprice=self.Config.MakerRepriceTicks or 3
 local replenish=self.Config.MakerReplenishSeconds or math.max(4,minRest/3)
 local sizeMultiplier=self.Config.MakerQuoteSizeMultiplier or 1
 local activeDepth=liquidity<.35 and 1 or liquidity<.7 and 2 or 3
 for depth=1,3 do
  for _,side in ipairs({1,-1}) do
   local slot=tostring(side)..":"..depth
   local held=a.Quotes[slot]and e.Orders[a.Quotes[slot]]
   if a.Quotes[slot]and not held then a.Quotes[slot]=nil;a.ReplenishAt[slot]=e.Time+replenish end
   local tick=math.max(1,math.round(center-side*(spread+(depth-1)*math.max(1,math.floor(stress)))))
   local age=held and e.Time-held.Time or math.huge
   local eligible=depth<=activeDepth
   if held and age>=minRest and (not eligible or math.abs(held.Price-tick)>=reprice)then
    e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil
   end
   if eligible and not held and e.Time>=(a.ReplenishAt[slot]or 0)then
    local size=math.max(1,math.floor(a.Size*sizeMultiplier*liquidity*(1+(depth-1)*.15)*(1-inventory/a.Limit*side*.8)))
    -- Fit the quote to remaining buying power instead of rejecting the whole larger quote.
    -- This includes all working orders; no new capital or inventory allowance is created.
    if not e:Exposure(account,a.Key,side,size) then
     local lo,hi=0,size
     while lo<hi do
      local mid=math.ceil((lo+hi)/2)
      if e:Exposure(account,a.Key,side,mid) then lo=mid else hi=mid-1 end
     end
     size=lo
    end
    if size>0 then
     local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",Price=tick*c.Tick,Expires=e.Time+minRest*6})
     if ok and result.Remaining>0 then a.Quotes[slot]=result.Id end
    end
   end
  end
 end
end
-- One small position at a time. Every fill goes through the shared finite book.
-- Profit-taking rests as real liquidity; stops and timed exits cannot reverse the position.
function Participants:_scalper(a)
 local e,r=self.Engine,self.Random local b=e.Books[a.Key] local s=self.Config.Scalper
 local account=e.Accounts[a.Id] local p=account.Positions[a.Key]
 if p then
  if a.PositionId~=p.Id then
   a.PositionId=p.Id;a.OpenedAt=e.Time
   e:CancelAll(a.Id,a.Key) -- Cancel any unfilled entry remainder before managing the exit.
  end
  if p.Triggered or account.Liquidating then e:CancelAll(a.Id,a.Key);return end
  if e.Time-a.OpenedAt>=a.MaxHold or b.Spec.CloseOnly or account.Locked then
   e:CancelAll(a.Id,a.Key)
   if BotExitRetry.Ready(e,account,a.Key,p)then
    local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=-p.Direction,Quantity=p.Quantity,Type="Market",ReduceOnly=true})
    if not ok or result.Filled==0 then BotExitRetry.Attempted(e,account,a.Key,p)end
   end
   return
  end
  -- Keep the target's queue priority until filled, stopped, or the holding time expires.
  if not next(account.OpenOrders) then
   local target=math.max(1,math.round(p.Entry/b.Spec.Tick)+p.Direction*a.Target)*b.Spec.Tick
   e:Submit(a.Id,{Contract=a.Key,Direction=-p.Direction,Quantity=p.Quantity,Type="Limit",Price=target,ReduceOnly=true})
  end
  return
 end
 if a.PositionId then
  e:CancelAll(a.Id,a.Key);a.PositionId=nil;a.OpenedAt=nil
  a.ReadyAt=e.Time+a.Cooldown*r:Range(0.75,1.25)
 end
 if account.Locked or account.Liquidating or b.Spec.CloseOnly then e:CancelAll(a.Id,a.Key);return end
 if e.Time<a.ReadyAt or next(account.OpenOrders) then return end
 e:_pruneBook(b)
 local bid,ask=b.Bids[1],b.Asks[1]
 if not bid or not ask then return end
 local spread=ask.Price-bid.Price
 if spread<1 or spread>s.MaxSpreadTicks or spread>=a.Target then return end
 local last=b.Last or b.Reference local previous=b.Recent[math.max(1,#b.Recent-a.Lookback)] or last
 local move=(last-previous)/math.max(1,b.Volatility*2)
 local policy=a.PolicyVersion and self.Config.BotPopulation
 local signal=a.Bias*(policy and .2 or 1)+r:Noise()*(policy and policy.ScalperNoise or 1)+(a.Style=="Momentum" and move or -move)
 if policy and math.abs(last-previous)<math.max(a.MinMove,spread+s.MaxSlippageTicks+a.EntryBuffer)then return end
 if math.abs(signal)<(a.EntryThreshold or .2) then return end
 local side=signal>0 and 1 or -1
 local aggressive=r:Next()<s.AggressiveChance
 -- A marketable limit caps entry slippage; passive entries join the best quote.
 local tick=aggressive and (side==1 and ask.Price+s.MaxSlippageTicks or bid.Price-s.MaxSlippageTicks)
  or (side==1 and bid.Price or ask.Price)
 local size=self:_fit(a,side,a.Size);if size<1 then return end
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",
  Price=math.max(1,tick)*b.Spec.Tick,StopTicks=a.Stop,Expires=e.Time+a.Patience})
 if ok then
  a.ReadyAt=e.Time+a.Cooldown
  if result.Filled>0 then
   e:CancelAll(a.Id,a.Key)
   local held=account.Positions[a.Key]
   if held then a.PositionId=held.Id;a.OpenedAt=e.Time end
  end
 end
end
function Participants:_trader(a)
 local e=self.Engine local b=e.Books[a.Key] local r=self.Random local c=b.Spec
 local account=e.Accounts[a.Id]
 if account.Locked or account.Liquidating or account.Positions[a.Key] and account.Positions[a.Key].Triggered then return end
 if r:Next()<0.25 then return end -- varied inactivity, even around news
 local last=b.Last or b.Reference local market=self.Markets[a.Key]
 if not(a.PolicyVersion and a.Kind=='Value')then
  a.Belief+=(market.Fair-a.Belief)*r:Range(0.02,0.18)+r:Noise()*self.Regime.Volatility*c.Scale*0.6
 end
 local p=account.Positions[a.Key] local inventory=p and p.Quantity*p.Direction or 0
 local recent=b.Recent local previous=recent[math.max(1,#recent-(a.Lookback or r:Int(8,35)))] or last
 local momentum=(last-previous)/math.max(3,b.Volatility*8)
 local edge=(a.Belief-last)/math.max(4,b.Volatility*8)
 local signal=a.Bias+r:Noise()*1.3-inventory/a.Limit*1.8
 if a.Kind=="Momentum" then signal+=momentum*r:Range(0.5,1.4)
 elseif a.Kind=="Value" then
  if a.PolicyVersion then
   local bid,ask=b.Bids[1],b.Asks[1];if not bid or not ask then return end
   if math.abs(a.Belief-last)<(ask.Price-bid.Price)/2+a.EntryBuffer then return end
   signal=edge*a.SignalWeight+a.Bias*.2+r:Noise()*.2-inventory/a.Limit*1.8
  else signal+=edge*r:Range(0.6,1.5)end
 elseif a.Kind=="Reversion" then signal-=momentum*r:Range(0.6,1.6) signal+=edge*0.3
 elseif a.Kind=="Protective" then signal+=edge*0.4 end
 if math.abs(signal)<(a.EntryThreshold or r:Range(0.1,0.55)) then return end
 local side=signal>0 and 1 or -1 local size=r:Int(1,a.Size)
 local aggressive=r:Next()<a.Aggression
 if a.Kind=="Whale" then
  if a.Parent>0 then side=a.ParentSide size=math.min(a.Parent,r:Int(4,math.max(5,math.floor(a.Size/3)))) a.Parent-=size
  else
   size=r:Int(math.floor(a.Size/2),a.Size)
   if r:Next()<0.55 then a.Parent=size*r:Int(2,4) a.ParentSide=side size=math.min(a.Parent,r:Int(4,12)) a.Parent-=size end
  end
  aggressive=r:Next()<0.8
 end
 if r:Next()<0.45 then
  local stale={}
  for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o and e.Time-o.Time>=math.max(12,a.Patience)then table.insert(stale,id)end end
  table.sort(stale);for _,id in ipairs(stale)do e:Cancel(a.Id,id)end
 end
 size=self:_fit(a,side,size);if size<1 then return end
 local request={Contract=a.Key,Direction=side,Quantity=size,Type=aggressive and "Market" or "Limit",Expires=e.Time+a.Patience*r:Range(0.5,1.5)}
 if not aggressive then
  local distance=r:Int(1,math.max(2,math.floor(3+self.Regime.Volatility*3)))
  request.Price=math.max(1,math.round(last-side*distance))*c.Tick
 end
 if a.Kind=="Protective" or (a.Kind~="Maker" and r:Next()<0.16) then request.StopTicks=a.Stop request.TargetTicks=a.Target end
 e:Submit(a.Id,request)
end
function Participants:Step()
 local e=self.Engine local r=self.Random
 e:AdvanceClock(self.Config.StepSeconds)
 if e.Time>=self.NextRegime then self:_regime() end
 if self.Config.NewsFrequency>0 and e.Time>=self.NextNews then
  local sign=r:Next()<0.5 and 1 or -1
  local magnitude=r:Range(8,40)*self.Config.Volatility
  for _,key in ipairs(self.Config.ContractOrder) do
   local m=self.Markets[key] local shock=sign*magnitude*e.Books[key].Spec.Scale*r:Range(0.4,1.5)
   m.Anchor+=shock m.Impulse+=shock*0.1
  end
  self.News=(sign>0 and "Optimistic" or "Cautious").." synthetic outlook"
  self.NewsUntil=e.Time+r:Range(20,55) self.NextNews=e.Time+r:Range(140,420)/self.Config.NewsFrequency
  table.insert(self.Events,{Step=e.Step,Kind="News",Name=self.News,Direction=sign}) if #self.Events>40 then table.remove(self.Events,1) end
 end
 if e.Time>=self.NextBeliefs then
  for _,key in ipairs(self.Config.ContractOrder) do
   local m=self.Markets[key] local c=e.Books[key].Spec
   m.Anchor+=self.Regime.Trend*self.Direction*c.Scale+r:Noise()*self.Regime.Volatility*self.Config.Volatility*c.Scale*0.16
   m.Fair+=(m.Anchor-m.Fair)*0.025+m.Impulse*0.06
   m.Impulse*=0.96
   m.Fair=math.clamp(m.Fair,e.Books[key].Reference*0.6,e.Books[key].Reference*1.4)
   e.Books[key].FairReference=math.round(m.Fair)
  end
  self.NextBeliefs=e.Time+1
 end
 for _,a in ipairs(self.Agents) do
  if not a.Retiring then self:_observe(a)end
  if not a.Retired and e.Time>=a.Next then
   local repairing=(a.PolicyVersion or a.Retiring)and self:_repairRisk(a)
   if not repairing then
    if a.Kind=="Maker" then self:_maker(a) elseif a.Kind=="Reserve"then self:_reserve(a)elseif a.Kind=="Scalper" then self:_scalper(a) else self:_trader(a) end
   end
   local delay=a.Speed*r:Range(0.45,1.65)/self.Regime.Activity
   if a.Kind=="Maker" then delay*=self.Config.MakerDecisionMultiplier or 1 end
   if a.Kind=="Whale" then delay=a.Parent>0 and r:Range(1.5,6)*(a.PolicyVersion and self.Config.BotPopulation.WhaleActivityScale or 1) or delay/math.max(0.0001,self.Config.WhaleFrequency) end
   if repairing then delay=r:Range(2,5)end
   a.Next=e.Time+delay
   e:ProcessStops()
  end
 end
 e:ProcessPlayerOrders()
end
return Participants
]====]):sub(2),Hash=([====[!06770e7acb8027cf8864761f1ff63076f5b8bc91bf0a92aeecbbedfa18a222a5]====]):sub(2),ExpectedHash=([====[!8a63e10b9ed59ef6c09c3f47b46d561d376215bcc34a528c3ec8b4a0b8d3dc7a]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.BotExitRetry]====]):sub(2) ]={Source=([====[!-- Derived liquidity checks are shared by blocked bot exits. Actual fills still go
-- through Submit, including ownership, reduce-only, capacity and price safeguards.
local Policy=require(script.Parent.PlayerExecution)
local Retry={}
local function revision(book)return book.ExitLiquidityRevision or 0 end
local function liquidity(e,b,side)
 e.BotExitLiquidity=e.BotExitLiquidity or {}
 local key=b.Key..":"..side;local cached=e.BotExitLiquidity[key]
 if cached and cached.Step==e.Step and cached.Revision==revision(b) and cached.Eligibility==e.EligibilityRevision and cached.Fair==b.FairReference then return cached.Available end
 local available=false
 for _,level in ipairs(side==1 and b.Asks or b.Bids)do
  if not Policy.Allows(e,b,level.Price,side)then break end
  for _,o in ipairs(level.Orders)do
   local a=e.Accounts[o.Owner]
   if a and e:_available(o,true)>0 then available=true;break end
  end
  if available then break end
 end
 e.BotExitLiquidity[key]={Step=e.Step,Revision=revision(b),Eligibility=e.EligibilityRevision,Fair=b.FairReference,Available=available}
 return available
end
local function remember(e,b,p,attempted)
 local prior=p.BotExitRetry
 p.BotExitRetry={At=e.Time+(e.Config.BotExitRetrySeconds or 4),Revision=revision(b),Eligibility=e.EligibilityRevision,Fair=b.FairReference,
  Reason=p.Triggered,AttemptStep=attempted and e.Step or prior and prior.AttemptStep}
end
function Retry.Ready(e,a,key,p)
 if a.Player or p.Triggered=="Take profit"then return true end
 local b=e.Books[key];local last=p.BotExitRetry
 if last and last.Reason==p.Triggered then
  if last.AttemptStep==e.Step then return false end
  if e.Time<last.At and last.Revision==revision(b) and last.Eligibility==e.EligibilityRevision and last.Fair==b.FairReference then return false end
 end
 if not liquidity(e,b,-p.Direction)then remember(e,b,p,false);return false end
 return true
end
function Retry.Attempted(e,a,key,p)
 if not a.Player and p.Triggered~="Take profit"then remember(e,e.Books[key],p,true)end
end
return Retry
]====]):sub(2),Hash=([====[!3aefb64355fdb578ce7d54fe41dc5a02b38e318a6223be85080d186504156d00]====]):sub(2),ExpectedHash=([====[!4822b7b987b6fd1c58767aba71b5a629bf8184925f0e53102419c04c9ef2c1eb]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.BotExitRetryTests]====]):sub(2) ]={Source=([====[!local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Scheduler=require(script.Parent.SimulationScheduler)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Tests={}
local function copy(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
function Tests.Fixture(count)
 local c=copy(Config);c.BotPopulation=nil;c.Contracts.BX.Last=5230.25
 local e=Engine.new(c,73015);local b=e.Books.BX;b.FairReference=5230.25/b.Spec.Tick
 e:AddAccount("player",20000000,20000,.8,true)
 assert(e:Submit("player",{Contract="BX",Direction=1,Quantity=13000,Type="Limit",Price=5230.25}))
 for i=1,count do
  local id="short:"..i;e:AddAccount(id,100000,100,.8,false)
  local ok,result=e:Submit(id,{Contract="BX",Direction=-1,Quantity=10,Type="Market"});assert(ok and result.Filled==10)
  local p=e.Accounts[id].Positions.BX;p.Triggered="Stop loss"
 end
 for _,price in ipairs({5282.5,5284.75})do assert(e:Submit("player",{Contract="BX",Direction=-1,Quantity=1300,Type="Limit",Price=price}))end
 b.FairReference=5202.25/b.Spec.Tick
 return e,c
end
function Tests.Benchmark(steps)
 local e=Tests.Fixture(55);local first=e.NextOrder;local prunes=0;local old=e._pruneBook
 e._pruneBook=function(self,book)prunes+=1;return old(self,book)end
 local start=os.clock()
 for _=1,steps or 256 do e:AdvanceClock(e.Config.StepSeconds)end
 return {Steps=steps or 256,Milliseconds=(os.clock()-start)*1000,NewOrders=e.NextOrder-first,BookScans=prunes,ContractsStillHeld=e.Accounts.player.Positions.BX.Quantity}
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("55 blocked exits behind a 13000-contract bid create no repeated orders or full-book scans",function()
  local r=Tests.Benchmark(256);assert(r.NewOrders==0 and r.BookScans==0);assert(r.ContractsStillHeld==550)
 end)
 test("New executable quote wakes a blocked exit and fills only available contracts",function()
  local e=Tests.Fixture(1);e:AdvanceClock(.25)
  local p=e.Accounts['short:1'].Positions.BX;assert(p.BotExitRetry)
  for id in pairs(e.Accounts.player.OpenOrders)do local o=e.Orders[id];if o.Direction==1 then e:Cancel('player',id)end end
  e:AddAccount('new-seller',100000,100,.8,false)
  -- New liquidity must be inside the same guard for bots and players.
  assert(e:Submit('new-seller',{Contract='BX',Direction=-1,Quantity=3,Type='Limit',Price=5203}))
  e:AdvanceClock(.25);assert(p.Quantity==7 and #e.Accounts['short:1'].History==1)
  local trade=e.Trades[#e.Trades];assert(trade.Price==5203 and trade.Quantity==3)
  e:AdvanceClock(.25);assert(p.Quantity==7);e:Audit()
 end)
 test("Fair-value change wakes eligible player liquidity before retry deadline",function()
  local e=Tests.Fixture(1);e:AdvanceClock(.25)
  e.Books.BX.FairReference=5280/e.Books.BX.Spec.Tick
  e:AdvanceClock(.25);assert(not e.Accounts['short:1'].Positions.BX)
  assert(e.Trades[#e.Trades].Price==5282.5);e:Audit()
 end)
 test("Blocked retry state survives checkpoint round trip and resumes identically",function()
  local e,c=Tests.Fixture(3);e:AdvanceClock(.25)
  local population=setmetatable({Engine=e,Config=c,Random=Participants.RNG.new(73015),Agents={}},Participants)
  local snap=Checkpoint.Capture(e,population);local restored=Checkpoint.Restore(snap,c)
  assert(restored.Books.BX.ExitLiquidityRevision==e.Books.BX.ExitLiquidityRevision)
  for _=1,20 do e:AdvanceClock(.25);restored:AdvanceClock(.25)end
  assert(e.NextOrder==restored.NextOrder and e.TradeHash==restored.TradeHash)
  e:Audit();restored:Audit()
 end)
 test("Bot risk repair does not submit a second exit while a stop owns the position",function()
  local e,c=Tests.Fixture(1);local a=e.Accounts['short:1'];a.Limit=1
  local p=setmetatable({Engine=e,Config=c},Participants);local n=e.NextOrder
  assert(p:_repairRisk({Id='short:1'}));assert(e.NextOrder==n)
 end)
 test("Timed scalper exits reuse retry controls while the only ask is blocked",function()
  local e,c=Tests.Fixture(1);local account=e.Accounts['short:1'];local position=account.Positions.BX;position.Triggered=nil
  local population=setmetatable({Engine=e,Config=c},Participants)
  local agent={Id=account.Id,Key='BX',PositionId=position.Id,OpenedAt=-100,MaxHold=1}
  local n=e.NextOrder
  for _=1,20 do population:_scalper(agent);e:AdvanceClock(.25)end
  assert(e.NextOrder==n and position.Quantity==10)
  e.Books.BX.FairReference=5280/.25;population:_scalper(agent)
  assert(not account.Positions.BX);e:Audit()
 end)
 test("Bot take-profit limits still rest without opposing liquidity",function()
  local e=Tests.Fixture(1);local p=e.Accounts['short:1'].Positions.BX
  p.Triggered='Take profit';p.Target=5220
  e:AdvanceClock(.25);assert(p.ExitOrder and e.Orders[p.ExitOrder].Type=='Limit')
  assert(e.Orders[p.ExitOrder].Price*e.Books.BX.Spec.Tick==5220);e:Audit()
 end)
 test("Guard-blocked bot target retains one queued order and recovers without reversing",function()
  local e=Tests.Fixture(1);local p=e.Accounts['short:1'].Positions.BX
  p.Triggered='Take profit';p.Target=5290
  e:AdvanceClock(.25);local id=p.ExitOrder;assert(id and e.Orders[id].Queued)
  local n=e.NextOrder
  for _=1,20 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(e.NextOrder==n and e.Orders[id].Remaining==10)
  e.Books.BX.FairReference=5280/e.Books.BX.Spec.Tick;e:AdvanceClock(.25);e:ProcessPlayerOrders()
  assert(not e.Accounts['short:1'].Positions.BX and not e.Orders[id]);e:Audit()
 end)
 test("Time budget yields after atomic steps and carries every unprocessed step",function()
  local time=0;local completed=0;local c={StepSeconds=.25,MaxCatchupSteps=32,SimulationFrameBudgetMs=8}
  local remaining,steps,limited=Scheduler.Advance(8,c,function()completed+=1;time+=.003 end,function()return time end)
  assert(steps==3 and completed==3 and remaining==7.25 and limited)
  while remaining>=.25 do remaining=Scheduler.Advance(remaining,c,function()completed+=1;time+=.003 end,function()return time end)end
  assert(completed==32 and remaining==0)
 end)
 test("One slow atomic step cannot trigger a 32-step catch-up batch",function()
  local time=0;local c={StepSeconds=.25,MaxCatchupSteps=32,SimulationFrameBudgetMs=8}
  local remaining,steps,limited=Scheduler.Advance(8,c,function()time+=.65 end,function()return time end)
  assert(remaining==7.75 and steps==1 and limited)
 end)
 test("Unavailable exchange preserves backlog and never reports a completed step",function()
  local remaining,steps=Scheduler.Advance(.5,{StepSeconds=.25,MaxCatchupSteps=32},function()return false end,function()return 0 end)
  assert(remaining==.5 and steps==0)
 end)
 test("Partial tick and maximum catch-up limits remain intact",function()
  local c={StepSeconds=.25,MaxCatchupSteps=2,SimulationFrameBudgetMs=8};local calls=0
  local remaining,steps=Scheduler.Advance(.24,c,function()calls+=1 end,function()return 0 end)
  assert(calls==0 and steps==0 and remaining==.24)
  remaining,steps=Scheduler.Advance(.8,c,function()calls+=1 end,function()return 0 end)
  assert(steps==2 and calls==2 and math.abs(remaining-.3)<1e-9)
 end)
 return rows
end
return Tests
]====]):sub(2),Hash=([====[!0ed2886bb83d72896c0ed00cac636e46d62c993bf4b5d0f951343a6a0a19d86c]====]):sub(2),ExpectedHash=([====[!00c9ceb05ec0be9f6bb46c5a07fcde3fbd00ed0b19067f9d1f5078276b17b597]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.WorldCheckpoint]====]):sub(2) ]={Source=([====[!-- Lossless execution state, including FIFO identity and the participants' next random draw.
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local TradeStats=require(script.Parent.TradeStats)
local Http=game:GetService("HttpService")
local Encoding=game:GetService("EncodingService")
-- Version 3 introduces E-minis, retained close-only micro books and equity-only failure.
-- Version 4 adds armed stop entry orders, which wait off the order book. An older build would
-- rest them as limits, so it must fail closed on V4. V1-V3 are read unchanged.
-- Version 5 executes player orders off the order book against a saved house counterparty account. An older
-- build would rest player limits in the book again and liquidate the house as a bot, so it fails closed on V5.
-- V5 originally moved V1-V4 player limits off-book; V9 now cancels pre-V9 player limits on migration.
-- V6 permanently separates tier access, account instances and Shop receipts. Older writers must
-- refuse it, otherwise they could reset permanent entitlements or spend the wallet twice.
-- V7 renames ES/NQ to BX/BT, keeps RTY/YM only as retired close-only books and adds BG. Older builds
-- cannot map those markets, so they must refuse V7. V1-V6 saves migrate on restore (see plan and rename).
-- V8 adds the single-account profile. Older writers must fail closed.
-- V9 makes player limits executable book liquidity and persists amendment priority.
-- Pre-V9 pending player limits are cancelled during migration rather than retroactively matched.
-- V10 adds permanent reward grants, player resets and disconnect accounting. Older writers
-- must fail closed so they cannot discard an acknowledged summary or reset a granted bonus.
-- V11 adds scalpers with their own entry/exit state. Older writers must not resume them as generic traders.
-- V12 persists queued market/limit execution and aggregate budgets. Older matching engines must fail closed.
-- V13 adds position-linked working targets and keeps stops on partially closed positions.
-- Older engines must not resume these orders with the old OCO and entry-budget rules.
-- V14 persists pending resets that must liquidate before granting a new account.
-- Older builds must not discard this exposure or allow trading during liquidation.
-- V15 records bot capital adjustments, exact populations and retiring obligations. Older writers fail closed.
-- V16 applies one execution collar to all participants and persists request deduplication.
-- Older writers must not restore a market and resume asymmetric executions.
local Checkpoint={Version=16,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,[13]=true,[14]=true,[15]=true,[16]=true}}
local function digest(raw)
 local bytes=Encoding:ComputeStringHash(raw,Enum.HashAlgorithm.Sha256)
 return (bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))
end
local function clone(value)
 if type(value)~="table"then return value end
 local result={} for key,v in pairs(value)do result[key]=clone(v)end return result
end
-- Maps each saved market to its current symbol (config.Renamed) and checks its economics: every saved market
-- must still exist as a current or retired (close-only) contract with the same tick and multiplier. The
-- restored order is every current market, then the retired markets the save held. A current market the
-- save lacks opens as a new book after restore (`added`).
local function plan(saved,current)
 assert(saved.StepSeconds==current.StepSeconds,"Saved market step size differs from configuration")
 local renamed,held,map=current.Renamed or {},{},{}
 for _,key in ipairs(saved.ContractOrder)do
  local name=renamed[key] or key
  local a,b=saved.Contracts[key],current.Contracts[name] or current.LegacyContracts[name]
  assert(a and b and not held[name] and a.Tick==b.Tick and a.Multiplier==b.Multiplier,"Saved contract specification changed: "..key)
  held[name]=true map[key]=name
 end
 local order,added={},{}
 for _,key in ipairs(current.ContractOrder)do table.insert(order,key) if not held[key] then added[key]=true end end
 for _,key in ipairs(current.LegacyOrder)do if held[key] and not current.Contracts[key] then table.insert(order,key) end end
 assert(#saved.Timeframes==#current.Timeframes,"Saved timeframes differ")
 for i,tf in ipairs(current.Timeframes)do assert(saved.Timeframes[i][1]==tf[1]and saved.Timeframes[i][2]==tf[2],"Saved timeframe changed")end
 return map,order,added
end
-- Moves renamed markets in saved state: table keys and the fields that name a market (Contract, Key) take the
-- current symbol. Saved ids stay opaque and unchanged (for example participant accounts "bot:ES:Maker:1").
local function rename(value,map,field)
 if type(value)=="string"then return (field=="Contract"or field=="Key")and map[value]or value end
 if type(value)~="table"then return value end
 local result={}
 for key,v in pairs(value)do result[type(key)=="string"and map[key]or key]=rename(v,map,key)end
 return result
end
local function capture(engine,population,borrow)
 local function take(value)return borrow and value or clone(value)end
 local e={Accounts={},Books={},Orders={},Profiles=take(engine.Profiles or {})}
 for _,key in ipairs({"Seed","Time","Step","NextOrder","NextPriority","NextTrade","TotalVolume","TradeHash","PendingStops","Execution","EligibilityRevision","RequestJournal","ExecutionDiagnostics","CloseNotificationErrors","LastCloseNotificationError"})do e[key]=take(engine[key])end
 for _,id in ipairs(engine.AccountOrder)do
  local a=borrow and table.clone(engine.Accounts[id])or clone(engine.Accounts[id]);a.OpenOrders=nil
  -- Bot histories are display-only; balances, cash ledger and inventory are retained exactly.
  if not a.Player then a.History={} a.Fills={}end
  table.insert(e.Accounts,a)
 end
 for _,key in ipairs(engine.Config.ContractOrder)do
  local book={}
  for field,value in pairs(engine.Books[key])do if field~="Bids"and field~="Asks"and field~="Spec"then book[field]=take(value)end end
  e.Books[key]=book
 end
 local ids={}for id in pairs(engine.Orders)do table.insert(ids,id)end table.sort(ids)
 for _,id in ipairs(ids)do table.insert(e.Orders,take(engine.Orders[id]))end
 local p={RandomState=population.Random.State}
 for key,value in pairs(population)do if key~="Engine"and key~="Config"and key~="Random"then p[key]=take(value)end end
 return {Version=Checkpoint.Version,Config=take(engine.Config),Engine=e,Population=p}
end
function Checkpoint.Capture(engine,population)
 return capture(engine,population,false) -- Independently mutable fixture/checkpoint copy.
end
function Checkpoint.Restore(snapshot,currentConfig)
 assert(type(snapshot)=="table"and Checkpoint.Readable[snapshot.Version],"Unsupported saved market format")
 local map,order,added=plan(snapshot.Config,currentConfig)
 for old,name in pairs(map)do if old~=name then snapshot=rename(snapshot,map) break end end
 -- Preserve saved behavior except explicit, versioned migrations; presentation cadence may change.
 local config=clone(snapshot.Config)
 local savedPolicy=snapshot.Population.PolicyVersion or 0
 if savedPolicy>0 then
  assert(config.BotPopulation and config.BotPopulation.Version==savedPolicy,"Inconsistent saved bot policy")
  if currentConfig.BotPopulation and savedPolicy==currentConfig.BotPopulation.Version then
   for _,kind in ipairs(currentConfig.BotPopulation.Order)do
    assert(config.BotPopulation.Counts[kind]==currentConfig.BotPopulation.Counts[kind]
     and config.BotPopulation.Capital[kind]==currentConfig.BotPopulation.Capital[kind],"Bot allocation changes require a policy version bump")
   end
  end
 end
 local upgradeBots=(snapshot.Population.PolicyVersion or 0)<(currentConfig.BotPopulation and currentConfig.BotPopulation.Version or 0)
 assert((snapshot.Population.PolicyVersion or 0)<=(currentConfig.BotPopulation and currentConfig.BotPopulation.Version or 0),"Cannot downgrade bot population policy")
 if upgradeBots then
  for _,key in ipairs({"BotPopulation","MakersPerInstrument","ParticipantsPerInstrument","WhalesPerInstrument","ScalpersPerInstrument","Scalper","Reserve"})do config[key]=clone(currentConfig[key])end
 end
 local upgradeReserves=(config.ReservePopulationVersion or 0)<(currentConfig.ReservePopulationVersion or 0)
 if upgradeReserves then config.Reserve=clone(currentConfig.Reserve);config.ReservePopulationVersion=currentConfig.ReservePopulationVersion end
 config.PlayerExecution=clone(currentConfig.PlayerExecution)
 config.BotExitRetrySeconds=currentConfig.BotExitRetrySeconds
 config.SimulationFrameBudgetMs=currentConfig.SimulationFrameBudgetMs
 local upgradeScalpers=(config.ScalperPopulationVersion or 0)<(currentConfig.ScalperPopulationVersion or 0)
 if upgradeScalpers then
  config.ScalpersPerInstrument=currentConfig.ScalpersPerInstrument
  config.ScalperPopulationVersion=currentConfig.ScalperPopulationVersion
  config.Scalper=clone(currentConfig.Scalper)
 end
 local upgradeMakers=(config.MakerPopulationVersion or 0)<(currentConfig.MakerPopulationVersion or 0)
 if upgradeMakers then
  config.MakersPerInstrument=currentConfig.MakersPerInstrument
  config.MakerPopulationVersion=currentConfig.MakerPopulationVersion
 end
 config.DailyLossLimit=nil
 for _,key in ipairs({"LegacyOrder","LegacyContracts","LegacyToCurrent","Renamed"})do config[key]=clone(currentConfig[key])end
 config.ContractOrder=order
 local retiring={}
 for _,key in ipairs(order)do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  local spec=config.Contracts[key]
  if added[key] then
   spec=clone(current) config.Contracts[key]=spec
   -- A new book starts near the saved market it succeeds, without relabelling historical executions or volume.
   for old,successor in pairs(currentConfig.LegacyToCurrent)do
    local b=successor==key and snapshot.Engine.Books[old]
    if b then spec.Last=(b.Last or b.Reference)*config.Contracts[old].Tick end
   end
  else
   -- Saved economics stay exact (checked in plan); names and the close-only rule follow this build.
   if current.CloseOnly and not spec.CloseOnly then retiring[key]=true end
   spec.Name=current.Name spec.Short=current.Short spec.CloseOnly=current.CloseOnly
  end
 end
 -- MaxCandles only bounds chart history (matching never reads candles), so a restored world adopts the current limit.
 for _,key in ipairs({"BroadcastSeconds","SimulationSpeed","MaxCatchupSteps","MaxCandles","MaxPlayerQuantity","MaxPlayerInventory","MaxPlayerOrders","DepthLevels","MakerQuotePolicyVersion","MakerMinRestSeconds","MakerRepriceTicks","MakerQuoteSizeMultiplier","MakerReplenishSeconds","MakerDecisionMultiplier"})do config[key]=currentConfig[key]end
 -- Simulated margin is buying-power policy; contract economics and all saved ledgers stay intact.
 for key,spec in pairs(config.Contracts) do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  if current then spec.Margin=current.Margin end
 end
 local data=snapshot.Engine local engine=Engine.new(config,data.Seed)
 for _,key in ipairs({"Time","Step","NextOrder","NextTrade","TotalVolume","TradeHash","PendingStops","Execution","EligibilityRevision","RequestJournal","ExecutionDiagnostics","CloseNotificationErrors","LastCloseNotificationError"})do engine[key]=clone(data[key])end
 engine.NextPriority=data.NextPriority or data.NextOrder
 for _,a in ipairs(data.Accounts)do
  local account=clone(a);account.OpenOrders={}
  account.LossLimit=account.Base
  assert(not engine.Accounts[a.Id],"Duplicate saved account")
  engine.Accounts[a.Id]=account table.insert(engine.AccountOrder,a.Id)
 end
 for key,fields in pairs(data.Books)do for name,value in pairs(fields)do engine.Books[key][name]=clone(value)end end
 engine.Profiles=clone(data.Profiles or {})
 for uid,profile in pairs(engine.Profiles)do
  assert(type(uid)=="string"and type(profile)=="table"and type(profile.Tiers)=="table"and type(profile.Ledger)=="table","Invalid saved funded profile")
  for _,id in ipairs(profile.Ledger)do assert(engine.Accounts[id],"Saved funded account missing")end
 end
 local prior=0
 for _,order in ipairs(data.Orders)do
  local o=clone(order)
  -- Preserve execution behavior for orders placed before the explicit choice existed.
  o.Execution=o.Execution or "Sliced"
  assert(o.Id>prior and o.Remaining>0 and engine.Accounts[o.Owner]and engine.Books[o.Contract],"Invalid saved resting order")
  prior=o.Id engine.Orders[o.Id]=o engine.Accounts[o.Owner].OpenOrders[o.Id]=true
  o.Priority=o.Priority or o.Id
  engine.NextPriority=math.max(engine.NextPriority,o.Priority)
  if o.Type=="Limit"and not o.Queued and not(engine.Accounts[o.Owner].Player and snapshot.Version<9)then engine:_rest(engine.Books[o.Contract],o)end
 end
 local population=setmetatable({Engine=engine,Config=config},Participants)
 -- Rebuilding FIFO is not a liquidity change. Keep saved retry deadlines valid;
 -- subsequent migrations/protection repairs still invalidate affected books.
 for key,fields in pairs(data.Books)do engine.Books[key].ExitLiquidityRevision=fields.ExitLiquidityRevision end
 for key,value in pairs(snapshot.Population)do if key~="RandomState"then population[key]=clone(value)end end
 population.Random=Participants.RNG.new(1);population.Random.State=snapshot.Population.RandomState
 assert(type(population.Random.State)=="number"and population.Random.State>0 and population.Random.State<2147483647,"Invalid saved random state")
 for _,agent in ipairs(population.Agents)do assert(engine.Accounts[agent.Id],"Saved participant account missing")end
 if snapshot.Version<3 then
  local currentAccounts={}
  for _,profile in pairs(engine.Profiles) do for _,entry in pairs(profile.Tiers) do if entry.Account then currentAccounts[entry.Account]=true end end end
  for _,profile in pairs(engine.Profiles) do for _,id in ipairs(profile.Ledger) do if not currentAccounts[id] then engine.Accounts[id].Retired=true end end end
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player and not a.Retired and engine:Summary(a).Equity>0 then
    a.Locked=false a.Liquidating=nil
    for _,p in pairs(a.Positions) do if p.Triggered=="Risk liquidation" then p.Triggered=nil end end
   end
   if a.Player then
    for orderId in pairs(clone(a.OpenOrders)) do
     local o=engine.Orders[orderId]
     if config.Contracts[o.Contract].CloseOnly and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 -- A market that became close-only keeps its positions, SL/TP and closing orders. Its entry orders could only
 -- open new exposure there, so they are cancelled (the order history records it).
 if next(retiring) then
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player then
    local ids={} for orderId in pairs(a.OpenOrders) do table.insert(ids,orderId) end table.sort(ids)
    for _,orderId in ipairs(ids) do
     local o=engine.Orders[orderId]
     if o and retiring[o.Contract] and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 for _,key in ipairs(order) do if added[key] then population:AddMarket(key) end end
 if not upgradeBots then
  if upgradeMakers then population:EnsureMakers(currentConfig.ContractOrder,config.MakersPerInstrument) end
  if upgradeScalpers then population:EnsureScalpers(currentConfig.ContractOrder,config.ScalpersPerInstrument) end
  if upgradeReserves then population:EnsureReserves(currentConfig.ContractOrder);population:RefreshReservePolicy()end
 end
 -- Lifetime trading stats (no format change): rebuilt once from saved history for older accounts,
 -- reconciled against the ledger for all others. Idempotent across repeated restores.
 local now=os.time()
 -- Older settlement added every fill separately to large balances, accumulating sub-cent
 -- floating-point drift. Rebuild only tiny discrepancies from the existing capital/P&L ledger;
 -- larger differences still fail Audit. New settlement derives Balance from that ledger.
 for _,id in ipairs(engine.AccountOrder)do local a=engine.Accounts[id]
  local gap=a.Balance-a.Base-a.Realized
  if a.Base>=1e9 and math.abs(gap)<.005 then a.Balance=a.Base+a.Realized end
 end
 require(script.Parent.BotPopulation).Apply(population)
 for _,id in ipairs(engine.AccountOrder) do local a=engine.Accounts[id] if a.Player then TradeStats.Reconcile(engine,a,now) end end
 -- Required migration, not optional leaderboard work: any failure aborts restore before saving.
 require(script.Parent.FundedAccounts).new(engine,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),currentConfig)
 -- Archive legacy profile evidence first; then cancel remaining off-book limits without a trade.
 if snapshot.Version<9 then
  local pending={};for id,o in pairs(engine.Orders)do if o.Type=="Limit"and engine.Accounts[o.Owner].Player then table.insert(pending,id)end end
  table.sort(pending);for _,id in ipairs(pending)do local o=engine.Orders[id];engine:Cancel(o.Owner,id)end
 end
 -- Rebuild missing targets/adopt legacy closing limits without executing trades during restore.
 local Protective=require(script.Parent.ProtectiveOrders)
 for _,id in ipairs(engine.AccountOrder)do local a=engine.Accounts[id]
  if a.Player then for key in pairs(a.Positions)do Protective.Mark(engine,a,key)end end
 end
 Protective.Sync(engine,true)
 engine:Audit()
 return engine,population
end
-- The reader's decompressed-size bound. It is unchanged, so every checkpoint that opened before still opens.
-- Encode refuses anything larger before compressing, so the writer and the reader enforce one bound: every
-- checkpoint the writer accepts decodes, and every save that decodes today can be written again.
Checkpoint.MaxDecodedBytes=32000000
-- The reader's header rules, shared by Encode (before a commit) and Decode (on restore).
function Checkpoint.Check(record,maxDecodedBytes)
 assert(type(record)=="table" and Checkpoint.Readable[record.Version] and record.Codec=="zstd-base64" and type(record.Payload)=="string","Invalid checkpoint encoding")
 local compressed=Encoding:Base64Decode(buffer.fromstring(record.Payload))
 local bytes=Encoding:GetDecompressedBufferSize(compressed,Enum.CompressionAlgorithm.Zstd)
 assert(bytes and bytes==record.RawBytes and bytes<=math.min(maxDecodedBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes),"Invalid checkpoint length")
 return compressed,bytes
end
function Checkpoint.Encode(snapshot,maxRawBytes)
 local raw=Http:JSONEncode(snapshot)
 local limit=math.min(maxRawBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes)
 if #raw>limit then error(string.format("Exchange checkpoint is too large (%d raw bytes, limit %d); trading paused to protect saved state",#raw,limit),2) end
 local compressed=Encoding:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd,3)
 local record={Version=Checkpoint.Version,Codec="zstd-base64",RawBytes=#raw,
  Digest=digest(raw),
  Payload=buffer.tostring(Encoding:Base64Encode(compressed))}
 Checkpoint.Check(record,limit)
 return record
end
function Checkpoint.Decode(record,maxDecodedBytes)
 local compressed=Checkpoint.Check(record,maxDecodedBytes)
 local raw=buffer.tostring(Encoding:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))
 assert(digest(raw)==record.Digest,"Checkpoint checksum failed")
 return Http:JSONDecode(raw)
end
function Checkpoint.EncodeWorld(engine,population,maxRawBytes)
 -- No borrowed table escapes this non-yielding call. EncodingService and JSON
 -- encoding are synchronous; the engine cannot advance between capture and
 -- serialization. Public Capture remains a deep copy for asynchronous consumers.
 return Checkpoint.Encode(capture(engine,population,true),maxRawBytes)
end
return Checkpoint
]====]):sub(2),Hash=([====[!3b8e1ab2c532853a8ed6606ff58280bf0da5d2d6993ffa116c62d02c569028db]====]):sub(2),ExpectedHash=([====[!ccbb113d25edd1fb2572cb0a0cfa1907779cce38503280292cd77e3619c9e5d9]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.WorldService]====]):sub(2) ]={Source=([====[!-- A single shared exchange. Follower servers route players to its owner instead of creating another tape.
local RunService=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Lease=require(script.Parent.WorldLease)
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Settings=require(script.Parent.WorldConfig)
local World={} World.__index=World
function World.new(config,options)
 options=options or {}
 local studio=options.Studio if studio==nil then studio=RunService:IsStudio()end
 local self=setmetatable({Config=config,Settings=options.Settings or Settings,Studio=studio,
  PlaceId=options.PlaceId or game.PlaceId,JobId=options.JobId or game.JobId,Now=options.Now or os.time,
  Mode="Connecting",Status="Connecting to the shared exchange",Busy=false,Closing=false,
  Healthy=false,NextSave=0,NextAttempt=0,Epoch=0,Store=options.Store},World)
 self.Identity={Token=Http:GenerateGUID(false),WorldId=Http:GenerateGUID(false),JobId=self.JobId,PlaceId=self.PlaceId}
 -- Private servers cannot be public teleport destinations. They only act as entry lobbies.
 self.CanOwn=options.CanOwn if self.CanOwn==nil then self.CanOwn=studio or game.PrivateServerId==""end
 return self
end
function World:_fresh()
 local seed=self.Studio and self.Settings.StudioReplaySeed or 0
 seed=seed or 0
 if seed==0 then seed=tonumber(Http:GenerateGUID(false):sub(1,8),16)%2147483646+1 end
 local engine=Engine.new(self.Config,seed) local population=Participants.new(engine)
 for i=1,math.floor(self.Config.WarmupSeconds/self.Config.StepSeconds)do
  population:Step() if i%200==0 then task.wait()end
 end
 return engine,population
end
function World:_encode(engine,population)
 engine=engine or self.Engine;population=population or self.Population
 local projection
 if self.CaptureProjection then
  -- Optional read model failures must never prevent an exchange save or trading.
  local ok,result=pcall(self.CaptureProjection,engine)
  if ok then projection=result else warn("[Get Funded!] Leaderboard projection unavailable: "..tostring(result)) end
 end
 -- Raw size is refused by Encode (before compression) with exactly the bound the reader enforces.
 local record=Checkpoint.EncodeWorld(engine,population,Checkpoint.MaxDecodedBytes)
 -- Measure the complete value UpdateAsync will store: lease fields plus this checkpoint, with headroom.
 local stored=self:_storedBytes(record,engine.Step)
 assert(stored+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Exchange checkpoint is too large; trading paused to protect saved state")
 self.LastRawBytes=record.RawBytes self.LastStoredBytes=stored
 return record,engine.Step,projection
end
function World:_storedBytes(record,step)
 local lease=self.Lease and self.Lease.Record
 local shell=lease and table.clone(lease) or {Version=1,WorldId=self.Identity.WorldId,Generation=1,SaveSequence=0}
 local now=self.Now()
 shell.Owner=self.Identity.Token shell.JobId=self.Identity.JobId shell.PlaceId=self.Identity.PlaceId
 shell.Checkpoint=record shell.SavedStep=step or self.Engine.Step shell.SavedAt=now
 shell.SaveSequence=(shell.SaveSequence or 0)+1 shell.LeaseUntil=now+self.Settings.LeaseSeconds
 return #Http:JSONEncode(shell)
end
-- False once the last saved checkpoint used the configured fraction of either size limit. Only new accounts
-- wait; trading and saving continue, and the unused room absorbs growth of the accounts that already exist.
-- kind "Start"/"Activate" (a first account or an earned tier) may use the band up to NewAccountCapacityFraction.
function World:HasCapacity(kind)
 local fraction=self.Settings.CapacityFraction or 0.8
 if kind=="Start" then fraction=math.max(fraction,self.Settings.NewAccountCapacityFraction or fraction) end
 if (self.LastRawBytes or 0)>=Checkpoint.MaxDecodedBytes*fraction then return false end
 if (self.LastStoredBytes or 0)>=self.Settings.MaxEncodedBytes*fraction then return false end
 return true
end
function World:_committed(rows)
 if not rows then return end
 local r=self.Lease.Record
 self.DurableProjection={Rows=rows,WorldId=r.WorldId,Sequence=r.SaveSequence,SavedAt=r.SavedAt}
end
function World:_sandbox(reason)
 self.Engine,self.Population=self:_fresh()
 self.Mode="Local" self.Status="LOCAL · NOT SAVED" self.Healthy=true self.Epoch+=1
 warn("[Get Funded!] Unsaved Studio sandbox: "..reason.." Publish a test experience and enable Studio API access for restart continuity.")
end
function World:Open()
 if self.Closing or self.Busy then return end
 self.Busy=true
 local ok,err=pcall(function()
  if not self.Settings.Enabled or self.PlaceId==0 then
   assert(self.Studio and self.Settings.AllowUnsavedStudio,"Persistent storage is required for the live exchange")
   self:_sandbox(self.PlaceId==0 and "This place is unpublished." or "Persistence is disabled.") return
  end
  if not self.Store then
   self.Store=game:GetService("DataStoreService"):GetDataStore(self.Settings.StoreName,self.Studio and "Studio" or "Live")
  end
  self.Lease=self.Lease or Lease.new(self.Store,self.Settings,self.Identity,self.Now)
  local owned,record
  if self.CanOwn then owned,record=self.Lease:Claim()
  else owned=false record=self.Store:GetAsync(self.Settings.WorldKey)end
  if not owned then
   self.Owner=record self.Mode="Following" self.Healthy=false
   self.Status=self.Studio and "Shared Studio exchange is active in another test; stop it before restarting here" or "Joining the shared exchange"
   return
  end
  self.Mode="Loading" self.Status="Restoring the saved exchange"
  -- Everything restored from the store is durable; no in-memory receipt or transaction from a previous engine survives.
  if record.Checkpoint then
   self.Engine,self.Population=Checkpoint.Restore(Checkpoint.Decode(record.Checkpoint),self.Config)
   assert(self.Engine.Step==record.SavedStep,"Checkpoint step does not match ownership record")
  else
   assert(record.SavedStep==0,"Saved exchange checkpoint is missing")
   self.Engine,self.Population=self:_fresh()
  end
  -- No client trades until the initial/loaded state has a confirmed durable checkpoint.
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,false)
  self:_committed(projection)
  self.Mode="Shared" self.Status="SHARED · SAVED" self.Healthy=true self.Epoch+=1
  self.NextSave=self.Now()+self.Settings.SaveSeconds
 end)
 self.Busy=false self.NextAttempt=self.Now()+self.Settings.RetrySeconds
 if not ok then
  -- Transient storage failures or corrupt checkpoints must never silently reset an existing market.
  self.Healthy=false self.Mode="Unavailable" self.Status="Saved exchange unavailable · retrying safely"
  self.LastError=tostring(err) warn("[Get Funded!] "..self.LastError)
 end
end
function World:CanRun()
 if self.Closing or self.Transaction or not self.Healthy or not self.Engine then return false end
 return self.Mode=="Local" or (self.Mode=="Shared" and self.Lease:Valid())
end
function World:Label()
 if self.Mode=="Shared" and not self:CanRun()then return "PAUSED · WAITING FOR SAVED EXCHANGE"end
 return self.Status
end
function World:Save(release)
 if self.Busy or not self.Engine or self.Mode~="Shared" then return false end
 self.Busy=true
 local ok,err=pcall(function()
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,release)
  self:_committed(projection)
 end)
 self.Busy=false self.NextSave=self.Now()+(ok and self.Settings.SaveSeconds or self.Settings.RetrySeconds)
 self.Healthy=ok and not release
 if not ok then self.LastError=tostring(err) warn("[Get Funded!] Save failed; exchange paused: "..self.LastError)end
 return ok
end
-- Freeze execution, transform a detached copy, then swap only after the fenced save confirms it.
-- A timed-out write may have committed: reload durable storage instead of overwriting it with old data.
function World:TransformSaved(transform)
 if self.Busy or self.Mode~="Shared" or not self:CanRun()then return false,"Exchange is not ready."end
 self.Busy=true;self.Transaction=true
 local rawBytes,storedBytes=self.LastRawBytes,self.LastStoredBytes
 local attemptedCommit=false local result
 local ok,err=pcall(function()
  local engine,population=Checkpoint.Restore(Checkpoint.Capture(self.Engine,self.Population),self.Config)
  result=transform(engine,population);engine:Audit()
  local encoded,step,projection=self:_encode(engine,population)
  assert(not self.CaptureProjection or projection,"Cannot transform saved data without its leaderboard projection")
  attemptedCommit=true;self.Lease:Commit(encoded,step,false)
  self.Engine=engine;self.Population=population;self.Epoch+=1
  self:_committed(projection)
 end)
 self.Busy=false;self.Transaction=false
 self.NextSave=self.Now()+self.Settings.SaveSeconds
 if not ok then
  self.LastRawBytes=rawBytes;self.LastStoredBytes=storedBytes
  self.LastError=tostring(err)
  if attemptedCommit then
   self.Healthy=false;self.Mode="Unavailable";self.Status="Verifying the saved exchange"
   self.Engine=nil;self.Population=nil;self.Epoch+=1
   self.NextAttempt=self.Now()+self.Settings.RetrySeconds
  end
  warn("[Get Funded!] Saved transformation failed: "..self.LastError)
 end
 return ok,ok and result or tostring(err)
end
function World:Maintain()
 if self.Closing or self.Busy or self.Mode=="Local"then return end
 local now=self.Now()
 if self.Mode=="Shared"then
  if not self.Lease.Owned or now>=self.Lease.Record.LeaseUntil then
   -- Discard unsaved state after loss of authority. Reacquire and restore the durable record.
   self.Healthy=false self.Mode="Unavailable" self.Status="Reconnecting to the saved exchange"
   self.Engine=nil self.Population=nil self.Epoch+=1 self.NextAttempt=now
  elseif now>=self.NextSave then self:Save(false) return end
 end
 if self.Mode~="Shared" and now>=self.NextAttempt then self:Open()end
end
function World:Close()
 self.Closing=true
 -- A save already in flight finishes before the final frozen checkpoint and lease release.
 local deadline=os.clock()+24
 while self.Busy and os.clock()<deadline do task.wait(0.05)end
 if not self.Busy and self.Mode=="Shared" and self.Lease.Owned then
  repeat
   if self:Save(true)then return true end
   if not self.Lease.Owned or self.Now()>=self.Lease.Record.LeaseUntil then break end
   task.wait(1)
  until os.clock()>=deadline
 end
 return self.Mode=="Local"
end
return World
]====]):sub(2),Hash=([====[!665bb3ab92a3db33a85176ef0a157f6298d1e893d5c9b318cbe159e2342fc649]====]):sub(2),ExpectedHash=([====[!09c72f726f4e4038ad422b0dcf966d0da79f687a5aba571cfcc8819c1bdc6700]====]):sub(2),ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.ExecutionIntegrityTests]====]):sub(2) ]={Source=([====[!-- Contract tests: isolated accounts, real two-sided settlement, no live state/services.
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function fresh()
 local c=copy(C);c.BotPopulation=nil;c.Contracts.BX.Last=5230.25
 local e=E.new(c,10315)
 for _,id in ipairs({'player','player2','maker','buyer','other'})do
  local a=e:AddAccount(id,1000000000,1000000,.8,id:sub(1,6)=='player');a.LiquidityProvider=true
 end
 return e,c
end
local function order(e,owner,side,quantity,price,extra)
 local request={Contract='BX',Direction=side,Quantity=quantity,Type=price and 'Limit'or 'Market',Price=price}
 for k,v in pairs(extra or {})do request[k]=v end
 local ok,result=e:Submit(owner,request);assert(ok,tostring(result));return result
end
local function position(quantity)
 local e,c=fresh();local policy=c.PlayerExecution;c.PlayerExecution=nil
 order(e,'maker',-1,quantity,5230.25)
 order(e,'player',1,quantity,nil,{TargetTicks=18,StopTicks=20})
 c.PlayerExecution=policy
 return e,c,e.Accounts.player.Positions.BX
end
local function pop(e,c)return setmetatable({Engine=e,Config=c,Random=P.RNG.new(10315),Agents={}},P)end
function Tests.Run(yieldBetween)
 local rows={};local function test(name,fn)if yieldBetween then yieldBetween()end;local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Captured BX TP: 7946 at 5234.75 cannot be bypassed by bot ask 5235.25 at fair 5181.50',function()
  local e,_,p=position(7946);local target=e.Orders[p.TargetOrder];local priority=target.Priority
  e.Books.BX.FairReference=5181.5/.25;e.Time=2177372.75;e.Step=8709491
  local worse=order(e,'other',-1,2,5235.25);local n=e.NextTrade
  local result=order(e,'buyer',1,91)
  assert(result.Filled==0 and e.NextTrade==n,'Out-of-band bot trade bypassed the TP')
  assert(target.Remaining==7946 and target.Filled==0 and target.BlockedReason=='Waiting · price safeguard')
  assert(target.StatusHistory[#target.StatusHistory].Reason==target.BlockedReason)
  local status=e:Snapshot('player','BX','1m',false).Orders[2]
  assert(status and status.Status:find('price safeguard',1,true),'TP must explain its blocking reason')
  e.Books.BX.FairReference=5234.75/.25
  local filled=order(e,'buyer',1,2)
  assert(filled.Filled==2 and filled.Average==5234.75 and p.Quantity==7944)
  assert(target.Priority==priority and target.Remaining==7944 and e.Orders[worse.Id].Remaining==2)
  e:Audit()
 end)
 test('Player and bot resting liquidity use identical collars for buy and sell aggressors',function()
  for _,side in ipairs({1,-1})do for _,owner in ipairs({'player','maker'})do
   local e=fresh();local price=5230.25+side*8
   order(e,owner,-side,3,price);order(e,'other',-side,3,price+side*.25)
   e.Books.BX.FairReference=5230.25/.25
   local r=order(e,'buyer',side,6)
   assert(r.Filled==0 and e.NextTrade==0,'Participant type changed execution eligibility');e:Audit()
  end end
 end)
 test('Rejected aggressive limits record a bounded reason for players and bots',function()
  local e=fresh();e.Books.BX.FairReference=5230.25/.25
  for i=1,80 do
   local ok=e:Submit(i%2==0 and 'player'or 'maker',{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=5240})
   assert(not ok)
  end
  assert(e.NextOrder==0 and e.ExecutionDiagnostics.RejectedCount==80 and #e.ExecutionDiagnostics.RecentRejections==64)
  assert(e.ExecutionDiagnostics.RecentRejections[64].Reason:find('No order placed',1,true));e:Audit()
 end)
 test('Best eligible price then FIFO, independent of participant type, with partial chunks',function()
  for _,first in ipairs({'player','maker'})do
   local e=fresh();local second=first=='player'and 'maker'or 'player'
   local a=order(e,first,-1,3,5231);local b=order(e,second,-1,4,5231);local worse=order(e,'other',-1,5,5231.25)
   local r=order(e,'buyer',1,5)
   assert(r.Filled==5 and r.Average==5231 and not e.Orders[a.Id]and e.Orders[b.Id].Remaining==2)
   assert(e.Orders[worse.Id].Remaining==5 and e.Trades[1].Quantity==3 and e.Trades[2].Quantity==2)
   e:Audit()
  end
 end)
 test('Amendment no-op retains FIFO; reprice loses priority; cancellation removes exactly one order',function()
  local e=fresh();local a=order(e,'player',-1,3,5231);local b=order(e,'player2',-1,3,5231)
  local priority=e.Orders[a.Id].Priority
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231}))
  assert(e.Orders[a.Id].Priority==priority)
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231.25}))
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231.25,ExpectedQuantity=3,Price=5231}))
  order(e,'buyer',1,3);assert(not e.Orders[b.Id]and e.Orders[a.Id].Remaining==3)
  assert(e:Cancel('player',a.Id));assert(not e:Cancel('player',a.Id));assert(#e.Books.BX.Asks==0);e:Audit()
 end)
 test('TP/SL race cancels residual target and cannot reverse after a partial target fill',function()
  local e,_,p=position(8000);local target=p.TargetOrder
  order(e,'buyer',1,3000,5234.75);assert(p.Quantity==5000 and e.Orders[target].Remaining==5000)
  order(e,'other',1,6000,5225.25)
  order(e,'maker',-1,1);e:ProcessStops();e:ProcessPlayerOrders()
  assert(not e.Accounts.player.Positions.BX and not e.Orders[target])
  for id in pairs(e.Accounts.player.OpenOrders)do assert(not e.Orders[id].Protection,'Orphan protective order')end
  e:Audit()
 end)
 test('Quantity reduction retains FIFO; increase loses FIFO and reserves new capacity',function()
  local e=fresh();local a=order(e,'player',-1,5,5231);local b=order(e,'player2',-1,5,5231)
  local priority=e.Orders[a.Id].Priority
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=5,Price=5231,Quantity=3}))
  assert(e.Orders[a.Id].Priority==priority and e.Orders[a.Id].Remaining==3)
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231,Quantity=6}))
  assert(e.Orders[a.Id].Priority>e.Orders[b.Id].Priority)
  order(e,'buyer',1,6);assert(not e.Orders[b.Id]and e.Orders[a.Id].Remaining==5);e:Audit()
 end)
 test('Bot margin eligibility is rechecked before a resting quote can execute',function()
  local e=fresh();local q=order(e,'maker',-1,10,5231)
  e.Accounts.maker.Balance=1;e.Accounts.maker.Realized=1-e.Accounts.maker.Base
  local r=order(e,'buyer',1,10)
  assert(r.Filled==0 and not e.Orders[q.Id])
  local archived=e.OrderArchive[#e.OrderArchive-1]
  assert(archived.BlockedReason=='Insufficient margin or inventory capacity')
 end)
 test('Snapshot filters ineligible liquidity without retiring or reprioritizing an order',function()
  local e=fresh();local r=order(e,'player',-1,10,5231);local o=e.Orders[r.Id];local priority=o.Priority
  e.Accounts.player.Balance=1000;e.Accounts.player.Realized=1000-e.Accounts.player.Base
  local n=e.NextOrder;local snapshot=e:Snapshot('player2','BX','1m',false)
  assert(#snapshot.Quotes.BX.Depth.Asks==0 and e.Orders[r.Id]==o and o.Priority==priority and e.NextOrder==n)
 end)
 for _,quantity in ipairs({8000,13000,50000})do
  test(quantity..'-contract TP uses matched chunks, tracks residual and never reverses',function()
   local e,_,p=position(quantity);local child=e.Orders[p.TargetOrder];local n=e.NextTrade
   order(e,'buyer',1,quantity-1,5234.75)
   assert(p.Quantity==1 and child.Remaining==1 and e.NextTrade==n+1,'Quantity was split per contract')
   order(e,'other',1,2,5234.75)
   assert(not e.Accounts.player.Positions.BX and not e.Orders[child.Id]and e.NextTrade==n+2)
   assert(e.Accounts.other.Positions.BX.Quantity==1);e:Audit()
  end)
 end
 test('Sparse liquidity preserves an active target and later arrival gets only available quantity',function()
  local e,_,p=position(13000);local id=p.TargetOrder;local priority=e.Orders[id].Priority
  for _=1,10 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(p.Quantity==13000 and e.Orders[id].Priority==priority)
  order(e,'buyer',1,7,5234.75);assert(p.Quantity==12993 and e.Orders[id].Remaining==12993);e:Audit()
 end)
 test('Checkpoint preserves blocked TP priority and exact continuation, independent of snapshot reads',function()
  local e,c,p=position(13000);e.Books.BX.FairReference=5181.5/.25
  order(e,'buyer',1,1);local id=p.TargetOrder
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop(e,c)))),c)
  assert(restored.Orders[id].Priority==e.Orders[id].Priority and restored.Orders[id].Remaining==13000)
  for _,engine in ipairs({e,restored})do engine.Books.BX.FairReference=5234.75/.25 end
  for i=1,8 do
   e:Snapshot('player','BX','1m',false)
   for _,engine in ipairs({e,restored})do engine:AdvanceClock(.25);order(engine,'buyer',1,i,5234.75)end
  end
  assert(e.TradeHash==restored.TradeHash and e.NextOrder==restored.NextOrder)
  assert(e.Accounts.player.Positions.BX.Quantity==restored.Accounts.player.Positions.BX.Quantity)
  e:Audit();restored:Audit()
 end)
 test('Self-trade prevention cancels own older quote and never creates a fill',function()
  local e=fresh();local q=order(e,'player',-1,10,5231);local n=e.NextTrade
  local r=order(e,'player',1,10);assert(r.Filled==0 and e.NextTrade==n and not e.Orders[q.Id]);e:Audit()
 end)
 test('Closing notification failure cannot interrupt settlement between the two counterparties',function()
  local e,_,p=position(2)
  e.OnFundedClose=function()error('Injected presentation callback failure')end
  order(e,'buyer',1,2,5234.75)
  assert(not e.Accounts.player.Positions.BX and e.CloseNotificationErrors==1)
  assert(e.LastCloseNotificationError.TradeId==e.NextTrade and not e.Orders[p.TargetOrder]);e:Audit()
 end)
 test('Atomic save encoding matches detached capture and cannot change after later fills',function()
  local e,c,p=position(8000);local population=pop(e,c)
  local detached=CP.Capture(e,population)
  local record=CP.EncodeWorld(e,population);local saved=CP.Decode(record)
  local function equal(a,b)
   if type(a)~='table'then assert(a==b);return end
   for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil)end
  end
  equal(detached,saved)
  order(e,'buyer',1,2,5234.75)
  equal(detached,CP.Decode(record))
  assert(e.Accounts.player.Positions.BX.Quantity==7998 and p.Quantity==7998)
 end)
 return rows
end
return Tests
]====]):sub(2),Hash=([====[!7f8083569eb49238cbfb23a0711548e56e1d41f55438fd28c7e3afc83683a729]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.RequestJournal]====]):sub(2) ]={Source=([====[!-- Persisted per-player request session/high-water mark. Evicting old replies never
-- makes an old id executable again. Reconnect retires the previous session.
local Journal={MaxReplies=128}
function Journal.Open(e,uid)
 e.RequestJournal=e.RequestJournal or {}
 local old=e.RequestJournal[uid]
 local state={Session=(old and old.Session or 0)+1,High=0,Replies={},Order={}}
 e.RequestJournal[uid]=state
 return state.Session
end
function Journal.Begin(e,uid,session,id)
 local state=e.RequestJournal and e.RequestJournal[uid]
 if not state or session~=state.Session then return false,nil,'Connection changed. Refresh the account before submitting a new request.'end
 local cached=state.Replies[tostring(id)]
 if cached then return false,cached end
 if id<=state.High then return false,nil,'Request already processed. Check the authoritative account snapshot.'end
 state.High=id -- consumed before any mutation; a retry cannot repeat a partial failure
 return true
end
function Journal.Finish(e,uid,session,id,result)
 local state=e.RequestJournal and e.RequestJournal[uid]
 if not state or state.Session~=session then return end
 local key=tostring(id)
 if not state.Replies[key]then table.insert(state.Order,key)end
 state.Replies[key]=result
 if #state.Order>Journal.MaxReplies then state.Replies[table.remove(state.Order,1)]=nil end
end
function Journal.Cached(e,uid,session,id)
 local state=e and e.RequestJournal and e.RequestJournal[uid]
 return state and state.Session==session and state.Replies[tostring(id)]or nil
end
return Journal
]====]):sub(2),Hash=([====[!65c1d06ebac8c2af8512a796b2be8dc0178f6f6f0dce1255d17df274538c5bc0]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.RequestJournalTests]====]):sub(2) ]={Source=([====[!local Journal=require(script.Parent.RequestJournal)
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local CP=require(script.Parent.WorldCheckpoint)
local P=require(script.Parent.Participants)
local Queue=require(script.Parent.RequestQueue)
local Tests={}
function Tests.Run(yieldBetween)
 local rows={};local function test(name,fn)if yieldBetween then yieldBetween()end;local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Retry returns the original result and cannot create another order or fill',function()
  local e=E.new(C,15);e:AddAccount('p',1000000,1000,.8,true);e:AddAccount('maker',1000000,1000,.8,false)
  local price=C.Contracts.BX.Last
  assert(e:Submit('maker',{Contract='BX',Direction=-1,Quantity=10,Type='Limit',Price=price}))
  local session=Journal.Open(e,'uid')
  local function process(id)
   local accepted,cached=Journal.Begin(e,'uid',session,id);if not accepted then return cached end
   local ok,result=e:Submit('p',{Contract='BX',Direction=1,Quantity=2,Type='Market'})
   local reply={Ok=ok,Result=result};Journal.Finish(e,'uid',session,id,reply);return reply
  end
  local first=process(1);local count=e.NextTrade;local order=e.NextOrder
  assert(first.Ok and first.Result.Filled==2)
  for _=1,100 do assert(process(1).Result.Id==first.Result.Id)end
  assert(e.NextTrade==count and e.NextOrder==order and e.Accounts.p.Positions.BX.Quantity==2);e:Audit()
 end)
 test('Reply eviction, changed payload and reconnect cannot resurrect a consumed request',function()
  local e={};local session=Journal.Open(e,'uid')
  for id=1,1000 do assert(Journal.Begin(e,'uid',session,id));Journal.Finish(e,'uid',session,id,{Id=id})end
  local accepted,cached,reason=Journal.Begin(e,'uid',session,1)
  assert(not accepted and not cached and reason:find('already processed',1,true))
  assert(#e.RequestJournal.uid.Order==Journal.MaxReplies)
  local nextSession=Journal.Open(e,'uid');assert(nextSession==session+1)
  assert(not Journal.Begin(e,'uid',session,1001));assert(Journal.Begin(e,'uid',nextSession,1))
 end)
 test('Interleaved owners retain their own request order; consumed failures never execute twice',function()
  local e={};local a=Journal.Open(e,'a');local b=Journal.Open(e,'b');local sequence={}
  for _,row in ipairs({{'a',a,1},{'b',b,1},{'a',a,2},{'a',a,2},{'b',b,2}})do
   if Journal.Begin(e,row[1],row[2],row[3])then table.insert(sequence,row[1]..row[3])end
  end
  assert(table.concat(sequence,',')=='a1,b1,a2,b2')
  assert(not Journal.Begin(e,'a',a,1)and not Journal.Begin(e,'a',a,2))
 end)
 test('Checkpoint persists request sessions, high-water marks and acknowledgements atomically',function()
  local c=table.clone(C);c.BotPopulation=nil;local e=E.new(c,15)
  local session=Journal.Open(e,'uid');assert(Journal.Begin(e,'uid',session,7))
  Journal.Finish(e,'uid',session,7,{Ok=true,Result={Id=23,Filled=5}})
  local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(15),Agents={}},P)
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),c)
  local accepted,cached=Journal.Begin(restored,'uid',session,7)
  assert(not accepted and cached.Ok and cached.Result.Id==23)
  assert(not Journal.Begin(restored,'uid',session,6));assert(Journal.Open(restored,'uid')==session+1)
 end)
 test('256 simultaneous accepted requests retain FIFO across bounded steps and new arrivals',function()
  local queue={};for i=1,256 do table.insert(queue,i)end
  local consumed={};local batches=0
  while #queue>0 do
   local batch;batch,queue=Queue.Take(queue);assert(#batch<=16);batches+=1
   for _,value in ipairs(batch)do table.insert(consumed,value)end
   if batches==1 then table.insert(queue,257)end
  end
  assert(#consumed==257 and batches==17)
  for i,value in ipairs(consumed)do assert(i==value,'Accepted requests reordered or dropped')end
 end)
 return rows
end
return Tests
]====]):sub(2),Hash=([====[!a3da5557116fdd8afdba1e14f6cdaf9862c034a75f6c0fc7827b48ef8c2de9de]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
release[ ([====[!ServerScriptService.MarketReign.RequestQueue]====]):sub(2) ]={Source=([====[!-- Fixed-sized FIFO batches. A wall-clock-dependent cut would change which
-- simulation step receives an accepted order, so batching is count-based.
local Queue={BatchSize=16,Capacity=256}
function Queue.Take(queue)
 local count=math.min(#queue,Queue.BatchSize);local batch=table.create(count)
 for i=1,count do batch[i]=queue[i]end
 local remaining=table.create(#queue-count)
 for i=count+1,#queue do remaining[i-count]=queue[i]end
 return batch,remaining
end
return Queue
]====]):sub(2),Hash=([====[!482b91acf00f3a55d7f17f8e5aa434a8c7023e7ba59b579c401646caaf5caad1]====]):sub(2),ExpectedHash=nil,ClassName=([====[!ModuleScript]====]):sub(2)}
local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end
for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Release hash mismatch "..path);if item.ExpectedHash then assert(instance and instance.ClassName==item.ClassName,"Missing/wrong class "..path);assert(hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash,"Source changed since evidence capture: "..path)else assert(not instance or instance.ClassName==item.ClassName and hash(instance.Source)==item.Hash,"New module collision "..path)end end
local ordered={};for path in pairs(release)do table.insert(ordered,path)end;table.sort(ordered)
for _,path in ipairs(ordered)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new(item.ClassName);instance.Name=name;instance.Source=item.Source;instance.Parent=parent else instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Installed hash mismatch "..path)end
return "Installed "..#ordered.." validated sources. No restart, save or publication was performed by this installer."
