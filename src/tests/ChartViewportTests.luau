local V=require(script.Parent.ChartViewport)

return function()

 local checks=0

 local function check(ok,message) checks+=1 assert(ok,message) end

 local function series(n,interval)

  local c={} for i=1,n do local o=100+math.sin(i/7)*5 c[i]={Time=(i-1)*(interval or 60),Open=o,High=o+2,Low=o-2,Close=o+(i%3==0 and -1 or 1),Volume=i} end return c

 end

 local candles=series(700)

 -- Deep zoom-out is limited by history and by plot width (7 px per candle).

 local minBars,maxBars=V.Limits(#candles,1266)

 check(minBars==10 and maxBars==math.floor(1266/7),"700 candles: zoom-out respects readable spacing: "..maxBars)

 local _,wide=V.Limits(1440,1266) check(wide==math.floor(1266/7),"Long history: zoom-out is limited by plot width at 7 px per candle: "..wide)

 local _,narrow=V.Limits(1440,500) check(narrow==math.floor(500/7),"Narrow plots still allow readable spacing")

 local _,cap=V.Limits(5000,4000) check(cap==V.MaxBars,"Absolute render ceiling")

 local _,small=V.Limits(30,1266) check(small==math.max(40,math.ceil(30*1.15)+5),"Zoom limits follow available history")

 local state={} local live=V.Resolve(state,candles,"1m",0.25,false,{101},1266)

 check(live.Live and live.Follow and #live.Data<#candles,"Starts following live with a navigable window")

 for _=1,40 do V.Zoom(state,live,1.4,0.5) live=V.Resolve(state,candles,"1m",0.25,false,{101},1266) end

 check(live.Bars==maxBars,"Zoom out reaches the practical limit and stops")

 check(live.Right<=candles[#candles].Time+V.RightMargin*60+1e-6 and #live.Data<=maxBars+3 and live.Interval==60,"Zoom keeps real one-minute candles and a bounded readable count")

 for _=1,40 do V.Zoom(state,live,0.5,0.5) live=V.Resolve(state,candles,"1m",0.25,false,{101},1266) end

 check(live.Bars==minBars,"Zoom in stops at the minimum")

 -- Cursor-anchored zoom keeps the time under the pointer fixed (away from bounds).

 V.Reset(state) local v=V.Resolve(state,candles,"1m",0.25,false,{101},1266)

 V.Pan(state,v,400,0,1266,300) v=V.Resolve(state,candles,"1m",0.25,false,{101},1266)

 for _,f in ipairs({0.1,0.37,0.8})do

  local anchor=V.TimeAt(v,f) V.Zoom(state,v,1.3,f) local z=V.Resolve(state,candles,"1m",0.25,false,{101},1266)

  check(math.abs(V.TimeAt(z,f)-anchor)<1e-6,"Zoom out keeps the pointer's time at "..f)

  anchor=V.TimeAt(z,f) V.Zoom(state,z,0.7,f) v=V.Resolve(state,candles,"1m",0.25,false,{101},1266)

  check(math.abs(V.TimeAt(v,f)-anchor)<1e-6,"Zoom in keeps the pointer's time at "..f)

 end

 -- Detached viewport is preserved when candles arrive; following scrolls with them.

 check(not v.Follow,"Panning into history stops following")

 local right,low=v.Right,v.Low

 local grown=table.clone(candles) table.insert(grown,{Time=700*60,Open=100,High=130,Low=90,Close=120,Volume=5})

 local after=V.Resolve(state,grown,"1m",0.25,false,{120},1266)

 check(after.Right==right and after.Bars==v.Bars,"New candles do not move a detached viewport")

 local follow={} local f1=V.Resolve(follow,candles,"1m",0.25,false,{101},1266)

 local f2=V.Resolve(follow,grown,"1m",0.25,false,{120},1266)

 check(f2.Right-f1.Right==60 and f2.Follow,"Following scrolls by exactly the new candle")

 -- Auto-fit pan moves time only; manual scale pans price too.

 local pan={} local p0=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 V.Pan(pan,p0,100,80,1266,300) local p1=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(p1.AutoY and p1.Right<p0.Right,"Auto-fit drag pans time and keeps auto scale")

 -- Y-axis drag: up = taller candles (narrower range), down = shorter; persists until auto-fit.

 V.ScalePrice(pan,p1,-60,300) local tall=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(not tall.AutoY and tall.High-tall.Low<p1.High-p1.Low,"Dragging the axis up compresses the range")

 V.Pan(pan,tall,-30,40,1266,300) local moved=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(math.abs((moved.High-moved.Low)-(tall.High-tall.Low))<1e-9 and moved.Low>tall.Low,"Manual scale survives panning and pans price")

 local grown2=table.clone(candles) table.insert(grown2,{Time=700*60,Open=100,High=400,Low=10,Close=120,Volume=5})

 local still=V.Resolve(pan,grown2,"1m",0.25,false,{120},1266)

 check(still.Low==moved.Low and still.High==moved.High,"Manual scale persists across live updates")

 V.ScalePrice(pan,moved,80,300) local short=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(short.High-short.Low>moved.High-moved.Low,"Dragging the axis down expands the range")

 V.AutoFit(pan) local fitted=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(fitted.AutoY and fitted.Low==short.Low,"Auto-fit starts from the current scale")

 for _=1,200 do V.Ease(pan,1/60) end fitted=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(math.abs(fitted.Low-fitted.TargetLow)<1e-9 and math.abs(fitted.High-fitted.TargetHigh)<1e-9,"Auto-fit settles exactly on the visible candles")

 local lo,hi=math.huge,-math.huge

 for _,c in ipairs(fitted.Data)do if c.Time>=fitted.Left-30 and c.Time<=fitted.Right+30 then lo=math.min(lo,c.Low) hi=math.max(hi,c.High)end end

 check(fitted.Low<lo and fitted.High>hi,"Auto-fit contains every visible candle")

 -- Go to live keeps the zoom; reset restores defaults.

 V.Zoom(pan,fitted,1.5,0.5) local zoomed=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 V.Pan(pan,zoomed,600,0,1266,300) zoomed=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 V.GoLive(pan,101) local back=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(back.Follow and back.Bars==zoomed.Bars and back.Right==candles[#candles].Time+V.RightMargin*60,"Go to live keeps zoom and follows")

 V.Reset(pan) local reset=V.Resolve(pan,candles,"1m",0.25,false,{101},1266)

 check(reset.Bars==V.DefaultBars.Desktop and reset.Live,"Reset view restores default zoom, auto-fit and live")

 -- Pinch keeps the time under the start midpoint under the current midpoint.

 local pinch={} local pv=V.Resolve(pinch,candles,"1m",0.25,true,{101},360)

 local anchor=V.TimeAt(pv,0.4) V.Pinch(pinch,pv,0.4,0.55,0.6,0,200)

 local pz=V.Resolve(pinch,candles,"1m",0.25,true,{101},360)

 check(math.abs(V.TimeAt(pz,0.55)-anchor)<1e-6 and pz.Bars<pv.Bars,"Pinch zoom anchors to the midpoint")

 -- Bounds and degenerate data.

 V.Pan(state,v,-1e8,0,1266,300) local b=V.Resolve(state,candles,"1m",0.25,false,{101},1266) check(b.Right<=b.Maximum,"Right bound")

 V.Pan(state,b,1e8,0,1266,300) b=V.Resolve(state,candles,"1m",0.25,false,{101},1266) check(b.Right>=b.Minimum and #b.Data>0,"Left bound keeps candles visible")

 local one=V.Resolve({},{{Time=0,Open=100,High=100,Low=100,Close=100,Volume=1}},"1D",0.25,false,{100},500)

 check(one.High>one.Low and one.Right>one.Left,"Single flat candle has a valid view")

 -- Ticks are round multiples of the tick size and inside the range.

 local ticks,step=V.PriceTicks(5801.3,5843.9,0.25,6)

 check(step%0.25==0 and #ticks>=3 and ticks[1]>=5801.3 and ticks[#ticks]<=5843.9,"Price ticks")

 for _,t in ipairs(ticks)do check(math.abs(t/step-math.round(t/step))<1e-6,"Price ticks are aligned") end

 local tt,ts=V.TimeTicks(3000,9000,60,6) check(ts>=60 and tt[1]%ts==0,"Time ticks aligned")

 check(candles[1].Time==0 and candles[700].Time==699*60,"Navigation never mutates candles")

 -- Reproduce the actual saved BX gap: trading stopped after 2854800's
 -- candle and resumed in 2901600's bucket. Preserve both real executions.
 local sparse={
  {Time=2854800,Open=5755.5,High=5788.25,Low=5754,Close=5787.75,Volume=147},
  {Time=2901600,Open=5787.75,High=5798,Low=5787.75,Close=5798,Volume=132},
  {Time=2902500,Open=5798,High=5798,Low=5757.75,Close=5769.25,Volume=315},
 }
 local gapView=V.Resolve({Bars=72},sparse,"15m",.25,false,{5769.25},1266)
 check(#gapView.Gaps==1,"Saved BX gap is explained on the chart")
 local gap=gapView.Gaps[1]
 check(gap.Start==2855700 and gap.Finish==2901600 and gap.Seconds==45900 and gap.Price==5787.75,"Gap uses actual empty buckets and the last executed price")
 check(V.GapDuration(gap.Seconds)=="12h 45m","Gap duration describes simulated chart time")
 check(V.GapAt(gapView.Gaps,gap.Start)==gap and V.GapAt(gapView.Gaps,gap.Finish)==nil,"Hover identifies inactivity without stealing the resumed candle")
 check(#V.Gaps(sparse,900,2860000,2869000)==1,"Gap is found when both bounding candles are off screen")
 local inside=V.Resolve({Right=2869000,Bars=10,Follow=false},sparse,"15m",.25,false,{},1266)
 check(#inside.Data==0 and #inside.Gaps==1 and inside.Low<5787.75 and inside.High>5787.75,"An empty viewport fits the carried last trade instead of implying a reset")
 check(#V.Gaps(sparse,900,2901600,2903400)==0,"Adjacent traded candles have no false gap")
 check(#V.Gaps(sparse,900,2854800,2855700)==0,"Trading candle is not labeled inactive")
 check(#V.Gaps(sparse,900,2903400,2907000)==0,"Unconfirmed future space is not labeled historical inactivity")
 check(#V.Gaps({},60,0,100)==0 and #V.Gaps({sparse[1]},900,0,3000000)==0,"Insufficient history does not fabricate a gap")
 check(#sparse==3 and sparse[1].Close==5787.75 and sparse[1].Volume==147 and sparse[2].Time==2901600 and sparse[2].Volume==132,"Gap rendering preserves saved OHLC, timestamps and volume")
 local manualGap=V.Resolve({Right=2869000,Bars=10,Follow=false,AutoY=false,Low=5000,High=6000},sparse,"15m",.25,false,{},1266)
 check(manualGap.Low==5000 and manualGap.High==6000 and manualGap.Right==2869000,"Inactivity markers preserve manual scale and pan")

 return {Passed=true,Cases=checks,Checks="Zoom limits, cursor/pinch anchoring, follow vs detached, auto-fit pan, manual Y scale, auto-fit easing, go live, reset, bounds, ticks"}

end

