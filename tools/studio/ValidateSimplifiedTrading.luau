-- Isolated Studio Edit integration fixture. Uses real UI, drawing controller and funded views.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="SimplifiedValidation";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="SimplifiedValidation";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="SimplifiedValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=pcall(function()
 local M=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local config=require(shared.MarketConfig);local ladder=require(shared.ProgressionConfig)
 local e=E.new(config,91);local f=F.new(e,ladder,config);f:Start("fixture");f:Flag("fixture","TutorialDone")
 local a=e.Accounts[f:Owner("fixture")];a.Realized=8000;a.Balance=13000;f:Evaluate("fixture");f:Activate("fixture","F10K");f:Activate("fixture","F25K")
 for _,key in ipairs({"F10K","F25K"})do
  local lost=e.Accounts[f:Resolve("fixture",key)];lost.Locked=true;lost.Depleted=true;lost.Realized=-lost.Base;lost.Balance=0
 end
 f:Evaluate("fixture")
 local original=M.New;local session
 M.New=function()
  local data={Quotes={},CandlesBySeries={},Time=3600,Step=1}
  for _,key in ipairs(config.ContractOrder)do
   local spec=config.Contracts[key];data.Quotes[key]={Last=spec.Last,Open=spec.Last,Bid=spec.Last-spec.Tick,Ask=spec.Last+spec.Tick}
   for _,tf in ipairs(config.Timeframes)do
    local list={};for i=1,60 do local price=spec.Last+math.sin(i*.7)*8*spec.Tick
     list[i]={Time=(i-1)*tf[2],Open=price,Close=price+spec.Tick,High=price+3*spec.Tick,Low=price-2*spec.Tick,Volume=10}
    end;data.CandlesBySeries[key..":"..tf[1]]=list
   end
  end
  session=original(nil,true,data);session.Preview=false;session.Ready=true;session.CanTrade=true;session.Portfolio=f:View("fixture");session.AccountKey=a.Id
  session.Send=function()return true,"Fixture","Orders",1 end
  return session
 end
 local report={Layouts={},Chart={}}
 for _,size in ipairs({{320,568},{390,844},{844,390},{1000,600},{1280,720},{1920,1080}})do
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  ctl=UI.Mount(host)
  for _,mode in ipairs({"Dashboard","Blown","Tools","Trade"})do
   ctl.State.Screen=mode=="Dashboard"and"Dashboard"or"Trade";ctl.State.Overlay=(mode=="Blown"or mode=="Tools")and mode or nil
   ctl.State.BlownTier="F25K";ctl.State.BlownEvent="F25K:1"
   ctl.Root.UIDiagnostics:Invoke("Set","Qty",3);task.wait(.08)
   local issues={}
   if mode=="Blown"then
    assert(ctl.Root.Canvas:FindFirstChild("StatValue3",true).Text=="$0 / $5,000","Blown notice must show its own tier's goal, even when an earlier tier is also locked")
   end
   for _,x in ipairs(ctl.Root.Canvas:GetDescendants())do
    if x:IsA("TextLabel")and x.Visible and x.Text~=""and not x.TextFits and not x.TextScaled and x.TextTruncate==Enum.TextTruncate.None then table.insert(issues,x:GetFullName()..": "..x.Text)end
    assert(not(x:IsA("TextLabel")and x.Text:find("Effective .- total")),"Effective readout still present")
    assert(x.Name~="ToolUndo" and x.Name~="ToolRedo","Removed control remains: "..x.Name)
    assert(not(x:IsA("TextLabel")and x.Text:find("Estimated totals for")),"Quantity estimate remains")
    if x:GetAttribute("RestartTier")then assert(x:GetAttribute("RestartTier")=="F5K","Higher tier restart remains")end
    if x.Name=="Distance"and x:IsA("Frame")then
     assert(not x:FindFirstChild("Increase")and not x:FindFirstChild("Decrease"),"Dollar stepper remains")
     assert(x.Value.AbsoluteSize.Y>=52 and x.Value.AbsoluteSize.X==x.AbsoluteSize.X,"Direct input is not full width")
    end
   end
   table.insert(report.Layouts,{Width=size[1],Height=size[2],Mode=mode,Issues=issues})
   assert(#issues==0,table.concat(issues,"\n"))
  end
  if size[1]==1920 then
   local chart=ctl.Chart;ctl.State.Screen="Trade";ctl.State.Overlay=nil;ctl.State.Tool="Trend"
   ctl.Root.UIDiagnostics:Invoke("Set","Qty",3);task.wait(.1)
   local function paint(x,y,magnet)
    local g=chart.Geometry;ctl.State.Magnet=magnet;chart.LastTouch=false;chart.Hover=g.Plot.AbsolutePosition+Vector2.new(g.Left+x,g.Top+y)
    chart:PaintOverlay(g);return g,chart.Hover,ctl.Root.Canvas:FindFirstChild("TrendReadyDot",true)
   end
   local g,pos,dot=paint(chart.Geometry.Width*.4,chart.Geometry.Height*.4,false)
   assert(dot and dot.Visible,"Trend readiness missing")
   local px,py=chart:Local(pos);local point=chart:PointAt(px,py,true,false)
   assert(math.abs(dot.Position.X.Offset+3-g.X(point.Time))<.001 and math.abs(dot.Position.Y.Offset+3-g.Y(point.Price))<.001,"Readiness misaligned")
   chart:Began({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector3.new(pos.X,pos.Y,0)})
   assert(chart.Placement.A.Time==point.Time and chart.Placement.A.Price==point.Price,"Click uses a different point")
   chart:Cancel();chart:PaintOverlay(g);assert(not dot.Visible and ctl.State.Tool=="Pan","Cancel did not hide readiness")
   ctl.State.Tool="Trend";local candle=g.Data[math.floor(#g.Data*.5)]
   g,pos,dot=paint(g.X(candle.Time)+2,g.Y(candle.High)+2,true)
   assert(dot.Visible and ctl.Root:GetAttribute("TrendReadyTime")==candle.Time and ctl.Root:GetAttribute("TrendReadyPrice")==candle.High,"Magnet readiness does not match snapped click")
   chart.Hover=nil;chart:PaintOverlay(g);assert(not dot.Visible,"Leave did not hide dot")
   paint(g.Width*.4,g.Height*.4,false);ctl.State.Tool="Pan";chart:PaintOverlay(g);assert(not dot.Visible,"Deselect did not hide dot")
   ctl.State.Tool="Trend";paint(g.Width+1,10,false);assert(not dot.Visible,"Price axis should not show drawing dot")
   report.Chart={Aligned=true,ClickMatches=true,Magnet=true,Cancel=true,Leave=true,Deselect=true,AxisExcluded=true}
  end
  ctl:Destroy();ctl=nil;host:Destroy()
 end
 return report
end)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy();server:Destroy()
if not ok then error(result)end
return result
