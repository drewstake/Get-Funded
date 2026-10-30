-- Isolated presentation fixture: real ChartView input handlers and native GUI rendering.
-- No trading requests, profiles, or persistent state. Run in Studio Edit mode.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="ChartInteractionsQA";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="ChartInteractionsQA";gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI)
 local Tools=require(shared.ChartTools)
 local Viewport=require(shared.ChartViewport)
 local config=require(shared.MarketConfig)
 local candles={}
 for i=1,160 do
  local open=5820+math.floor(math.sin(i*.17)*28)*.25
  candles[i]={Time=i*60,Open=open,High=open+2,Low=open-2,Close=open+1,Volume=50}
 end
 local cache,quotes={},{}
 for _,key in ipairs(config.ContractOrder)do
  quotes[key]={Last=5820,Open=5820,Bid=5819.75,Ask=5820.25,Spread=.5}
  for _,tf in ipairs(config.Timeframes)do cache[key..":"..tf[1]]=candles end
 end
 local holder=Instance.new("Frame");holder.Size=UDim2.fromOffset(1280,800);holder.Parent=gui
 ctl=UI.Mount(holder,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=9600,Step=1}})
 local chart=ctl.Chart;local s=ctl.State
 local report={Passed=true,Checks={},Tools={}}
 local function check(value,message)assert(value,message);table.insert(report.Checks,message)end
 local function near(a,b)return math.abs(a-b)<.01 end
 check(chart.Geometry~=nil,"Chart mounts with candle data")
 chart.Ctx.Options.Preview=false
 chart.Ctx.onIdle=function()end;chart.Ctx.refresh=function()end
 local panel=ctl.Root.Canvas.Chart
 local function paint()
  chart.Dirty=true
  chart:Paint(panel.Position.X.Offset,panel.Position.Y.Offset,panel.Size.X.Offset,panel.Size.Y.Offset,false,false,true)
 end
 local state=chart.Geometry.State
 state.Right=9600+30*60;state.Follow=false;state.Bars=72;state.AutoY=false;state.Low=5805;state.High=5835
 paint()
 local g=chart.Geometry
 local function position(x,y)return g.Plot.AbsolutePosition+Vector2.new(g.Left+x,g.Top+y)end
 local function down(x,y)
  chart.Hover=position(x,y)
  chart:Began({UserInputType=Enum.UserInputType.MouseButton1,Position=chart.Hover})
 end
 local function move(x,y)
  chart.Hover=position(x,y)
  chart:Changed({UserInputType=Enum.UserInputType.MouseMovement,Position=chart.Hover})
 end
 local function up()chart:Ended({UserInputType=Enum.UserInputType.MouseButton1,UserInputState=Enum.UserInputState.End})end
 local function reset(tool,magnet)
  chart:Cancel();table.clear(s.Drawings);chart.Selected=nil;s.Tool=tool;s.Magnet=magnet
 end
 local function oracle(x,y)
  local best,dist=nil,math.huge
  for _,c in ipairs(g.Data)do for _,field in ipairs({"Open","High","Low","Close"})do
   local d=(g.X(c.Time)-x)^2+(g.Y(c[field])-y)^2
   if d<=dist then best={Time=c.Time,Price=c[field]};dist=d end
  end end
  return best,math.sqrt(dist)
 end
 for _,tool in ipairs({"Line","Trend","Rect"})do
  reset(tool,true)
  local x,y=g.Width*.94,g.Height*.12
  local expected,distance=oracle(x,y)
  check(distance>24,tool..": target well beyond the old snap radius")
  down(x,y)
  local first=tool=="Line" and chart.Drag.Point or chart.Placement.A
  check(first.Time==expected.Time and first.Price==expected.Price,tool..": first anchor snaps globally")
  chart:PaintOverlay(g)
  check(ctl.Root:GetAttribute("SnapTarget")~=nil and g.Plot.PriceLayer.DrawingLayer.SnapTarget.Visible,tool..": visible snap target")
  local x2,y2=g.Width*.35,g.Height*.88
  move(x2,y2);local ending=oracle(x2,y2)
  up()
  local d=s.Drawings[1]
  check(d~=nil,tool..": placement commits through input handlers")
  local t,p=tool=="Line"and d.T1 or d.T2,tool=="Line"and d.P1 or d.P2
  check(t==ending.Time and p==ending.Price,tool..": moving active anchor uses the same snap")
  report.Tools[tool]="Creation, movement, and target indicator passed"
 end
 -- Existing drawing anchors use the same unrestricted target as placement.
 for _,kind in ipairs({"Line","Trend","Rect"})do
  reset("Pan",true)
  local d=Tools.New(kind,{Time=9800,Price=5827},{Time=10400,Price=5815},s.Contract,s.Timeframe)
  table.insert(s.Drawings,d);chart.Selected=d.Id
  local original=Tools.Copy(d)
  local parts=kind=="Line"and {"Move"}or kind=="Trend"and {"P1","P2"}or {"Corner1","Corner2","Corner3","Corner4"}
  for _,part in ipairs(parts)do
   local hx,hy=g.Width*.8,g.Y(d.P1)
   for _,pt in ipairs(Tools.Points(d))do if pt.Part==part then hx,hy=g.X(pt.Time),g.Y(pt.Price)end end
   down(hx,hy);check(chart.Drag and chart.Drag.Part==part,kind..": snap edit hit "..part)
   local x,y=g.Width*.3,g.Height*.05
   move(x,y)
   local expected=chart:DrawingPointAt(x,y,false)
   check(expected.Snap~=nil,kind..": snap edit has target "..part)
   up()
   local fields=part=="Move"and {"T1","P1"}or part=="P1"and {"T1","P1"}or part=="P2"and {"T2","P2"}or Tools.CornerFields[tonumber(part:match("%d"))]
   check(near(d[fields[2]],expected.Price)and(kind=="Line"or near(d[fields[1]],expected.Time)),kind..": edited anchor lands on OHLC "..part)
   for k,v in pairs(original)do d[k]=v end
  end
 end
 -- Cursor time is independent of the magnet and keeps increasing beyond the last candle.
 for _,magnet in ipairs({false,true})do
  reset("Crosshair",magnet)
  local last=9600
  for _,fraction in ipairs({.75,.85,.98})do
   local x=g.Width*fraction;chart.Hover=position(x,g.Height*.5);chart:PaintOverlay(g)
   local time=ctl.Root:GetAttribute("CrosshairTime")
   check(time>last and near(time,Viewport.TimeAt(g.View,fraction)),"Future crosshair time, magnet="..tostring(magnet)..", x="..fraction)
   check(g.Plot.CrossV.Position.X.Offset==g.Left+math.floor(x+.5),"Future crosshair follows pointer at "..fraction)
   local expected=string.format("%02d:%02d",math.floor(time/3600)%24,math.floor(time/60)%60)
   check(g.Plot.CrossTime.Time.Text==expected,"Future x-axis time label at "..fraction)
   last=time
  end
 end
 -- Mouse creation and all resize handles beyond the latest candle, both off and bypassed.
 local bypassMethod=chart.SnapBypassed
 for _,bypass in ipairs({false,true})do
  chart.SnapBypassed=function()return bypass end
  for _,tool in ipairs({"Line","Trend","Rect"})do
   reset(tool,bypass)
   local x,y=g.Width*.73,g.Height*.25
   down(x,y);move(g.Width*.85,g.Height*.65);up()
   local d=s.Drawings[1]
   check(d and d.T1>9600 and (tool=="Line"or d.T2>9600),tool..": future creation, bypass="..tostring(bypass))
   if tool~="Line"then
    local parts=tool=="Trend"and {"P1","P2"}or {"Corner1","Corner2","Corner3","Corner4","Extend"}
    for _,part in ipairs(parts)do
     local original=Tools.Copy(d);local hx,hy
     if part=="Extend"then hx,hy=Tools.ExtendPoint(d,g.X,g.Y)
     else for _,pt in ipairs(Tools.Points(d))do if pt.Part==part then hx,hy=g.X(pt.Time),g.Y(pt.Price)end end end
     s.Tool="Pan";chart.Selected=d.Id;down(hx,hy)
     check(chart.Drag and chart.Drag.Kind=="Edit"and chart.Drag.Part==part,tool..": hit "..part)
     local targetX=g.Width*.95
     move(targetX,g.Height*.44);up()
     local field=part=="Extend"and(original.T2>=original.T1 and "T2"or"T1")or part=="P1"and"T1"or part=="P2"and"T2"or Tools.CornerFields[tonumber(part:match("%d"))][1]
     check(d[field]>9600 and near(d[field],Viewport.TimeAt(g.View,.95)),tool..": future resize "..part..", bypass="..tostring(bypass))
     for k,v in pairs(original)do d[k]=v end
    end
   end
   -- Whole shape drags retain their size and can move farther into future space.
   s.Tool="Pan";chart.Selected=d.Id
   local original=Tools.Copy(d)
   local hx=tool=="Line"and g.Width*.78 or (g.X(d.T1)+g.X(d.T2))/2
   local hy=tool=="Line"and g.Y(d.P1)or (g.Y(d.P1)+g.Y(d.P2))/2
   down(hx,hy);check(chart.Drag and chart.Drag.Kind=="Edit",tool..": body drag begins")
   move(hx+g.Width*.05,hy);up()
   check(d.T1>original.T1 and (not d.T2 or near(d.T2-d.T1,original.T2-original.T1)),tool..": future body drag preserves width")
  end
 end
 -- Alt pressed/released during a moved gesture updates its endpoint without another mouse move.
 reset("Trend",true)
 local bypass=false;chart.SnapBypassed=function()return bypass end
 down(g.Width*.4,g.Height*.3);move(g.Width*.9,g.Height*.6)
 check(chart.Placement.B.Snap~=nil,"Active gesture starts snapped")
 bypass=true;chart:ModifierChanged()
 check(chart.Placement.B.Time>9600 and not chart.Placement.B.Snap,"Alt frees an active endpoint immediately")
 bypass=false;chart:ModifierChanged()
 check(chart.Placement.B.Snap~=nil,"Releasing Alt restores snapping immediately")
 chart:Cancel();chart.SnapBypassed=bypassMethod
 -- Modifier regressions use the real key handlers, including stationary changes.
 local function key(code,held)
  if held then chart:KeyBegan({KeyCode=code})else chart:KeyEnded({KeyCode=code})end
  chart:PaintOverlay(g)
 end
 local ctrl,otherCtrl=Enum.KeyCode.LeftControl,Enum.KeyCode.RightControl
 local shift,otherShift=Enum.KeyCode.LeftShift,Enum.KeyCode.RightShift
 for _,magnet in ipairs({false,true})do
  reset("Rect",magnet)
  move(g.Width*.3,g.Height*.2);chart:PaintOverlay(g)
  local locked=ctl.Root:GetAttribute("CrosshairTime")
  local lockedX=g.Plot.CrossV.Position.X.Offset
  key(ctrl,true)
  check(not chart:MagnetOn(),"Rectangle Ctrl reserves the modifier even with magnet="..tostring(magnet))
  move(g.Width*.6,g.Height*.4);chart:PaintOverlay(g)
  check(near(ctl.Root:GetAttribute("CrosshairTime"),locked) and g.Plot.CrossV.Position.X.Offset==lockedX,"Rectangle Ctrl freezes vertical crosshair before placement")
  check(g.Plot.CrossH.Position.Y.Offset==g.Top+math.floor(g.Height*.4+.5),"Rectangle Ctrl leaves horizontal crosshair free")
  down(g.Width*.6,g.Height*.4)
  check(near(chart.Placement.A.Time,locked),"Rectangle first click uses displayed locked time")
  key(ctrl,false)
  check(near(ctl.Root:GetAttribute("CrosshairTime"),Viewport.TimeAt(g.View,.6)),"Ctrl release immediately resumes crosshair without motion")
  move(g.Width*.72,g.Height*.65)
  key(ctrl,true)
  local secondTime=chart.Placement.B.Time
  key(otherCtrl,true);key(ctrl,false)
  move(g.Width*.9,g.Height*.8);chart:PaintOverlay(g)
  check(near(chart.Placement.B.Time,secondTime) and chart.Ctrl,"Either Ctrl key maintains the lock until both released")
  check(near(chart.Placement.B.Price,chart:PointAt(g.Width*.9,g.Height*.8,false).Price),"Rectangle endpoint price follows mouse during lock")
  check(g.X(chart.Placement.B.Time)==ctl.Root:GetAttribute("CrosshairX"),"Rectangle preview time aligns with displayed crosshair")
  local preview=Tools.Copy(chart.Placement.B)
  up()
  local d=s.Drawings[1]
  check(d and near(d.T2,preview.Time) and d.P2==preview.Price,"Rectangle drag commit matches locked preview")
  key(otherCtrl,false)
  check(chart.RectangleLockTime==nil,"Rectangle commit clears old lock")
 end
 -- Two-click rectangle: release/repress Ctrl while waiting for the second click.
 reset("Rect",false);down(g.Width*.2,g.Height*.2);up()
 move(g.Width*.6,g.Height*.5);chart:PaintOverlay(g);key(ctrl,true)
 local locked=chart.Placement.B.Time
 move(g.Width*.85,g.Height*.75);chart:PaintOverlay(g)
 check(near(chart.Placement.B.Time,locked),"Two-click rectangle preview follows lock")
 key(ctrl,false)
 check(near(chart.Placement.B.Time,Viewport.TimeAt(g.View,.85)),"Waiting rectangle releases Ctrl without mouse movement")
 key(ctrl,true);move(g.Width*.95,g.Height*.8);chart:PaintOverlay(g)
 local preview=Tools.Copy(chart.Placement.B)
 down(g.Width*.95,g.Height*.8);up();key(ctrl,false)
 check(s.Drawings[1] and near(s.Drawings[1].T2,preview.Time) and s.Drawings[1].P2==preview.Price,"Two-click rectangle commit matches preview")
 -- Both trendline creation modes, both Shift keys, with/without the magnet.
 for _,twoClick in ipairs({false,true})do for _,magnet in ipairs({false,true})do
  reset("Trend",magnet);down(g.Width*.25,g.Height*.25)
  if twoClick then up()end
  move(g.Width*.6,g.Height*.7);chart:PaintOverlay(g)
  local free=Tools.Copy(chart.Placement.B)
  check(free.Price~=chart.Placement.A.Price,"Trend starts unrestricted")
  key(shift,true)
  check(chart.Placement.B.Price==chart.Placement.A.Price,"Shift makes active trend horizontal without mouse movement")
  key(otherShift,true);key(shift,false)
  move(g.Width*.8,g.Height*.9);chart:PaintOverlay(g)
  check(chart.Placement.B.Price==chart.Placement.A.Price and chart.Shift,"Remaining Shift keeps price fixed")
  local freeEnd=chart:PointAt(g.Width*.8,g.Height*.9,true)
  check(near(chart.Placement.B.Time,freeEnd.Time),"Shift leaves trend endpoint time following mouse")
  local line=g.Plot.PriceLayer.DrawingLayer.UserTrend
  check(line.Visible and near(line.Rotation,0),"Native trend preview is perfectly horizontal")
  key(otherShift,false)
  check(chart.Placement.B.Price==freeEnd.Price,"Shift release restores unconstrained endpoint without motion")
  key(shift,true)
  local endpoint=Tools.Copy(chart.Placement.B)
  if twoClick then down(g.Width*.8,g.Height*.9)end
  up();key(shift,false)
  local d=s.Drawings[1]
  check(d and d.P1==d.P2 and d.P2==endpoint.Price and near(d.T2,endpoint.Time),"Completed horizontal trend matches preview, twoClick="..tostring(twoClick)..", magnet="..tostring(magnet))
 end end
 for _,twoClick in ipairs({false,true})do
  reset("Trend",false);down(g.Width*.2,g.Height*.2);if twoClick then up()end
  move(g.Width*.65,g.Height*.7);key(shift,true);key(shift,false)
  local endpoint=Tools.Copy(chart.Placement.B)
  if twoClick then down(g.Width*.65,g.Height*.7)end
  up()
  check(s.Drawings[1].P2==endpoint.Price and s.Drawings[1].P2~=s.Drawings[1].P1,"Released Shift commits unrestricted line, twoClick="..tostring(twoClick))
 end
 reset("Rect",false);move(g.Width*.4,g.Height*.3);key(ctrl,true);down(g.Width*.4,g.Height*.3)
 chart:FocusLost()
 check(not chart.Ctrl and not chart.Shift and chart.RectangleLockTime==nil and not chart.Placement,"Focus loss clears modifiers, lock and active placement")
 reset("Trend",false);key(ctrl,true)
 check(chart:MagnetOn(),"Ctrl still temporarily enables magnet for other tools")
 key(ctrl,false)
 check(not chart:MagnetOn(),"Other tools restore magnet on Ctrl release")
 -- Paint native candle objects at dense, fractional and maximum zoom. Measure full
 -- silhouettes (including bevels) rather than repeating the renderer's width formula.
 reset("Pan",false)
 report.CandleZoom={}
 for _,width in ipairs({390,640,1280,1920,2560})do
  for _,bars in ipairs({10,10.25,15.7,24,36.3,72,110,160})do
   state.Bars=bars;state.Right=9500;state.Follow=false
   chart.Dirty=true;chart:Paint(0,0,width,800,false,false,true);g=chart.Geometry
   local strip=g.Plot.PriceLayer.CandleStrip
   local bounds={}
   for _,o in ipairs(strip:GetChildren())do
    if o.Name=="Candle" and o.Visible then
     local t=o:GetAttribute("Time")
     local lo,hi=o.Position.X.Offset,o.Position.X.Offset+o.Size.X.Offset
     for _,edge in ipairs(strip:GetChildren())do
      if edge.Name=="CandleEdge" and edge.Visible and math.abs(edge.Position.X.Offset+edge.Size.X.Offset/2-(lo+hi)/2)<.1 then
       lo=math.min(lo,edge.Position.X.Offset);hi=math.max(hi,edge.Position.X.Offset+edge.Size.X.Offset)
      end
     end
     table.insert(bounds,{Time=t,Left=lo,Right=hi,Width=o.Size.X.Offset})
    end
   end
   table.sort(bounds,function(a,b)return a.Time<b.Time end)
   local minGap,maxGap=math.huge,0
   for i=2,#bounds do
    local gap=bounds[i].Left-bounds[i-1].Right
    minGap=math.min(minGap,gap);maxGap=math.max(maxGap,gap)
   end
   check(#bounds>2 and minGap>=3 and maxGap<=5,"Candle silhouettes have small nonoverlapping gaps: width="..width..", bars="..bars..", gaps="..minGap.."-"..maxGap)
   if width>=1280 and bars<=10.25 then check(bounds[2].Width>29,"Zoomed candles exceed old 29px cap")end
   table.insert(report.CandleZoom,{Width=width,Bars=g.State.Bars,MinGap=minGap,MaxGap=maxGap,BodyWidth=bounds[2].Width})
  end
 end
 check(not ctl.Root:GetAttribute("ChartError"),"No chart rendering errors")
 report.Cases=#report.Checks
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end
gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result

