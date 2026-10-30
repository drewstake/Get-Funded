from pathlib import Path
r=Path(__file__).resolve().parents[2]
p=r/'src/server/MarketEngine.luau'
s=p.read_text(encoding='utf-8')
s=s.replace('NextOrder=0,NextTrade=0','NextOrder=0,NextPriority=0,NextTrade=0')
s=s.replace(' if self.Resting and self.Resting[o.Contract] then self.Resting[o.Contract][o.Id]=nil end\n','')
start=s.index('-------------------------------------------------------------------------------------------------\n-- Player execution is off-book.')
end=s.index('Engine.HouseId=',start)
s=s[:start]+'''-- The historical house ledger is retained ONLY for atomic administrative migrations/resets.
-- Ordinary player orders use the same finite, executable book as participants.
'''+s[end:]
start=s.index('-- Working player limits by contract.')
end=s.index('function Engine:_playerFill',start)
s=s[:start]+s[end:]
start=s.index('-- A market trade at `tick` fills every waiting player limit')
end=s.index('function Engine:_trade',start)
s=s[:start]+'''-- Arrival priority is separate from the stable order id: repricing loses time priority.
function Engine:_priority()
 self.NextPriority=math.max(self.NextPriority or 0,self.NextOrder)+1
 return self.NextPriority
end
function Engine:_unrest(b,o)
 local levels=o.Direction==1 and b.Bids or b.Asks
 for _,level in ipairs(levels)do
  local index=table.find(level.Orders,o)
  if index then table.remove(level.Orders,index);break end
 end
 self:_cleanBook(b)
end
function Engine:_available(o,resting)
 local a=self.Accounts[o.Owner]
 if not a or self.Orders[o.Id]~=o or o.Remaining<=0 or (o.Expires and o.Expires<=self.Time)then return 0 end
 if a.Retired or a.LegacyRetired then return 0 end
 if a.Player and self.ConnectedOwners and not self.ConnectedOwners[a.Id]and (resting or not o.ReduceOnly)then return 0 end
 if o.ReduceOnly then
  local p=a.Positions[o.Contract]
  return p and p.Direction~=o.Direction and math.min(o.Remaining,p.Quantity)or 0
 end
 if a.Locked or a.Liquidating or self:Summary(a).Equity<=0 then return 0 end
 if a.Player and self:OrderCapacity(a,o.Contract,o.Direction,o.StopTicks,o.Id)<o.Remaining then return 0 end
 return o.Remaining
end
function Engine:_pruneBook(b)
 for _,side in ipairs({b.Bids,b.Asks})do for _,level in ipairs(side)do for _,o in ipairs(level.Orders)do
  if o.Remaining>0 then
   local available=self:_available(o,true)
   if available<o.Remaining then
    o.Cancelled+=o.Remaining-available;o.Remaining=available;self.Accounts[o.Owner].Revision+=1
    if available==0 then self:_retire(o,"No longer eligible")end
   end
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
 end
end
function Engine:SetConnected(owner,connected)
 if not self.ConnectedOwners then return end
 self.ConnectedOwners[owner]=connected and true or nil
 if not connected and self.Accounts[owner]then self:CancelAll(owner)end
end
'''+s[end:]
s=s.replace(' -- Waiting player limits fill at their own price once the market trades through them.\n self:_fillResting(b,tick)\n','')
s=s.replace('-- `internal` is engine-only (never from a client request): FillTicks sets a take-profit fill price.','-- `internal` is engine-only; administrative settlement is never accepted from order requests.')
s=s.replace(' if a.Locked and not reducing then', ' if a.Player and self.ConnectedOwners and not self.ConnectedOwners[owner]and not reducing then return false,"Player is no longer connected."end\n if a.Locked and not reducing then',1)
s=s.replace(' self:_cleanBook(b)\n local opposing=side==1 and b.Asks or b.Bids\n self.NextOrder+=1',' self:_pruneBook(b)\n local opposing=side==1 and b.Asks or b.Bids\n self.NextOrder+=1')
s=s.replace(' local o={Id=self.NextOrder,Owner=owner,',' local o={Id=self.NextOrder,Priority=self:_priority(),Owner=owner,')
start=s.index(' if a.Player then return self:_playerOrder(a,b,o,internal) end')
end=s.index('function Engine:ProcessStops()',start)
s=s[:start]+''' if internal and internal.AdministrativeSettlement and a.Player and reducing then
  self:_playerFill(o,self:_touch(b,side),qty);self:_retire(o,"Filled")
  return true,{Id=o.Id,Filled=o.Filled,Remaining=0,Cancelled=0,Average=o.Notional/o.Filled,Status=o.Status}
 end
 return self:_match(a,b,o)
end
function Engine:_match(a,b,o)
 self:_pruneBook(b)
 local side=o.Direction;local reducing=o.ReduceOnly
 local opposing=side==1 and b.Asks or b.Bids
 for _,level in ipairs(opposing)do
  if o.Remaining<=0 or self:_available(o,false)<=0 then break end
  if o.Type=="Limit"and (level.Price-o.Price)*side>0 then break end
  for _,resting in ipairs(level.Orders)do
   local incoming=self:_available(o,false)
   if o.Remaining<=0 or incoming<=0 then break end
   if resting.Remaining>0 then
    local ra=self.Accounts[resting.Owner]
    if resting.Owner==o.Owner or (a.Group and ra.Group==a.Group)or (a.ProfileId and ra.ProfileId==a.ProfileId)then
     resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"Self-trade prevented");ra.Revision+=1
    else
     local available=self:_available(resting,true)
     if available<=0 then
      resting.Cancelled+=resting.Remaining;resting.Remaining=0;self:_retire(resting,"No longer eligible");ra.Revision+=1
     else
      self:_trade(b,o,resting,math.min(incoming,available))
      if resting.Remaining==0 then self:_retire(resting,"Filled")end
     end
    end
   end
  end
 end
 if o.Remaining==0 then if self.Orders[o.Id]then self:_retire(o,"Filled")end
 elseif o.Type=="Market"or self:_available(o,true)<=0 then
  o.Cancelled+=o.Remaining;o.Remaining=0;self:_retire(o,o.Filled>0 and "Partial / IOC"or "No liquidity")
 else self:_rest(b,o)end
 self:_pruneBook(b);a.Revision+=1
 local average=o.Filled>0 and o.Notional/o.Filled or nil
 return true,{Id=o.Id,Filled=o.Filled,Remaining=o.Remaining,Cancelled=o.Cancelled,Average=average,Status=o.Status,
  Slippage=average and (average-o.Reference*b.Spec.Tick)*side or 0}
end
'''+s[end:]
old='''   self:CancelAll(a.Id,item.Contract)
   -- A player's take profit is a limit at the target: it fills at the target once a trade reaches it.
   local internal
   if a.Player and p.Triggered=="Take profit" and p.Target then internal={FillTicks=math.round(p.Target/self.Books[item.Contract].Spec.Tick)} end
   self:Submit(a.Id,{Contract=item.Contract,Direction=-p.Direction,Quantity=math.min(p.Quantity,a.Player and self.Config.MaxPlayerQuantity or 10000),Type="Market",ReduceOnly=true},internal)'''
new='''   local exit=p.ExitOrder and self.Orders[p.ExitOrder]
   if not exit then
    self:CancelAll(a.Id,item.Contract)
    local target=p.Triggered=="Take profit"and p.Target
    local ok,result=self:Submit(a.Id,{Contract=item.Contract,Direction=-p.Direction,
     Quantity=math.min(p.Quantity,a.Player and self.Config.MaxPlayerQuantity or 10000),
     Type=target and "Limit"or "Market",Price=target,ReduceOnly=true})
    if ok and result.Remaining>0 then p.ExitOrder=result.Id end
   end'''
assert old in s;s=s.replace(old,new)
s=s.replace(' o.Price=ticks o.Time=self.Time\n self:_playerOrder(a,b,o)',' if ticks==o.Price then return true,"Limit price is unchanged."end\n self:_unrest(b,o)\n o.Price=ticks;o.Time=self.Time;o.Priority=self:_priority()\n self:_match(a,b,o)')
s=s.replace('  local b=self.Books[symbol] local tick=b.Spec.Tick\n','  local b=self.Books[symbol] local tick=b.Spec.Tick\n  self:_pruneBook(b)\n')
s=s.replace('assert(o.Id>arrival,"FIFO violated") arrival=o.Id','assert((o.Priority or o.Id)>arrival,"FIFO violated") arrival=o.Priority or o.Id')
p.write_text(s,encoding='utf-8')
p=r/'src/server/FundedAccounts.luau';s=p.read_text(encoding='utf-8').replace('Type="Market",ReduceOnly=true},{})','Type="Market",ReduceOnly=true},{AdministrativeSettlement=true})');p.write_text(s,encoding='utf-8')
print('Shared matching implemented; historical administrative settlement remains private.')
