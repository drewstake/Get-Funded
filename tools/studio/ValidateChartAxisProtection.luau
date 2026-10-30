-- Isolated Studio Edit fixture using rendered markers and real chart input handlers.
-- Trading methods are captured locally; no remote requests or persistent account changes.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="ChartAxisProtectionQA";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="ChartAxisProtectionQA";gui.Parent=game.StarterGui
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
 session.AmendProtection=function(_,contract,id,field,price,original)
  table.insert(requests,{Kind="Protection",Field=field,Price=price,Original=original})
  return false,"Captured by fixture"
 end
 session.AmendOrder=function()table.insert(requests,{Kind="Order"});return false,"Captured by fixture"end
 session.CreateProtection=function()table.insert(requests,{Kind="Create"});return false,"Captured by fixture"end
 session.Cancel=function()table.insert(requests,{Kind="Cancel"});return false,"Captured by fixture"end
 local held={Id="axis-fixture",Entry=5820,Stop=5810,Target=5830,Quantity=1,Direction=1}
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
   local label=layout[1].."/"..kind.Name
   for _,field in ipairs({"Stop","Target"})do
    for _,axisOffset in ipairs({0,1,40})do
     reset(table.unpack(layout))
     local y=g.Y(held[field]);local ev=down(kind,g.Width+axisOffset,y)
     check(chart.Drag and chart.Drag.Kind=="Scale",label.." axis at "..field.." +"..axisOffset.." begins scaling")
     check(not ctl.Root:GetAttribute("DraggingProtection"),"Axis never sets protection drag indicator")
     move(ev,g.Width*.6,y+24)
     check(chart.Drag.Kind=="Scale" and state.High-state.Low>g.View.High-g.View.Low,"Axis keeps scaling after entering the chart")
     up(ev)
     check(#requests==0 and held.Stop==5810 and held.Target==5830,"Axis release leaves both protections unchanged without trading requests")
    end
    -- Both the visible label and its line remain draggable from inside the plot.
    for _,onLabel in ipairs({true,false})do
     reset(table.unpack(layout))
     local x=onLabel and 30 or g.Width*.8;local y=g.Y(held[field])
     local ev=down(kind,x,y)
     check(chart.Drag and chart.Drag.Kind=="Protection" and chart.Drag.Field==field,label.." grabs "..field..(onLabel and " label" or " line"))
     move(ev,x,y+18);up(ev)
     check(#requests==1 and requests[1].Kind=="Protection" and requests[1].Field==field and requests[1].Price~=requests[1].Original,"Only the grabbed protection is amended")
    end
    reset(table.unpack(layout))
    local x,y=g.Width+20,g.Y(held[field])
    local first=down(kind,x,y);up(first)
    local second=down(kind,x,y);up(second)
    check(state.AutoY==true and not chart.Drag and #requests==0,label.." double-tap at "..field.." restores auto-fit")
   end
   -- A working order at the same price must also leave the axis available.
   reset(table.unpack(layout))
   session.Orders={{Id="limit-fixture",Contract=s.Contract,Type="Limit",Quantity=1,Price=5810,Direction=1}}
   chart.Dirty=true;chart:Paint(0,0,layout[1],layout[2],layout[3],false,true);g=chart.Geometry
   local ev=down(kind,g.Width+20,g.Y(5810))
   check(chart.Drag and chart.Drag.Kind=="Scale",label.." axis wins over overlapping limit and SL")
   move(ev,g.Width+20,g.Y(5810)+24);up(ev)
   check(#requests==0,"Axis cannot amend or cancel a working order")
   reset(table.unpack(layout))
   local pan=down(kind,g.Width*.6,g.Y(5820))
   check(chart.Drag and chart.Drag.Kind=="Pan",label.." empty chart space still pans")
   move(pan,g.Width*.6+20,g.Y(5820)+20);up(pan)
   check(#requests==0,"Chart pan sends no protection request")
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
