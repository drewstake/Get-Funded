-- Funded, inventory-capped fades of stretched public prices that are losing speed.
-- All clocks, observations and private random state are checkpointed; no price/cash writes.
local R={}
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
function R.Enabled(p,a)return a.Kind=='Reversion'and p.Config.BotReversion~=nil and a.PolicyVersion~=nil end
function R.Sample(p,key)
 local c=p.Config.BotReversion;if not c then return end
 local e=p.Engine;local b=e.Books[key];if b.Spec.CloseOnly then return end
 local h=p.Markets[key].ReversionHistory or {};p.Markets[key].ReversionHistory=h
 if #h>0 and e.Time-h[#h].Time<c.SampleSeconds then return end
 table.insert(h,{Time=e.Time,Price=b.Last or b.Reference})
 while #h>2 and h[2].Time<e.Time-c.RetentionSeconds do table.remove(h,1)end
end
function R.Adopt(p,a)
 local e,c=p.Engine,p.Config.BotReversion;local s=a.Reversion
 if s and s.Version==c.Version then return s end
 cancelEntries(e,a)
 s={Version=c.Version,RandomState=seed(a.Id,e.Seed),Phase='Waiting'}
 for _=1,6 do random(s)end
 s.Horizon=range(s,c.LookbackSeconds);s.Recent=range(s,c.SlowingSeconds)
 s.Extension=range(s,c.ExtensionTicks);s.Deceleration=range(s,c.Deceleration)
 s.Hold=range(s,c.HoldSeconds);s.Cooldown=range(s,c.CooldownSeconds)
 s.Aggression=range(s,c.Aggression);s.ProfitFraction=range(s,c.ProfitFraction)
 s.ReadyAt=e.Time+range(s,c.StartDelay);s.Recoveries=e.Accounts[a.Id].ParticipationRecoveries or 0
 s.Review=range(s,c.ReviewSeconds)
 a.Reversion=s;return s
end
function R.Signal(p,a,s)
 local e,c=p.Engine,p.Config.BotReversion;local h=p.Markets[a.Key].ReversionHistory
 if not h or #h<4 or e.Time-h[#h].Time>c.SampleSeconds*2 then return nil end
 local first,recent,prior
 for i=#h,1,-1 do
  if not recent and h[i].Time<=e.Time-s.Recent then recent=i end
  if not prior and h[i].Time<=e.Time-s.Recent*2 then prior=i end
  if h[i].Time<=e.Time-s.Horizon then first=i;break end
 end
 if not first or not recent or not prior or prior<=first or recent<=prior then return nil end
 local b=e.Books[a.Key];local last=b.Last or b.Reference;local bid,ask=e:PublicPrices(a.Key)
 if not bid or not ask then return nil end
 local spread=(ask-bid)/b.Spec.Tick;if spread>c.MaxSpreadTicks then return nil end
 local total,duration,sum2,n=0,0,0,0
 for i=first,#h-1 do
  local dt=h[i+1].Time-h[i].Time;total+=h[i].Price*dt;duration+=dt
  local d=h[i+1].Price-h[i].Price;sum2+=d*d;n+=1
 end
 if duration<=0 then return nil end
 local mean=total/duration;local extension=last-mean;local direction=extension>=0 and 1 or -1
 local required=math.max(s.Extension,spread+c.MaxSlippageTicks+c.ProfitBufferTicks,math.sqrt(sum2/math.max(1,n))*c.VolatilityExtension)
 local recentRate=(last-h[recent].Price)/math.max(c.SampleSeconds,e.Time-h[recent].Time)
 local priorRate=(h[recent].Price-h[prior].Price)/math.max(c.SampleSeconds,h[recent].Time-h[prior].Time)
 -- A slowing continuation is enough: a countertrend print is not a prerequisite.
 -- Flat tape and accelerating moves are not opportunities. Large completed reversals are not chased.
 local slowing=priorRate*direction>0 and recentRate*direction<=priorRate*direction*s.Deceleration
 local limitedTurn=recentRate*direction>=-priorRate*direction*c.MaxTurnRatio
 local side=math.abs(extension)>=required and slowing and limitedTurn and -direction or 0
 return {Side=side,Mean=mean,Last=last,Distance=math.abs(extension),Required=required,Spread=spread,RecentRate=recentRate,PriorRate=priorRate}
end
function R.Capacity(p,a,stop)
 local e,c=p.Engine,p.Config.BotReversion;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local equity=e:Summary(ac).Equity
 return math.max(0,math.min(a.Limit,ac.Limit,c.MaxInventory,a.Size*c.SizeMultiple,
  math.floor(equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin),
  math.floor(equity*c.PositionRiskFraction/(stop*b.Spec.Tick*b.Spec.Multiplier))))
end
local function pause(e,a,s,c,stopped)
 cancelEntries(e,a);s.ChildId=nil;s.PositionId=nil;s.OpenedAt=nil;s.Phase='Waiting';s.TargetTick=nil
 s.ReadyAt=e.Time+s.Cooldown*range(s,stopped and c.StopCooldownMultiple or c.CooldownMultiple)
end
local function availableExit(e,a,pos)
 local qty=pos.Quantity
 for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o and o.Contract==a.Key and o.ReduceOnly then qty-=o.Remaining end end
 return math.max(0,qty)
end
function R.Step(p,a)
 if not R.Enabled(p,a)then return end
 local e,c=p.Engine,p.Config.BotReversion;local ac=e.Accounts[a.Id];local b=e.Books[a.Key];local s=R.Adopt(p,a)
 local pos=ac.Positions[a.Key];s.NextDecision=e.Time+s.Review*range(s,{.75,1.25})
 if ac.Locked or ac.Liquidating or a.Retiring or b.Spec.CloseOnly or pos and pos.Triggered then cancelEntries(e,a);return end
 if s.Recoveries~=(ac.ParticipationRecoveries or 0)then s.Recoveries=ac.ParticipationRecoveries or 0;pause(e,a,s,c,true);return end
 if s.PositionId and(not pos or pos.Id~=s.PositionId)then pause(e,a,s,c,true);return end
 local stop=math.clamp(a.Stop,c.MinStopTicks,c.MaxStopTicks);local capacity=R.Capacity(p,a,stop)
 if pos then
  if not s.PositionId then
   cancelEntries(e,a);s.ChildId=nil;s.PositionId=pos.Id;s.OpenedAt=e.Time;s.Phase='Holding'
   -- Adopt legacy positions without changing existing/manual stops or targets.
   if not pos.Stop and not pos.ManualStop then pos.Stop=math.max(1,math.round(pos.Entry/b.Spec.Tick)-pos.Direction*stop)*b.Spec.Tick;ac.Revision+=1 end
   s.TargetTick=s.TargetTick or math.round(pos.Entry/b.Spec.Tick)+pos.Direction*math.max(c.ProfitBufferTicks,math.floor(stop*.5))
  end
  if pos.Quantity>capacity or e.Time-s.OpenedAt>=s.Hold then s.Phase='Reducing'end
  if s.Phase=='Reducing'and s.ExitId then
   if e.Orders[s.ExitId]then e:Cancel(a.Id,s.ExitId)end;s.ExitId=nil
  end
  local bid,ask=e:PublicPrices(a.Key);local touch=pos.Direction==1 and bid or ask
  if not touch then return end
  local qty=math.min(availableExit(e,a,pos),a.Size,c.ExitSliceContracts)
  if qty<1 then return end
  if s.Phase=='Reducing'then
   if e.Time<(s.NextExitAt or 0)then return end
   s.NextExitAt=e.Time+range(s,c.ExitSeconds)
   local side=-pos.Direction;local tick=math.max(1,math.round(touch/b.Spec.Tick)+side*c.MaxSlippageTicks)
   local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=qty,Type='Limit',Price=tick*b.Spec.Tick,ReduceOnly=true})
   if ok and e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  elseif not pos.ManualTarget and not pos.Target then
   -- Rest a funded, position-linked profit exit. Never lower it just to force a fill.
   local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=-pos.Direction,Quantity=availableExit(e,a,pos),Type='Limit',Price=math.max(1,s.TargetTick)*b.Spec.Tick,ReduceOnly=true,Expires=s.OpenedAt+s.Hold})
   if ok and e.Orders[result.Id]then s.ExitId=result.Id end
  end
  return
 end
 if s.ChildId then
  if e.Orders[s.ChildId]then return end
  pause(e,a,s,c,false);return
 end
 if e.Time<s.ReadyAt or capacity<1 then return end
 local signal=R.Signal(p,a,s);if not signal or signal.Side==0 then return end
 local size=p:_fit(a,signal.Side,capacity);if size<1 then return end
 local bid,ask=e:PublicPrices(a.Key);local aggressive=random(s)<s.Aggression
 local touch=aggressive and(signal.Side==1 and ask or bid)or(signal.Side==1 and bid or ask)
 if not touch then return end
 local tick=math.max(1,math.round(touch/b.Spec.Tick)+(aggressive and signal.Side*c.MaxSlippageTicks or 0))
 local profit=math.max(math.ceil(signal.Spread+c.MaxSlippageTicks+c.ProfitBufferTicks),math.floor(math.min(signal.Distance*s.ProfitFraction,stop*c.MaxRewardMultiple)))
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=signal.Side,Quantity=size,Type='Limit',Price=tick*b.Spec.Tick,StopTicks=stop,Expires=e.Time+range(s,c.EntrySeconds)})
 s.ReadyAt=e.Time+s.Cooldown*range(s,c.CooldownMultiple)
 if ok then
  s.Phase='Entering';s.TargetTick=math.round((signal.Side==1 and ask or bid)/b.Spec.Tick)+signal.Side*profit
  if aggressive then if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  elseif e.Orders[result.Id]then s.ChildId=result.Id end
  local held=ac.Positions[a.Key]
  if held then
   cancelEntries(e,a);s.ChildId=nil;s.PositionId=held.Id;s.OpenedAt=e.Time;s.Phase='Holding'
   s.TargetTick=math.round(held.Entry/b.Spec.Tick)+held.Direction*profit
  elseif not s.ChildId then pause(e,a,s,c,false)end
 end
end
return R
