-- Persistent aggregate execution budgets. Cancelling, splitting requests, changing
-- instruments, or switching accounts of the same profile does not reset the allowance.
local Policy={}
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
function Policy.Record(e,a,b,side,quantity)
 if not e.Config.PlayerExecution or not a.Player then return end
 local s=Policy.State(e);local owner=Policy.Owner(a)..":"..side;local market=b.Key..":"..side
 s.Owners[owner]=(s.Owners[owner]or 0)+quantity
 if s.Markets[market]then s.Markets[market].Used+=quantity end
end
-- Standard limits must either finish matching the crossed liquidity or rest without
-- crossing the book. Reject a blocked submission/amendment before any fill or cancel.
function Policy.StandardLimitAllowed(e,a,b,o,price,quantity)
 if not a.Player or not e.Config.PlayerExecution then return true end
 local side=o.Direction
 if not Policy.Allows(e,b,price,side)then return false end
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
 local c=e.Config.PlayerExecution
 return not c or not b.FairReference or (price-b.FairReference)*side<=c.GuardTicks*math.max(1,b.Spec.Scale or 1)
end
function Policy.Process(e)
 local c=e.Config.PlayerExecution;if not c then return end
 local state=Policy.State(e);local pending={}
 for _,o in pairs(e.Orders)do if o.Queued then
  local a=e.Accounts[o.Owner];local owner=Policy.Owner(a);local old=pending[owner]
  -- Protective exits get priority within one player's queue, then oldest order first.
  if not old or o.ReduceOnly and not old.ReduceOnly or o.ReduceOnly==old.ReduceOnly and o.Id<old.Id then pending[owner]=o end
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
