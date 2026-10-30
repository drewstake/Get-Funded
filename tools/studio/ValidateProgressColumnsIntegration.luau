-- Full TerminalUI mounts verify available width after navigation and mobile insets.
local shared=game.ReplicatedStorage.ProgressColumnsQA
local UI=require(shared.TerminalUI)
local pf=game:GetService("HttpService"):JSONDecode(shared.Portfolio.Value)
local gui=Instance.new("ScreenGui");gui.Name="ProgressColumnsIntegrationQA";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local report={Layouts={},Issues={}};local ctl
local ok,err=xpcall(function()
 for _,size in ipairs({{320,568},{390,844},{749,303},{1024,768},{1280,720},{1440,900},{1920,1080}})do
  for _,tab in ipairs({"Trades","Wins","Profit","Ranks"})do
   local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
   ctl=UI.Mount(host,{Preview=true,PortfolioData=pf});ctl.State.CoachDismissed=true;ctl.State.Screen="Progress"
   ctl.State.ProgressViewState={Collection=tab=="Ranks"and "Ranks"or "Titles",Track=tab}
   ctl.Root.UIDiagnostics:Invoke("Render");task.wait(.05)
   assert(not ctl.Root:GetAttribute("RenderError"),ctl.Root:GetAttribute("RenderError"))
   local page=ctl.Root.Canvas.Progress
   for _,o in ipairs(page:GetDescendants())do if o:IsA("TextLabel")or o:IsA("TextButton")then
    if not o.TextFits then table.insert(report.Issues,size[1].." "..tab.." overflow: "..o:GetFullName().." "..o.Text)end
   end end
   page.CanvasPosition=Vector2.new(0,300);task.wait()
   local position=page.CanvasPosition.Y
   ctl.Root.UIDiagnostics:Invoke("Render");task.wait()
   assert(math.abs(ctl.Root.Canvas.Progress.CanvasPosition.Y-position)<1,"Full render lost scroll position")
   table.insert(report.Layouts,{Width=size[1],Height=size[2],Tab=tab,PageWidth=page.Size.X.Offset,Columns=page:GetAttribute("Columns")})
   ctl:Destroy();ctl=nil;host:Destroy()
  end
 end
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();assert(ok,err)
return report
