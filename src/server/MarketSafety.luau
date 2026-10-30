-- Public-price risk controls. Never writes prices, grants money or creates fills.
local Safety={}
function Safety.Config(e,b)
 return e.Config.PlayerExecution and e.Config.MarketSafety and b.Safety and e.Config.MarketSafety
end
function Safety.Adopt(e,p)
 local c=e.Config.MarketSafety
 if not c or not e.Config.PlayerExecution or not e.Config.BotPopulation or e.SafetyPopulation==p then return end
 local funded=false
 for _,a in ipairs(p.Agents)do if a.Kind=='Reserve'and not a.Retiring and not a.Retired then funded=true;break end end
 if not funded then return end
 e.SafetyPopulation=p -- Derived index; deliberately excluded from checkpoints.
 for _,key in ipairs(e.Config.ContractOrder)do local b=e.Books[key]
  if not b.Spec.CloseOnly then
   b.Safety=b.Safety or {Version=c.Version,History={{Time=e.Time,Price=b.Last or b.Reference}}}
   assert(b.Safety.Version==c.Version,'Unsupported market safety state')
   b.ReserveProviders={}
  end
 end
 for _,a in ipairs(p.Agents)do local b=e.Books[a.Key]
  if a.Kind=='Reserve'and b.Safety and not a.Retiring and not a.Retired then
   e.Accounts[a.Id].ReserveMarket=a.Key
   table.insert(b.ReserveProviders,a.Id)
  end
 end
end
function Safety.Sample(e)
 for _,key in ipairs(e.Config.ContractOrder)do local b=e.Books[key];local c=Safety.Config(e,b)
  if c then local h=b.Safety.History
   if e.Time-h[#h].Time>=c.SampleSeconds then
    table.insert(h,{Time=e.Time,Price=b.Last or b.Reference})
    local cutoff=e.Time-c.LongSeconds
    while #h>2 and h[2].Time<=cutoff do table.remove(h,1)end
   end
  end
 end
end
function Safety.Bounds(e,b)
 local c=Safety.Config(e,b);if not c then return 1,math.huge end
 e.SafetyBounds=e.SafetyBounds or {};local cached=e.SafetyBounds[b.Key]
 if cached and cached.Time==e.Time and cached.History==b.Safety.History
  and cached.ShortSeconds==c.ShortSeconds and cached.ShortTicks==c.ShortTicks
  and cached.LongSeconds==c.LongSeconds and cached.LongTicks==c.LongTicks and cached.Scale==b.Spec.Scale then return cached.Low,cached.High end
 local h=b.Safety.History;local lo,hi=1,math.huge;local scale=math.max(1,b.Spec.Scale or 1)
 for _,band in ipairs({{c.ShortSeconds,c.ShortTicks},{c.LongSeconds,c.LongTicks}})do
  local anchor=h[1].Price
  for _,point in ipairs(h)do if point.Time<=e.Time-band[1]then anchor=point.Price else break end end
  lo=math.max(lo,anchor-band[2]*scale);hi=math.min(hi,anchor+band[2]*scale)
 end
 e.SafetyBounds[b.Key]={Time=e.Time,History=h,Low=lo,High=hi,Scale=b.Spec.Scale,
  ShortSeconds=c.ShortSeconds,ShortTicks=c.ShortTicks,LongSeconds=c.LongSeconds,LongTicks=c.LongTicks}
 return lo,hi
end
function Safety.Allows(e,b,price)
 local lo,hi=Safety.Bounds(e,b);return price>=lo and price<=hi
end
function Safety.ReserveLimit(e,a,b,summary)
 local c=Safety.Config(e,b)
 if not c or a.ReserveMarket~=b.Key then return a.Limit end
 local equity=summary and summary.Equity or e:Mark(a);local budget=a.PolicyCapitalTarget or a.StartingCapital or a.Base
 if a.Locked or a.Liquidating or equity<=budget*(1-c.ReserveDrawdown)then return 0 end
 local funds=math.max(0,math.min(budget,equity,a.Balance))
 local stress=c.ReserveStressTicks*math.max(1,b.Spec.Scale or 1)*b.Spec.Tick*b.Spec.Multiplier
 return math.max(0,math.floor(math.min(a.Limit,c.ReserveContracts,funds*c.ReserveRiskFraction/stress)))
end
local function owner(a)return tostring(a.ProfileId or a.Group or a.Id)end
local function players(e)
 -- AddAccount invalidates this index, including same-length run replacements;
 -- retirement replaces AccountOrder. Rebuild on either change.
 -- Balances, positions, flags and orders are still read afresh on EVERY check.
 local index=e.SafetyPlayers
 if not index or index.Order~=e.AccountOrder or index.Count~=#e.AccountOrder then
  local ids={};for _,id in ipairs(e.AccountOrder)do if e.Accounts[id].Player then table.insert(ids,id)end end
  index={Order=e.AccountOrder,Count=#e.AccountOrder,Ids=ids};e.SafetyPlayers=index
 end
 return index.Ids
end
function Safety.Capacity(e,a,b,side,exclude)
 local c=Safety.Config(e,b);if not c or not a.Player then return math.huge end
 local funded=0
 for _,id in ipairs(b.ReserveProviders or {})do funded+=Safety.ReserveLimit(e,e.Accounts[id],b)end
 local marketLimit=math.floor(funded*c.MarketFraction)
 local ownerLimit=math.min(c.PlayerContracts,math.floor(funded*c.PlayerFraction))
 local own,all,signed=0,0,0;local id=owner(a)
 for _,accountId in ipairs(players(e))do local ac=e.Accounts[accountId]
  if ac.Player and not ac.Retired and not ac.Archive then
   local pos=ac.Positions[b.Key];local net=pos and pos.Quantity*pos.Direction*side or 0
   for orderId in pairs(ac.OpenOrders)do local o=e.Orders[orderId]
    if o and orderId~=exclude and o.Contract==b.Key and o.Direction==side and not o.ReduceOnly then net+=o.Remaining end
   end
   local used=math.max(0,net);all+=used;if owner(ac)==id then own+=used end
   if ac==a then signed=net end
  end
 end
 -- Grandfather old exposure for reduction only. Pending entries and related
 -- accounts share the allowance; gains, splitting and passive fills cannot evade it.
 return math.max(0,-signed)+math.max(0,math.min(ownerLimit-own,marketLimit-all))
end
-- A stalled market exit becomes a real, position-linked resting limit. It can
-- meet another participant's market exit without synthetic clearing or a crossed book.
function Safety.RestExit(e,a,b,o)
 local c=Safety.Config(e,b)
 if not c or not o.ReduceOnly or o.Type~='Market'or o.Immediate or e:_available(o,true)<=0 then return false end
 if o.Protection=='Take profit'then return false end
 local tick=b.Last or b.Reference
 local opposing=(o.Direction==1 and b.Asks or b.Bids)[1]
 if opposing and (opposing.Price-tick)*o.Direction<=0 then return false end
 if not Safety.Allows(e,b,tick)then return false end
 o.Type='Limit';o.Price=tick;o.ExitFallback=true;o.ExitRetryAt=e.Time+c.ExitRetrySeconds
 if o.ExitRestPrice and o.ExitRestPrice~=tick then o.Priority=e:_priority();o.Time=e.Time end
 o.ExitRestPrice=tick
 e:_rest(b,o);e:_blocked(o,'Waiting for counterparty · closing limit')
 local p=a.Positions[b.Key];if p then p.ExitOrder=o.Id end
 return true
end
function Safety.RetryExits(e)
 local ids={};for id,o in pairs(e.Orders)do if o.ExitFallback and e.Time>=(o.ExitRetryAt or 0)then table.insert(ids,id)end end
 table.sort(ids)
 for _,id in ipairs(ids)do local o=e.Orders[id]
  if o then local b=e.Books[o.Contract];local a=e.Accounts[o.Owner]
   e:_unrest(b,o);o.Type='Market';o.Price=nil;o.Queued=true
   o.ExitRetryAt=e.Time+e.Config.MarketSafety.ExitRetrySeconds
   e:_match(a,b,o)
  end
 end
end
return Safety
