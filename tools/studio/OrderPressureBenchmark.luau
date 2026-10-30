local function run(root,seed,seconds)
 local f=root:Clone()
 local configModule=root:FindFirstChild('MarketConfig')and f.MarketConfig or game.ReplicatedStorage.MarketReign.MarketConfig:Clone()
 local ok,result=pcall(function()
  local c=require(configModule);local E=require(f.MarketEngine);local P=require(f.Participants)
  local e=E.new(c,seed);local p=P.new(e);local stats={}
  for key in pairs(e.Books)do stats[key]={Trades=0,Volume=0,Low=math.huge,High=-math.huge,Spreads={},NoQuote=0,MidLow=math.huge,MidHigh=-math.huge,Up=0,Down=0,ByAggressor={}}end
  local kinds={};for _,a in ipairs(p.Agents)do kinds[a.Id]=a.Kind end
  local trade=e._trade;e._trade=function(self,b,incoming,resting,qty)
   trade(self,b,incoming,resting,qty)
   if self.Time>=300 then
    local s=stats[b.Key];s.Trades+=1;s.Volume+=qty;s.Low=math.min(s.Low,b.Last);s.High=math.max(s.High,b.Last)
    local kind=kinds[incoming.Owner]or 'Other';s.ByAggressor[kind]=(s.ByAggressor[kind]or 0)+qty
   end
  end
  for i=1,seconds/c.StepSeconds do
   p:Step()
   if e.Time>=300 and i%4==0 then for key,b in pairs(e.Books)do
    local s=stats[key];local bid,ask=e:PublicPrices(key)
    if bid and ask then
     local mid=(bid+ask)/2/b.Spec.Tick;s.MidLow=math.min(s.MidLow,mid);s.MidHigh=math.max(s.MidHigh,mid)
     if s.PriorMid then if mid>s.PriorMid then s.Up+=1 elseif mid<s.PriorMid then s.Down+=1 end end;s.PriorMid=mid
     table.insert(s.Spreads,math.round((ask-bid)/b.Spec.Tick))
    else s.NoQuote+=1 end
   end end
   if i%120==0 then task.wait()end
  end
  e:Audit()
  for key,b in pairs(e.Books)do
   local s=stats[key];s.RangeTicks=s.High-s.Low;s.MidpointRangeTicks=s.MidHigh-s.MidLow
   s.Low=nil;s.High=nil;s.MidLow=nil;s.MidHigh=nil;s.PriorMid=nil
   table.sort(s.Spreads);s.MedianSpread=s.Spreads[math.ceil(#s.Spreads*.5)];s.P95Spread=s.Spreads[math.ceil(#s.Spreads*.95)];s.MaxSpread=s.Spreads[#s.Spreads];s.Spreads=nil
   local total,count,narrow=0,0,0
   for _,bar in ipairs(b.Candles['1m'])do if bar.Time>=300 then local range=(bar.High-bar.Low)/b.Spec.Tick;total+=range;count+=1;if range<=1.01 then narrow+=1 end end end
   s.MeanMinuteRange=total/math.max(1,count);s.OneTickMinutes=narrow;s.Minutes=count
  end
  local depleted=0;for _,a in ipairs(p.Agents)do if e:Summary(e.Accounts[a.Id]).Equity<=0 then depleted+=1 end end
  return {Seed=seed,Seconds=seconds,MeasuredSeconds=seconds-300,Markets=stats,Depleted=depleted,Audit=true}
 end)
 f:Destroy();if configModule.Parent==nil then configModule:Destroy()end
 if not ok then error(result)end
 return result
end
return run
