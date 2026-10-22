-- Public-price Momentum only. All durable state is on agents/Markets; no wall clocks,
-- hidden values, private loops, synthetic fills, funding writes, or shared RNG draws.
local M={}
local function random(state)
 state.RandomState=state.RandomState*48271%2147483647
 return state.RandomState/2147483647
end
local function range(state,limits)return limits[1]+(limits[2]-limits[1])*random(state)end
local function seed(id,world)
 local n=math.floor(math.abs(world or 1))%2147483646+1
 for i=1,#id do n=(n*31+string.byte(id,i))%2147483646 end
 return n+1
end
function M.Enabled(p,a)
 return a.Kind=='Momentum' and p.Config.BotMomentum~=nil and p.Config.BotPopulation~=nil and a.PolicyVersion~=nil
end
function M.Sample(p,key)
 local c=p.Config.BotMomentum;if not c then return end
 local e=p.Engine;local b=e.Books[key];if b.Spec.CloseOnly then return end
 local market=p.Markets[key];local h=market.MomentumHistory or {};market.MomentumHistory=h
 if #h>0 and e.Time-h[#h].Time<c.SampleSeconds then return end
 table.insert(h,{Time=e.Time,Price=b.Last or b.Reference})
 while #h>2 and h[2].Time<e.Time-c.RetentionSeconds do table.remove(h,1)end
end
function M.Adopt(p,a)
 local c=p.Config.BotMomentum;local e=p.Engine;local old=a.Momentum
 if old and old.Version==c.Version then return old end
 -- Cancel entry intent at the next decision only. Restore itself never touches orders.
 local ac=e.Accounts[a.Id];local ids={}
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
 local s={Version=c.Version,RandomState=seed(a.Id,e.Seed)}
 -- Mix nearby numeric identities before assigning cohorts; the first LCG draw alone
 -- would put neighboring IDs in nearly identical horizons.
 for _=1,6 do random(s)end
 local cohort=math.min(#c.Horizons,math.floor(random(s)*#c.Horizons)+1)
 s.Horizon=range(s,c.Horizons[cohort]);s.Cohort=cohort
 s.Style=random(s)<c.BreakoutFraction and 'Breakout'or 'Trend'
 s.Threshold=range(s,c.EntryStrength);s.Confirmation=range(s,c.ConfirmationSeconds)
 s.HoldSeconds=math.clamp(s.Horizon*range(s,c.HoldMultiple),c.MinHoldSeconds,c.MaxHoldSeconds)
 s.TargetFraction=range(s,c.TargetFraction);s.BuildSeconds=range(s,c.BuildSeconds)
 s.ReviewSeconds=range(s,c.ReviewSeconds);s.NextReview=e.Time
 local pos=ac.Positions[a.Key]
 s.Phase=pos and 'Holding'or 'Waiting';s.PositionId=pos and pos.Id
 s.OpenedAt=pos and e.Time;s.Best=pos and (e.Books[a.Key].Last or e.Books[a.Key].Reference)
 s.CooldownUntil=e.Time+range(s,c.StartDelay)
 a.Momentum=s;a.OrderObjective=nil;a.FlowPositionId=nil;a.FlowCooldownUntil=nil
 return s
end
-- Use completed observations before the confirmation interval for the breakout range.
-- Repeated identical prints contribute zero volatility; activity is not a signal.
function M.Signal(p,a,s)
 local c=p.Config.BotMomentum;local e=p.Engine;local b=e.Books[a.Key]
 local h=p.Markets[a.Key].MomentumHistory
 if not h or #h<3 or e.Time-h[#h].Time>c.SampleSeconds*2 then return nil end
 local first,recent
 for i=#h,1,-1 do
  if not recent and h[i].Time<=e.Time-s.Confirmation then recent=i end
  if h[i].Time<=e.Time-s.Horizon then first=i;break end
 end
 if not first or not recent or recent<=first then return nil end
 local last=b.Last or b.Reference;local low,high=math.huge,-math.huge
 local sum2,n=0,0
 for i=first,recent do low=math.min(low,h[i].Price);high=math.max(high,h[i].Price)end
 for i=first+1,#h do local d=h[i].Price-h[i-1].Price;sum2+=d*d;n+=1 end
 local bid,ask=e:PublicPrices(a.Key)
 if not bid or not ask then return nil end
 local spread=(ask-bid)/b.Spec.Tick
 local volatility=math.sqrt(sum2/math.max(1,n))*math.sqrt(s.Horizon/c.SampleSeconds)
 local required=math.max(c.MinMoveTicks,spread+c.MaxSlippageTicks+c.ProfitBufferTicks,volatility*s.Threshold)
 local move=last-h[first].Price;local confirmation=last-h[recent].Price
 local buffer=math.max(c.BreakoutBufferTicks,spread*.5)
 local side=0;local level
 if s.Style=='Breakout'then
  if last>high+buffer and confirmation>0 then side=1;level=high
  elseif last<low-buffer and confirmation<0 then side=-1;level=low end
  if math.abs(move)<required then side=0 end
 elseif math.abs(move)>=required and move*confirmation>=0 then side=move>0 and 1 or -1 end
 return {Side=side,Move=move,Required=required,Volatility=volatility,Spread=spread,
  Last=last,Confirmation=confirmation,Level=level,Buffer=buffer}
end
local function cancelEntries(e,a)
 local ids={};for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
end
local function pause(e,a,s,c,stopped)
 s.Phase='Waiting';s.PositionId=nil;s.OpenedAt=nil;s.Target=nil;s.BreakoutLevel=nil;s.InvalidSince=nil
 s.CooldownUntil=e.Time+range(s,stopped and c.StopCooldownSeconds or c.CooldownSeconds)
 a.FlowCooldownUntil=s.CooldownUntil
end
function M.Step(p,a)
 if not M.Enabled(p,a)then return end
 local e,c=p.Engine,p.Config.BotMomentum;local ac=e.Accounts[a.Id];local b=e.Books[a.Key]
 local s=M.Adopt(p,a)
 a.FlowNextDecision=e.Time+range(s,c.SliceSeconds)
 if ac.Locked or ac.Liquidating or a.Retiring or b.Spec.CloseOnly then return end
 local pos=ac.Positions[a.Key];if pos and pos.Triggered then return end
 -- Recovery may have closed positions outside this executor. Never resurrect its mandate.
 if s.PositionId and (not pos or pos.Id~=s.PositionId)then pause(e,a,s,c,true);return end
 if (s.CooldownUntil or 0)>e.Time then a.FlowCooldownUntil=s.CooldownUntil;return end
 a.FlowCooldownUntil=nil
 local equity=e:Summary(ac).Equity
 local stressed=equity<=a.Budget*(1-p.Config.BotOrderFlow.MaxDrawdown)
 local capacity=math.max(0,math.min(a.Limit,ac.Limit,math.floor(equity*ac.Risk*p.Config.BotPopulation.MarginFraction/b.Spec.Margin)))
 if pos and not s.PositionId then
  s.PositionId=pos.Id;s.OpenedAt=e.Time;s.Best=b.Last or b.Reference;s.Phase='Holding'
 end
 if pos and (stressed or pos.Quantity>capacity or e.Time-(s.OpenedAt or e.Time)>=s.HoldSeconds)then
  s.Phase='Reducing';s.ExitReason=stressed and 'Drawdown'or pos.Quantity>capacity and 'Capacity'or 'Time'
 end
 if e.Time>=s.NextReview then
  s.NextReview=e.Time+s.ReviewSeconds*range(s,{.75,1.25})
  local signal=M.Signal(p,a,s)
  if s.EntryEpisodeSide then
   local last=b.Last or b.Reference
   s.EntryEpisodeExtreme=s.EntryEpisodeSide==1 and math.max(s.EntryEpisodeExtreme,last)or math.min(s.EntryEpisodeExtreme,last)
   -- A fresh opportunity requires a real pullback, not cooldown expiry in the same impulse.
   local reset=math.max(6,a.Stop*.35)
   if (s.EntryEpisodeExtreme-last)*s.EntryEpisodeSide>=reset then s.EntryEpisodeSide=nil;s.EntryEpisodeExtreme=nil end
  end
  if pos and signal and s.Phase~='Reducing'then
   local failed=signal.Move*pos.Direction < -signal.Required*c.ExitStrength
   if s.BreakoutLevel then failed=failed or (signal.Last-s.BreakoutLevel)*pos.Direction < -signal.Buffer end
   if failed then
    s.InvalidSince=s.InvalidSince or e.Time
    if e.Time-s.InvalidSince>=s.Confirmation then s.Phase='Reducing';s.ExitReason='Thesis' end
   else s.InvalidSince=nil end
  elseif not pos and s.Phase=='Waiting'and not stressed and signal and signal.Side~=0 then
   local riskCapacity=math.floor(math.max(0,equity)*c.PositionRiskFraction/(a.Stop*b.Spec.Tick*b.Spec.Multiplier))
   local quantity=math.min(math.floor(capacity*s.TargetFraction),riskCapacity)
   if quantity>0 and not (s.EntryEpisodeSide==signal.Side) then
    s.EntryEpisodeSide=signal.Side;s.EntryEpisodeExtreme=signal.Last
    s.Phase='Building';s.Target=quantity*signal.Side;s.StartedAt=e.Time;s.Filled=0
    s.BuildUntil=e.Time+s.BuildSeconds;s.BreakoutLevel=signal.Level;s.InvalidSince=nil
   end
  end
 end
 if pos then
  local last=b.Last or b.Reference
  s.Best=pos.Direction==1 and math.max(s.Best or last,last)or math.min(s.Best or last,last)
  -- Ratchet only after a favorable move; never loosen or replace triggered/manual protection.
  if s.Phase~='Reducing'and not pos.ManualStop and (s.Best-pos.Entry/b.Spec.Tick)*pos.Direction>=a.Stop*c.TrailActivation then
   local stop=math.max(1,math.round(s.Best-pos.Direction*a.Stop))*b.Spec.Tick
   if not pos.Stop or (stop-pos.Stop)*pos.Direction>0 then pos.Stop=stop;ac.Revision+=1 end
  end
 end
 if s.Phase=='Building'and e.Time>=s.BuildUntil then
  if pos then s.Phase='Holding'else pause(e,a,s,c,false)end
 end
 if s.Phase=='Holding'or s.Phase=='Waiting'then return end
 if s.Phase=='Reducing'and not pos then pause(e,a,s,c,false);return end
 local reducing=s.Phase=='Reducing'
 local inventory=pos and pos.Quantity*pos.Direction or 0
 local target=reducing and 0 or math.clamp(s.Target,-capacity,capacity)
 local delta=target-inventory
 if delta==0 then s.Phase=pos and 'Holding'or 'Waiting';return end
 local side=delta>0 and 1 or -1
 -- An entry mandate may never reverse an inherited position.
 if pos and side~=pos.Direction then reducing=true end
 local size=math.min(math.abs(delta),math.max(1,math.floor(a.Size*range(s,c.SliceFraction))))
 if reducing then size=math.min(size,pos.Quantity);cancelEntries(e,a)
 else
  local due=math.ceil(math.abs(s.Target)*math.clamp((e.Time-s.StartedAt+c.SliceSeconds[2])/s.BuildSeconds,0,1))
  size=math.min(size,math.max(0,due-(s.Filled or 0)));size=p:_fit(a,side,size)
 end
 if size<1 then return end
 local bid,ask=e:PublicPrices(a.Key);local touch=side==1 and ask or bid
 if not touch then return end
 local tick=math.round(touch/b.Spec.Tick)+side*c.MaxSlippageTicks
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type='Limit',
  Price=math.max(1,tick)*b.Spec.Tick,ReduceOnly=reducing,StopTicks=not reducing and a.Stop or nil,Expires=e.Time+c.SliceSeconds[1]})
 if ok then
  if not reducing then s.Filled=(s.Filled or 0)+result.Filled end
  if e.Orders[result.Id]then e:Cancel(a.Id,result.Id)end
  local held=ac.Positions[a.Key]
  if held then
   if not s.PositionId then s.OpenedAt=e.Time;s.Best=b.Last or b.Reference end
   s.PositionId=held.Id
  elseif reducing then pause(e,a,s,c,false)end
 end
end
return M
