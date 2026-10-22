-- Inventory-sensitive passive market making. State is saved on the existing Maker agent.
-- No private task loops, shared RNG draws, price writes or funding adjustments.
local M={}
local function random(s)s.RandomState=s.RandomState*48271%2147483647;return s.RandomState/2147483647 end
local function range(s,v)return v[1]+(v[2]-v[1])*random(s)end
local function seed(id,world)
 local n=math.floor(math.abs(world or 1))%2147483646+1
 for i=1,#id do n=(n*31+string.byte(id,i))%2147483646 end
 return n+1
end
local function cancelEntries(e,a)
 local ids={};for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
end
function M.Enabled(p,a)return a.Kind=='Maker'and p.Config.BotMaker~=nil and p.Config.BotPopulation~=nil and a.PolicyVersion~=nil end
function M.Adopt(p,a)
 local e,c=p.Engine,p.Config.BotMaker;local s=a.Maker
 if s and s.Version==c.Version then return s end
 local ac=e.Accounts[a.Id];local inherited=next(ac.OpenOrders)~=nil
 cancelEntries(e,a)
 s={Version=c.Version,RandomState=seed(a.Id,e.Seed),Anchor=e.Books[a.Key].Last or e.Books[a.Key].Reference,ObservedAt=e.Time,Mode='Normal',Sides={}}
 for _=1,6 do random(s)end
 s.Response=range(s,c.ResponseSeconds);s.WarehouseMultiple=range(s,c.WarehouseMultiple);s.Soft=range(s,c.SoftUtilization);s.Hard=range(s,c.UnwindUtilization)
 s.Resume=range(s,c.ResumeUtilization);s.MaxAge=range(s,c.MaxInventorySeconds);s.Skew=range(s,c.SkewTicks)
 s.MinRest=range(s,c.MinRestSeconds);s.Refill=range(s,c.RefillSeconds);s.Decay=range(s,c.HitDecaySeconds)
 for _,side in ipairs({1,-1})do s.Sides[tostring(side)]={Fills=side==1 and(ac.BotBuyContracts or 0)or(ac.BotSellContracts or 0),Pressure=0}end
 local pos=ac.Positions[a.Key];s.PositionId=pos and pos.Id;s.InventorySince=pos and e.Time
 s.Recoveries=ac.ParticipationRecoveries or 0
 a.Maker=s;a.Quotes={};a.ReplenishAt={};a.QuotePolicy=p.Config.MakerQuotePolicyVersion
 -- Existing inventory/exits survive adoption; entry withdrawals return at staggered times.
 if inherited then for depth=1,3 do for _,side in ipairs({1,-1})do a.ReplenishAt[side..':'..depth]=e.Time+s.Refill*range(s,{.8,1.2})end end end
 return s
end
function M.Capacity(p,a)
 local e=p.Engine;local ac=e.Accounts[a.Id]
 return math.max(0,math.min(a.Limit,ac.Limit,math.floor(e:Summary(ac).Equity*ac.Risk*p.Config.BotPopulation.MarginFraction/e.Books[a.Key].Spec.Margin)))
end
local function observe(e,a,s,c)
 local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local dt=math.max(0,e.Time-s.ObservedAt);local last=b.Last or b.Reference
 if s.Response==0 then s.Anchor=last elseif dt>0 then s.Anchor+=(last-s.Anchor)*dt/(s.Response+dt)end;s.ObservedAt=e.Time
 for _,side in ipairs({1,-1})do
  local q=s.Sides[tostring(side)];local fills=side==1 and(ac.BotBuyContracts or 0)or(ac.BotSellContracts or 0)
  q.Pressure=math.min(c.MaxHitPressure,q.Pressure*s.Decay/(s.Decay+dt)+math.max(0,fills-q.Fills)/math.max(1,a.Size))
  q.Fills=fills
 end
 local pos=ac.Positions[a.Key]
 if not pos or pos.Id~=s.PositionId or s.Recoveries~=(ac.ParticipationRecoveries or 0)then
  s.PositionId=pos and pos.Id;s.InventorySince=pos and e.Time;s.Mode='Normal'
 end
 s.Recoveries=ac.ParticipationRecoveries or 0
end
function M.Plan(p,a,s)
 local e,c=p.Engine,p.Config.BotMaker;local b=e.Books[a.Key];local ac=e.Accounts[a.Id];local pos=ac.Positions[a.Key]
 local funded=M.Capacity(p,a);local capacity=math.min(funded,math.max(a.Size*s.WarehouseMultiple,math.floor(funded*c.WarehouseCapacityFraction)));local inventory=pos and pos.Quantity*pos.Direction or 0
 local utilization=math.abs(inventory)/math.max(1,capacity);local signed=inventory/math.max(1,capacity)
 local age=pos and e.Time-(s.InventorySince or e.Time)or 0
 if not pos or s.Mode=='Unwind'and utilization<=s.Resume then s.Mode='Normal';s.InventorySince=pos and e.Time
 elseif s.Mode~='Unwind'and(utilization>=s.Hard or age>=s.MaxAge and utilization>=c.AgeMinimumUtilization)then s.Mode='Unwind'end
 local stress=p.Regime.Volatility*p.Config.Volatility+math.min(6,b.Volatility)*.2
 local reference=b.Last or b.Reference;local scale=math.max(1,b.Spec.Scale or 1)
 local anchor=math.clamp(s.Anchor,reference-c.MaxAnchorLagTicks*scale,reference+c.MaxAnchorLagTicks*scale)
 local pressure=math.clamp((utilization-c.InventoryResponseStart)/math.max(.01,s.Hard-c.InventoryResponseStart),0,1)
 local skew=inventory/math.max(1,a.Limit)*(5+stress*5)+(inventory>=0 and 1 or -1)*s.Skew*c.NonlinearSkew*pressure^2
 return {Capacity=capacity,Inventory=inventory,Utilization=utilization,Age=age,Reference=reference,
  Center=anchor-skew,InventoryPressure=pressure,Spread=math.max(1,math.floor(stress*.8+b.Volatility*.2)),Stress=stress,
  Liquidity=p.Regime.Liquidity*p.Config.Liquidity,Unwind=s.Mode=='Unwind'}
end
local function withdraw(e,a,s,slot,delay)
 local id=a.Quotes[slot];if id and e.Orders[id]then e:Cancel(a.Id,id)end
 a.Quotes[slot]=nil;a.ReplenishAt[slot]=math.max(a.ReplenishAt[slot]or 0,e.Time+delay)
end
function M.Step(p,a)
 if not M.Enabled(p,a)then return end
 local e,c=p.Engine,p.Config.BotMaker;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local s=M.Adopt(p,a)
 observe(e,a,s,c)
 local pos=ac.Positions[a.Key]
 if ac.Locked or ac.Liquidating or a.Retiring or b.Spec.CloseOnly or pos and pos.Triggered then cancelEntries(e,a);return end
 local plan=M.Plan(p,a,s);local lanes=p.Config.MakerLanes
 local lane=lanes and((tonumber(a.Id:match(':(%d+)$'))or 1)-1)%lanes.Count or 0
 local offset=lanes and lane*(lanes.SpacingTicks[a.Key]or 1)or 0
 local depthCount=plan.Liquidity<.35 and 1 or plan.Liquidity<.7 and 2 or 3
 local desired={};local order={}
 for depth=1,3 do for _,side in ipairs({1,-1})do
  local slot=side..':'..depth;table.insert(order,slot)
  local closingSide=pos~=nil and side==-pos.Direction;local reducing=closingSide and(plan.Unwind or plan.Utilization>=s.Soft);local adding=pos~=nil and not closingSide
  local pressure=s.Sides[tostring(side)].Pressure
  local riskOff=adding and(plan.Unwind or plan.Utilization>=s.Soft)
  local compression=closingSide and plan.InventoryPressure or 0
  if plan.Unwind and reducing then compression=1 end
  local distance=plan.Spread+offset*(1-compression)+(depth-1)*math.max(1,math.floor(plan.Stress))
  if not closingSide then distance+=pressure*c.HitSpreadTicks*plan.InventoryPressure end
  local tick=math.max(1,math.round(plan.Center-side*distance))
  local opposing=side==1 and b.Asks[1]or b.Bids[1]
  if opposing then tick=side==1 and math.max(1,math.min(tick,opposing.Price-1))or math.max(tick,opposing.Price+1)end
  local factor=math.max(0,1-plan.Inventory/math.max(1,a.Limit)*side*.8)
  if adding then factor*=1-plan.InventoryPressure*.8 end
  local base=a.Size*(p.Config.MakerQuoteSizeMultiplier or 1)*plan.Liquidity*(1+(depth-1)*.15)
  local size=math.floor(base*factor/(1+(closingSide and 0 or pressure*c.HitSizePenalty*plan.InventoryPressure)))
  if reducing and base>0 then size=math.max(1,size)end
  local eligible=depth<=depthCount and not riskOff and size>0 and(reducing or plan.Capacity>0)
  desired[slot]={Side=side,Tick=tick,Size=size,Reducing=reducing,Eligible=eligible}
 end end
 local known={};for _,id in pairs(a.Quotes)do known[id]=true end
 local closing=pos and pos.Quantity or 0
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and o.ReduceOnly and o.Contract==a.Key and not known[id]then closing-=o.Remaining end end
 local entryBudget={['1']=math.max(0,math.floor(plan.Capacity*s.Hard)-math.max(0,plan.Inventory)),['-1']=math.max(0,math.floor(plan.Capacity*s.Hard)-math.max(0,-plan.Inventory))}
 -- Withdraw first, then allocate. Every cancellation waits; repricing cannot refill instantly.
 for _,slot in ipairs(order)do
  local d=desired[slot];local id=a.Quotes[slot];local held=id and e.Orders[id]
  if id and not held then
   withdraw(e,a,s,slot,s.Refill*(1+s.Sides[tostring(d.Side)].Pressure*.25)*range(s,{.8,1.2}))
  elseif held then
   local stale=(held.Price-plan.Reference)*d.Side>=math.max(2,plan.Spread)and math.abs(held.Price-d.Tick)>=(p.Config.MakerRepriceTicks or 3)
   local incompatible=(held.ReduceOnly==true)~=d.Reducing or held.ReduceOnly and(pos==nil or held.ReductionPosition~=pos.Id)
   local riskOff=not d.Eligible or not d.Reducing and plan.Utilization>=s.Soft and plan.Inventory*d.Side>0
   local available=held.ReduceOnly and math.max(0,closing)or entryBudget[tostring(d.Side)]
   riskOff=riskOff or held.Remaining>available
   local reprice=e.Time-held.Time>=s.MinRest and math.abs(held.Price-d.Tick)>=(p.Config.MakerRepriceTicks or 3)
   if stale or incompatible or riskOff or reprice then withdraw(e,a,s,slot,range(s,c.RepriceSeconds))
   elseif held.ReduceOnly then closing-=held.Remaining else entryBudget[tostring(d.Side)]-=held.Remaining end
  end
 end
 -- All reducing orders, including inherited/manual exits, share the actual position quantity.
 local closingReserved=0
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and o.ReduceOnly and o.Contract==a.Key then closingReserved+=o.Remaining end end
 for _,slot in ipairs(order)do
  local d=desired[slot]
  if not a.Quotes[slot]and d.Eligible and e.Time>=(a.ReplenishAt[slot]or 0)then
   local size=d.Size
   if d.Reducing then size=math.min(size,math.max(0,pos.Quantity-closingReserved))
   else
    -- A strategy warehouse ceiling is stricter than, and never expands, engine buying power.
    local working=0;for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly and o.Contract==a.Key and o.Direction==d.Side then working+=o.Remaining end end
    size=math.min(size,math.max(0,math.floor(plan.Capacity*s.Hard)-math.max(0,plan.Inventory*d.Side)-working))
    size=p:_fit(a,d.Side,size)
   end
   if size>0 then
    local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=d.Side,Quantity=size,Type='Limit',Price=d.Tick*b.Spec.Tick,
     ReduceOnly=d.Reducing,Expires=e.Time+s.MinRest*c.QuoteLifetimeMultiple})
    if ok and result.Remaining>0 then a.Quotes[slot]=result.Id;if d.Reducing then closingReserved+=result.Remaining end end
   end
  end
 end
end
return M
