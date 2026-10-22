-- Independent public-price countertrend and portfolio demand styles on existing funded accounts.
-- No price writes, new accounts, capital transfers, shared direction or shared random draws.
local D={}
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
local function reserveRole(a)
 local index=tonumber(a.Id:match(':(%d+)$'))or 1
 return a.Kind=='Reserve'and index%3==0, index%6==0 and 'Stretch'or 'Portfolio'
end
function D.Enabled(p,a)
 local c=p.Config.BotDiversity
 return c and a.PolicyVersion and ((c.ReserveMode and reserveRole(a))or(c.Stretch and a.Kind=='Reversion')or(c.Portfolio and a.Kind=='Value'))
end
function D.Adopt(p,a)
 local e,c=p.Engine,p.Config.BotDiversity;local s=a.Diversity
 if s and s.Version==c.Version then return s end
 cancelEntries(e,a)
 s={Version=c.Version,RandomState=seed(a.Id,e.Seed),Phase='Waiting'}
 for _=1,8 do random(s)end
 local assigned,style=reserveRole(a)
 s.Style=assigned and style or a.Kind=='Reversion'and 'Stretch'or 'Portfolio'
 s.Horizon=range(s,c.Horizons[math.min(#c.Horizons,math.floor(random(s)*#c.Horizons)+1)])
 s.Extension=range(s,c.ExtensionFraction);s.TakeFraction=range(s,c.TakeFraction)
 s.Hold=range(s,c.HoldSeconds);s.TargetFraction=range(s,c.TargetFraction)
 s.Build=range(s,c.BuildSeconds);s.Pause=range(s,c.CooldownSeconds)
 s.ReadyAt=e.Time+range(s,c.StartDelay);s.Recoveries=e.Accounts[a.Id].ParticipationRecoveries or 0
 local pos=e.Accounts[a.Id].Positions[a.Key]
 if pos then s.Phase=assigned and 'Reducing'or 'Holding';s.PositionId=pos.Id;s.OpenedAt=e.Time;s.ExitReason=assigned and 'Reallocation'or nil end
 a.Diversity=s;return s
end
function D.Signal(p,a,s)
 local e,c=p.Engine,p.Config.BotDiversity;local b=e.Books[a.Key];local h=p.Markets[a.Key].MomentumHistory
 if not h or #h<3 or e.Time-h[#h].Time>p.Config.BotMomentum.SampleSeconds*2 then return nil end
 local first
 for i=#h,1,-1 do if h[i].Time<=e.Time-s.Horizon then first=i;break end end
 if not first then return nil end
 local total,n=0,0
 for i=first,#h-1 do total+=h[i].Price;n+=1 end
 local last=b.Last or b.Reference;local mean=total/math.max(1,n)
 local bid,ask=e:PublicPrices(a.Key);if not bid or not ask then return nil end
 local spread=(ask-bid)/b.Spec.Tick;if spread>c.MaxSpreadTicks then return nil end
 local distance=last-mean
 local required=math.max(c.MinExtensionTicks,last*s.Extension,spread+c.MaxSlippageTicks+c.ProfitBufferTicks)
 return {Side=math.abs(distance)>=required and (distance>0 and -1 or 1)or 0,Distance=math.abs(distance),Required=required,Mean=mean,Last=last,Spread=spread}
end
local function pause(e,a,s,c,stopped)
 cancelEntries(e,a);s.Phase='Waiting';s.PositionId=nil;s.OpenedAt=nil;s.Target=nil;s.ProfitTicks=nil;s.ExitReason=nil
 s.ReadyAt=e.Time+s.Pause*range(s,stopped and c.StopCooldownMultiple or {.75,1.25})
end
function D.Capacity(p,a)
 local e,c=p.Engine,p.Config.BotDiversity;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local equity=e:Summary(ac).Equity
 return math.max(0,math.min(a.Limit,ac.Limit,math.floor(equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin),
  math.floor(math.max(0,equity)*c.PositionRiskFraction/(a.Stop*b.Spec.Tick*b.Spec.Multiplier))))
end
function D.Step(p,a)
 if not D.Enabled(p,a)then return end
 local e,c=p.Engine,p.Config.BotDiversity;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local s=D.Adopt(p,a)
 a.DiversityNext=e.Time+range(s,c.SliceSeconds)
 local pos=ac.Positions[a.Key]
 if ac.Locked or ac.Liquidating or a.Retiring or b.Spec.CloseOnly or(pos and pos.Triggered)then cancelEntries(e,a);return end
 if s.Recoveries~=(ac.ParticipationRecoveries or 0)then s.Recoveries=ac.ParticipationRecoveries or 0;pause(e,a,s,c,true);return end
 if s.PositionId and(not pos or pos.Id~=s.PositionId)then pause(e,a,s,c,true);return end
 local equity=e:Summary(ac).Equity;local capacity=D.Capacity(p,a)
 local stressed=equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)
 if reserveRole(a)and c.ReserveMode=='Withdraw'then
  cancelEntries(e,a)
  if not pos then return end
  s.Phase='Reducing';s.ExitReason='Reallocation'
 end
 if pos and not s.PositionId then s.PositionId=pos.Id;s.OpenedAt=e.Time;s.Phase='Holding'end
 if pos then
  if stressed or pos.Quantity>capacity then s.Phase='Reducing';s.ExitReason='Risk'
  elseif e.Time-(s.OpenedAt or e.Time)>=s.Hold then s.Phase='Reducing';s.ExitReason='Time'
  elseif s.Style=='Stretch'and s.ProfitTicks and not pos.ManualTarget then
   local bid,ask=e:PublicPrices(a.Key);local touch=pos.Direction==1 and bid or ask
   if touch and(touch-pos.Entry)*pos.Direction>=s.ProfitTicks*b.Spec.Tick then s.Phase='Reducing';s.ExitReason='Retracement'end
  end
 end
 if s.Phase=='Building'and(e.Time>=s.BuildUntil or pos and pos.Quantity>=math.abs(s.Target))then
  if pos then s.Phase='Holding'else pause(e,a,s,c,false)end
 end
 if s.Phase=='Waiting'then
  if pos or stressed or capacity<1 or e.Time<s.ReadyAt then return end
  local side,signal
  if s.Style=='Stretch'then signal=D.Signal(p,a,s);if not signal or signal.Side==0 then return end;side=signal.Side
  else side=random(s)<.5 and 1 or -1 end
  local quantity=math.floor(capacity*s.TargetFraction);if quantity<1 then return end
  s.Target=side*quantity;s.Phase='Building';s.StartedAt=e.Time;s.BuildUntil=e.Time+s.Build;s.Filled=0;s.ExitReason=nil
  s.ProfitTicks=signal and math.max(c.MinProfitTicks,math.ceil(signal.Spread+c.MaxSlippageTicks+c.ProfitBufferTicks),math.floor(signal.Distance*s.TakeFraction))or nil
 end
 if s.Phase=='Holding'then return end
 if s.Phase=='Reducing'and not pos then pause(e,a,s,c,false);return end
 local reducing=s.Phase=='Reducing'
 local inventory=pos and pos.Quantity*pos.Direction or 0
 local delta=(reducing and 0 or math.clamp(s.Target,-capacity,capacity))-inventory
 if delta==0 then s.Phase=pos and 'Holding'or 'Waiting';return end
 local side=delta>0 and 1 or -1
 if pos and side~=pos.Direction then reducing=true end
 local size=math.min(math.abs(delta),math.max(1,math.floor(a.Size*range(s,c.SliceFraction))))
 if reducing then
  cancelEntries(e,a)
  local available=pos.Quantity
  for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and o.Contract==a.Key and o.ReduceOnly then available-=o.Remaining end end
  size=math.min(size,math.max(0,available))
 else
  local due=math.ceil(math.abs(s.Target)*math.clamp((e.Time-s.StartedAt+c.SliceSeconds[2])/s.Build,0,1))
  size=math.min(size,math.max(0,due-s.Filled));size=p:_fit(a,side,size)
 end
 if size<1 then return end
 local bid,ask=e:PublicPrices(a.Key);local touch=side==1 and ask or bid;if not touch then return end
 local tick=math.max(1,math.round(touch/b.Spec.Tick)+side*c.MaxSlippageTicks)
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type='Limit',Price=tick*b.Spec.Tick,
  ReduceOnly=reducing,StopTicks=not reducing and a.Stop or nil,Expires=e.Time+c.SliceSeconds[1]})
 if ok then
  if not reducing then s.Filled+=result.Filled end
  if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  local held=ac.Positions[a.Key]
  if held then
   if not s.PositionId then s.OpenedAt=e.Time end
   s.PositionId=held.Id
  elseif reducing then pause(e,a,s,c,false)end
 end
end
return D
