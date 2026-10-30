-- Isolated Studio Edit fixture using rendered markers and real chart input handlers.
-- Trading methods are captured locally; no remote requests or persistent account changes.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="PositionProtectionDragQA";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="PositionProtectionDragQA";gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI)
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
 local chart,s=ctl.Chart,ctl.State
 local session=chart.Ctx.Session
 local report={Passed=true,Checks={}}
 local function check(value,message)assert(value,message);table.insert(report.Checks,message)end
 chart.Ctx.Options.Preview=false
 chart.Ctx.onIdle=function()end;chart.Ctx.refresh=function()end;chart.Ctx.toast=function()end
 local requests={}
 session.AmendProtection=function(_,contract,id,field,price,original,quantity)
  table.insert(requests,{Kind="Protection",Field=field,Price=price,Original=original,Quantity=quantity})
  return false,"Captured by fixture"
 end
 session.AmendOrder=function()table.insert(requests,{Kind="Order"});return false,"Captured by fixture"end
 session.CreateProtection=function(_,contract,id,field,price,quantity)table.insert(requests,{Kind="Create",Field=field,Price=price,Quantity=quantity});return false,"Captured by fixture"end
 session.Cancel=function()table.insert(requests,{Kind="Cancel"});return false,"Captured by fixture"end
 local held={Id="axis-fixture",Entry=5820,Stop=5810,Target=5830,Quantity=305,Direction=1}
 session.Positions={[s.Contract]=held};session.Orders={};session.AccountKey="axis-fixture"
 s.Levels=true;s.Tool="Pan";s.Overlay=nil;s.Sheet=nil
 local g,state
 local function reset(width,height,mobile)
  chart:FocusLost();chart.LastAxisTap=nil;chart.Pending=nil;chart.OrderPending=nil
  table.clear(requests);session.Orders={}
  state=chart.Geometry.State
  state.Right=11400;state.Follow=false;state.Bars=72;state.AutoY=false
  state.Low=5800;state.High=5840;state.ShowLow=5800;state.ShowHigh=5840
  chart.Dirty=true;chart:Paint(0,0,width,height,mobile,false,true);g=chart.Geometry
 end
 local function position(x,y)return g.Plot.AbsolutePosition+Vector2.new(g.Left+x,g.Top+y)end
 local function down(kind,x,y)
  local ev={UserInputType=kind,Position=position(x,y)};chart:Began(ev);return ev
 end
 local function move(ev,x,y)
  ev.Position=position(x,y)
  chart:Changed(ev.UserInputType==Enum.UserInputType.Touch and ev or {UserInputType=Enum.UserInputType.MouseMovement,Position=ev.Position})
 end
 local function up(ev)
  ev.UserInputState=Enum.UserInputState.End;chart:Ended(ev)
 end

 for _,layout in ipairs({{390,650,true},{844,300,true},{1280,800,false}})do
  for _,kind in ipairs({Enum.UserInputType.Touch,Enum.UserInputType.MouseButton1})do
   for _,side in ipairs({1,-1})do
    for _,field in ipairs({"Stop","Target"})do
     for _,existing in ipairs({true,false})do
      held.Direction=side;held.Quantity=305;held.Entry=5820
      held.Stop=5820-side*10;held.Target=5820+side*10
      if not existing then held[field]=nil end
      reset(table.unpack(layout))
      local marker=assert(chart.EntryMarker)
      local x,y=marker.X+marker.W/2,marker.Y+marker.H/2
      local ev=down(kind,x,y)
      check(chart.Drag and chart.Drag.FromEntry,"Position label starts protection drag with either or both levels present")
      local dy=(field=="Stop"and 1 or -1)*side*60
      move(ev,x,y+dy)
      check(chart.Drag.Field==field and chart.Drag.Creating==not existing,"Direction selects the correct field and create/amend route")
      chart:Paint(0,0,layout[1],layout[2],layout[3],false,true);g=chart.Geometry
      up(ev)
      check(#requests==1 and requests[1].Field==field and requests[1].Quantity==305,"Release sends exactly one quantity-checked protection request")
      check(requests[1].Kind==(existing and "Protection"or "Create"),"Existing levels are amended; missing levels are created")
      if existing then check(requests[1].Original==held[field],"Replacement uses the original protection price, not entry")end
     end
    end
   end
   held.Direction=1;held.Stop=5819.75;held.Target=5830;held.Quantity=305
   reset(table.unpack(layout))
   local marker=chart.EntryMarker;local x,y=marker.X+marker.W/2,marker.Y+marker.H/2
   local ev=down(kind,x,y);check(chart.Drag.FromEntry,"Entry label takes precedence over nearby stop line")
   move(ev,x,y+60);check(chart.Drag.Field=="Stop","Downward drag selects stop")
   move(ev,x,y-60);check(chart.Drag.Field=="Target","Crossing entry switches to target")
   up(ev);check(#requests==1 and requests[1].Field=="Target","Only final selected field is submitted")
   reset(table.unpack(layout));marker=chart.EntryMarker;x=marker.X+marker.W/2;y=marker.Y+marker.H/2
   ev=down(kind,x,y);up(ev);check(#requests==0,"Click without drag sends nothing")
   reset(table.unpack(layout));marker=chart.EntryMarker;x=marker.X+marker.W/2;y=marker.Y+marker.H/2
   ev=down(kind,x,y);move(ev,x,y+60);held.Quantity=306
   check(chart:OnMarketUpdate()~=nil and not chart.Drag,"Size change during entry-label drag cancels stale gesture")
   up(ev);check(#requests==0,"Stale drag never submits")
   held.Quantity=305
   reset(table.unpack(layout));marker=chart.EntryMarker;x=marker.X+marker.W/2;y=marker.Y+marker.H/2
   ev=down(kind,x,y);move(ev,x,y+60);chart:FocusLost();up(ev)
   check(#requests==0,"Losing focus cancels without moving protection")
  end
 end
 -- A partial target keeps both markers draggable; snapshot changes cancel stale gestures.
 for _,kind in ipairs({Enum.UserInputType.Touch,Enum.UserInputType.MouseButton1})do
  for _,field in ipairs({"Stop","Target"})do
   held.Direction=1;held.Quantity=3;held.Entry=5820;held.Stop=5810;held.Target=5830
   held.Triggered="Take profit";held.TargetFilled=2;held.ProtectionEditable=true
   reset(1280,800,false)
   local hit;for _,h in ipairs(g.ProtectionHits)do if h.Field==field then hit=h end end
   check(hit~=nil,"Partially filled TP retains both protection markers")
   local x,y=30,hit.Y
   local ev=down(kind,x,y)
   check(chart.Drag and chart.Drag.Kind=="Protection"and chart.Drag.Field==field,"Partial TP allows direct "..field.." drag")
   move(ev,x,y-12);chart:OnMarketUpdate()
   check(chart.Drag~=nil,"Unchanged partial TP snapshot does not cancel the drag")
   up(ev)
   check(#requests==1 and requests[1].Field==field and requests[1].Quantity==3,"Partial TP sends one residual-quantity amendment")
   reset(1280,800,false);hit=nil;for _,h in ipairs(g.ProtectionHits)do if h.Field==field then hit=h end end
   ev=down(kind,30,hit.Y);move(ev,30,hit.Y-12);held.Quantity=2;chart:OnMarketUpdate();up(ev)
   check(#requests==0 and not chart.Drag,"Another partial fill cancels a stale protection drag")
  end
 end
 for _,reason in ipairs({"Stop loss","Player close","Account depleted","Account reset"})do
  held.Quantity=3;held.Triggered=reason;held.ProtectionEditable=false;reset(1280,800,false)
  local hit=g.ProtectionHits[1];if hit then local ev=down(Enum.UserInputType.MouseButton1,30,hit.Y);check(not chart.Drag or chart.Drag.Kind~="Protection","Genuine closing state cannot drag protection");up(ev)end
 end
 check(not ctl.Root:GetAttribute("ChartError"),"No chart rendering errors")
 report.Cases=#report.Checks
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end
gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result

