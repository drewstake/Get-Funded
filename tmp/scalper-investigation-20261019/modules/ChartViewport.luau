-- Presentation-only chart navigation. Never modifies prices, candles or account state.
-- Time is horizontal (seconds), price is vertical. All inputs are screen deltas in pixels.
local Viewport={}
Viewport.Seconds={["1m"]=60,["5m"]=300,["15m"]=900,["1h"]=3600,["1D"]=86400}
Viewport.MinBars=10          -- deepest zoom-in
Viewport.MaxBars=240        -- absolute zoom-out ceiling (render budget)
Viewport.PixelsPerBar=7      -- readable 3+ px bodies, distinct wicks and space between candles
Viewport.RightMargin=3       -- empty bars to the right of the live candle
Viewport.EaseSeconds=0.07    -- auto-fit price-scale smoothing
Viewport.DefaultBars={Desktop=72,Mobile=36}

-- Practical zoom range: limited by the available history and by how many candles the plot can draw.
function Viewport.Limits(count,width)
 local render=math.clamp(math.floor((width or 800)/Viewport.PixelsPerBar),Viewport.MinBars+10,Viewport.MaxBars)
 local data=math.max(40,math.ceil(count*1.15)+Viewport.RightMargin+2)
 return Viewport.MinBars,math.max(Viewport.MinBars+2,math.min(render,data))
end
-- First index whose candle time is >= time (binary search; candles are time ordered).
local function lowerBound(candles,time)
 local lo,hi=1,#candles+1
 while lo<hi do local mid=(lo+hi)//2 if candles[mid].Time<time then lo=mid+1 else hi=mid end end
 return lo
end
Viewport.LowerBound=lowerBound

function Viewport.Resolve(state,candles,timeframe,tick,mobile,levels,width)
 if #candles==0 then return nil end
 local interval=Viewport.Seconds[timeframe]
 local minBars,maxBars=Viewport.Limits(#candles,width)
 state.Bars=math.clamp(state.Bars or (mobile and Viewport.DefaultBars.Mobile or Viewport.DefaultBars.Desktop),minBars,maxBars)
 state.Interval=interval
 local latest,earliest=candles[#candles].Time,candles[1].Time
 if state.Right==nil then state.Right=latest+Viewport.RightMargin*interval state.Follow=true end
 -- Following: new candles scroll the view by exactly the time they add. Detached: the view never moves.
 if state.Follow and state.Latest and latest~=state.Latest then state.Right+=latest-state.Latest end
 state.Latest=latest
 local maximum=latest+state.Bars*0.8*interval
 local minimum=math.min(earliest+math.min(6,state.Bars*0.5)*interval,maximum)
 state.Right=math.clamp(state.Right,minimum,maximum)
 local right=state.Right local left=right-state.Bars*interval
 -- One extra candle each side so partially visible bodies are drawn and clipped, not popped.
 local first=lowerBound(candles,left-interval) local last=lowerBound(candles,right+interval)-1
 local visible=table.move(candles,first,math.max(first-1,last),1,{})
 local low,high=math.huge,-math.huge
 for _,c in ipairs(visible)do
  if c.Time>=left-interval*0.5 and c.Time<=right+interval*0.5 then low=math.min(low,c.Low) high=math.max(high,c.High) end
 end
 if low==math.huge then local c=candles[math.clamp(first,1,#candles)] low=c.Low high=c.High end
 -- While following, keep the live price and the open position's levels in view.
 if state.Follow then for _,price in ipairs(levels or {})do low=math.min(low,price) high=math.max(high,price) end end
 local padding=math.max(tick*2,(high-low)*0.08)
 local targetLow,targetHigh=low-padding,high+padding
 state.TargetLow,state.TargetHigh=targetLow,targetHigh
 local auto=state.AutoY~=false
 local lo,hi
 if auto then
  if not state.ShowLow then state.ShowLow,state.ShowHigh=targetLow,targetHigh end
  lo,hi=state.ShowLow,state.ShowHigh
 else lo,hi=state.Low,state.High end
 if hi-lo<tick then local mid=(lo+hi)/2 lo,hi=mid-tick/2,mid+tick/2 end
 return {Left=left,Right=right,Low=lo,High=hi,Bars=state.Bars,Interval=interval,Data=visible,First=first,
  Earliest=earliest,Latest=latest,Minimum=minimum,Maximum=maximum,MinBars=minBars,MaxBars=maxBars,Tick=tick,
  Follow=state.Follow==true,AutoY=auto,TargetLow=targetLow,TargetHigh=targetHigh,
  Live=state.Follow==true and auto}
end
-- Eases the displayed auto-fit range toward its target. Returns true while still moving.
function Viewport.Ease(state,dt,snap)
 if state.AutoY==false or not state.TargetLow then return false end
 if snap or not state.ShowLow then state.ShowLow,state.ShowHigh=state.TargetLow,state.TargetHigh return false end
 local range=math.max(1e-9,state.TargetHigh-state.TargetLow)
 local dl,dh=state.TargetLow-state.ShowLow,state.TargetHigh-state.ShowHigh
 if math.abs(dl)<range*0.0005 and math.abs(dh)<range*0.0005 then
  state.ShowLow,state.ShowHigh=state.TargetLow,state.TargetHigh return false
 end
 local k=1-math.exp(-math.max(0,dt)/Viewport.EaseSeconds)
 state.ShowLow+=dl*k state.ShowHigh+=dh*k
 return true
end
function Viewport.TimeAt(view,fraction) return view.Left+(view.Right-view.Left)*fraction end
function Viewport.PriceAt(view,fraction) return view.High-(view.High-view.Low)*fraction end
function Viewport.X(view,time,width) return (time-view.Left)/(view.Right-view.Left)*width end
function Viewport.Y(view,price,height) return (view.High-price)/(view.High-view.Low)*height end
local function refollow(state)
 if state.Latest and state.Interval then state.Follow=state.Right>=state.Latest+state.Interval*0.5 end
end
-- Manual price scale: fix the current range so later changes are explicit.
local function manual(state,view)
 if state.AutoY~=false then state.AutoY=false state.Low,state.High=view.Low,view.High end
end
function Viewport.Pan(state,start,dx,dy,width,height)
 state.Right=math.clamp(start.Right-dx/math.max(1,width)*(start.Right-start.Left),math.min(start.Minimum,start.Maximum),start.Maximum)
 -- Auto-fit keeps the price axis fitted to the candles; a manual scale pans vertically with the pointer.
 if not start.AutoY then
  local shift=dy/math.max(1,height)*(start.High-start.Low)
  state.Low=start.Low+shift state.High=start.High+shift
 end
 refollow(state)
end
function Viewport.Zoom(state,view,factor,fraction)
 fraction=math.clamp(fraction,0,1)
 local bars=math.clamp(view.Bars*factor,view.MinBars or Viewport.MinBars,view.MaxBars or Viewport.MaxBars)
 local anchor=Viewport.TimeAt(view,fraction)
 state.Bars=bars state.Right=anchor+(1-fraction)*bars*view.Interval
 -- Zooming out reveals more history, not empty future: the right edge never moves past where it was
 -- (or the live candle's usual margin), so the extra room goes to older candles.
 if bars>view.Bars and view.Latest and view.Interval then
  state.Right=math.min(state.Right,math.max(view.Right,view.Latest+Viewport.RightMargin*view.Interval))
 end
 refollow(state)
end
-- Two-finger gesture: the time under the starting midpoint stays under the current midpoint.
function Viewport.Pinch(state,start,fromFraction,toFraction,ratio,dy,height)
 local bars=math.clamp(start.Bars*ratio,start.MinBars or Viewport.MinBars,start.MaxBars or Viewport.MaxBars)
 local anchor=Viewport.TimeAt(start,math.clamp(fromFraction,0,1))
 state.Bars=bars state.Right=anchor+(1-toFraction)*bars*start.Interval
 if not start.AutoY and dy then
  local shift=dy/math.max(1,height)*(start.High-start.Low)
  state.Low=start.Low+shift state.High=start.High+shift
 end
 refollow(state)
end
-- Y-axis drag: down expands the visible price range (candles shorter), up compresses it (taller).
function Viewport.ScalePrice(state,start,dy,height)
 local factor=math.exp(math.clamp(dy,-2000,2000)/math.max(120,height)*1.6)
 local mid=(start.Low+start.High)/2
 local half=math.clamp((start.High-start.Low)/2*factor,(start.Tick or 0.01)*2,math.max(1,math.abs(mid))*2)
 state.AutoY=false state.Low=mid-half state.High=mid+half
end
function Viewport.AutoFit(state)
 if state.AutoY==false and state.Low then state.ShowLow,state.ShowHigh=state.Low,state.High end
 state.AutoY=true state.Low=nil state.High=nil
end
-- Follow the live candle again at the current zoom. A manual scale is re-centred on the live price.
function Viewport.GoLive(state,price)
 if state.AutoY==false and state.Low and price then
  local half=(state.High-state.Low)/2 state.Low=price-half state.High=price+half
 end
 state.Right=nil state.Follow=true
end
function Viewport.Reset(state)
 table.clear(state)
end
Viewport.Manual=manual
local niceSteps={1,2,2.5,5}
-- Round-number price grid; every label is a multiple of the contract tick.
function Viewport.PriceTicks(low,high,tick,count)
 local range=math.max(high-low,tick) local raw=range/math.max(1,count)
 local magnitude=10^math.floor(math.log10(raw)) local step
 for _,m in ipairs(niceSteps)do if m*magnitude>=raw then step=m*magnitude break end end
 step=step or 10*magnitude
 step=math.max(tick,math.ceil(step/tick-1e-9)*tick)
 local ticks={} local p=math.ceil(low/step-1e-9)*step
 while p<=high+1e-9 and #ticks<64 do table.insert(ticks,p) p+=step end
 return ticks,step
end
local timeSteps={60,120,300,600,900,1800,3600,7200,10800,14400,21600,43200,86400,172800,432000,864000,2592000}
function Viewport.TimeTicks(left,right,interval,count)
 local raw=(right-left)/math.max(1,count) local step=timeSteps[#timeSteps]
 for _,s in ipairs(timeSteps)do if s>=interval and s>=raw then step=s break end end
 local ticks={} local t=math.ceil(left/step)*step
 while t<=right and #ticks<64 do table.insert(ticks,t) t+=step end
 return ticks,step
end
return Viewport
