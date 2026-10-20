-- One deterministic scheduler; participants never own task loops or modify trade prices.
local Participants={}
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
  for i=1,self.Config.ParticipantsPerInstrument do
   local total=0 for _,kind in ipairs({"Liquidity","Momentum","Value","Reversion","Protective"}) do total+=self.Config.BehaviorWeights[kind] or 0 end
   local draw=r:Range(0,total) local chosen="Liquidity"
   for _,kind in ipairs({"Liquidity","Momentum","Value","Reversion","Protective"}) do draw-=self.Config.BehaviorWeights[kind] or 0 if draw<=0 then chosen=kind break end end
   self:_agent(key,chosen,i)
  end
  if self.Config.WhaleFrequency>0 then for i=1,self.Config.WhalesPerInstrument do self:_agent(key,"Whale",i) end end
  if not book.Spec.CloseOnly then for i=1,self.Config.ScalpersPerInstrument or 0 do self:_agent(key,"Scalper",i) end end
  if self.Config.Reserve and not book.Spec.CloseOnly then for i=1,self.Config.Reserve.Count do self:_agent(key,"Reserve",i)end end
 end
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
function Participants:_agent(key,kind,index)
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
 local account=self.Engine:AddAccount(id,budget,a.Limit,a.Risk,false)
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
   for _,a in ipairs(self.Agents) do if a.Key==key and a.Kind==kind then count+=1 end end
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
 for i=1,self.Config.ParticipantsPerInstrument do
  local total=0 for _,kind in ipairs({"Liquidity","Momentum","Value","Reversion","Protective"}) do total+=self.Config.BehaviorWeights[kind] or 0 end
  local draw=r:Range(0,total) local chosen="Liquidity"
  for _,kind in ipairs({"Liquidity","Momentum","Value","Reversion","Protective"}) do draw-=self.Config.BehaviorWeights[kind] or 0 if draw<=0 then chosen=kind break end end
  self:_agent(key,chosen,i)
 end
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
   e:Submit(a.Id,{Contract=a.Key,Direction=-p.Direction,Quantity=p.Quantity,Type="Market",ReduceOnly=true})
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
 local signal=a.Bias+r:Noise()+(a.Style=="Momentum" and move or -move)
 if math.abs(signal)<0.2 then return end
 local side=signal>0 and 1 or -1
 local aggressive=r:Next()<s.AggressiveChance
 -- A marketable limit caps entry slippage; passive entries join the best quote.
 local tick=aggressive and (side==1 and ask.Price+s.MaxSlippageTicks or bid.Price-s.MaxSlippageTicks)
  or (side==1 and bid.Price or ask.Price)
 local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=a.Size,Type="Limit",
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
 local account=e.Accounts[a.Id] if account.Locked then return end
 if r:Next()<0.25 then return end -- varied inactivity, even around news
 local last=b.Last or b.Reference local market=self.Markets[a.Key]
 a.Belief+=(market.Fair-a.Belief)*r:Range(0.02,0.18)+r:Noise()*self.Regime.Volatility*c.Scale*0.6
 local p=account.Positions[a.Key] local inventory=p and p.Quantity*p.Direction or 0
 local recent=b.Recent local previous=recent[math.max(1,#recent-r:Int(8,35))] or last
 local momentum=(last-previous)/math.max(3,b.Volatility*8)
 local edge=(a.Belief-last)/math.max(4,b.Volatility*8)
 local signal=a.Bias+r:Noise()*1.3-inventory/a.Limit*1.8
 if a.Kind=="Momentum" then signal+=momentum*r:Range(0.5,1.4)
 elseif a.Kind=="Value" then signal+=edge*r:Range(0.6,1.5)
 elseif a.Kind=="Reversion" then signal-=momentum*r:Range(0.6,1.6) signal+=edge*0.3
 elseif a.Kind=="Protective" then signal+=edge*0.4 end
 if math.abs(signal)<r:Range(0.1,0.55) then return end
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
  if e.Time>=a.Next then
   if a.Kind=="Maker" then self:_maker(a) elseif a.Kind=="Reserve"then self:_reserve(a)elseif a.Kind=="Scalper" then self:_scalper(a) else self:_trader(a) end
   local delay=a.Speed*r:Range(0.45,1.65)/self.Regime.Activity
   if a.Kind=="Maker" then delay*=self.Config.MakerDecisionMultiplier or 1 end
   if a.Kind=="Whale" then delay=a.Parent>0 and r:Range(1.5,6) or delay/math.max(0.0001,self.Config.WhaleFrequency) end
   a.Next=e.Time+delay
   e:ProcessStops()
  end
 end
 e:ProcessPlayerOrders()
end
return Participants
