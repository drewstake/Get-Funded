-- Disposable UI fixtures; no live orders, remotes or persistence.
local H=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ResetLiquidationUIValidation"
shared.TerminalUI.Source=H:GetAsync("http://127.0.0.1:8791/src/shared/TerminalUI.luau",true);shared.Parent=game.ReplicatedStorage
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
local gui=Instance.new("ScreenGui");gui.Name="ResetLiquidationUIValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI);local C=require(shared.MarketConfig)
 local quotes,cache={},{}
 for _,key in ipairs(C.ContractOrder)do
  quotes[key]={Last=5825,Open=5825,Bid=5824.75,Ask=5825.25}
  for _,tf in ipairs(C.Timeframes)do local bars={};for i=1,100 do bars[i]={Time=i*tf[2],Open=5825,Close=5825,High=5826,Low=5824,Volume=50}end;cache[key..":"..tf[1]]=bars end
 end
 local report={Passed=true,Checks=0,Layouts=0}
 local function check(v,message)assert(v,message);report.Checks+=1 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1280,800},{1920,1080}})do
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  local pf={Active="reset-fixture",Started=true,StartingBalance=145000,Tutorial="Done",Rank="New Trader",RankId="New",Accounts={{Key="reset-fixture",Usable=true}},Milestones={}}
  ctl=UI.Mount(host,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=6000,Step=1},PortfolioData=pf})
  local session=ctl.Chart.Ctx.Session;session.AccountToken="reset-fixture"
  ctl.State.Coach=nil;ctl.State.Screen="Trade";ctl.State.Overlay="ResetAccount";ctl.Chart.Ctx.refresh();task.wait(.05)
  local dialog=ctl.Root.Canvas:FindFirstChild("Dialog");check(dialog~=nil,"Reset confirmation missing")
  local effects=dialog:FindFirstChild("ResetEffects",true)
  check(effects and effects.Text:find("available market prices",1,true),"Reset copy omits real execution")
  check(effects.Text:find("after every position closes",1,true),"Reset copy promises early grant")
  check(effects.TextFits,"Reset explanation clips at "..size[1])
  local preserved=dialog:FindFirstChild("Preserved",true);check(preserved and preserved.TextFits,"Preserved progress copy clips")
  local sent=0;session.ResetAccount=function()sent+=1;return true,"accepted",nil,sent end
  pf.Resetting=true;pf.Accounts[1].Resetting=true;pf.Accounts[1].Usable=false
  ctl.Chart.Ctx.refresh();task.wait(.05);dialog=ctl.Root.Canvas:FindFirstChild("Dialog")
  local confirm=dialog:FindFirstChild("ConfirmReset",true)
  check(confirm and not confirm.Active,"Pending reset button remains active")
  local activate=confirm:FindFirstChild("TestActivate");check(activate~=nil,"No confirmation test binding")
  activate:Invoke();check(sent==0,"Pending reset submitted a second request")
  check(not ctl.Root:GetAttribute("RenderError")and not ctl.Root:GetAttribute("ChartError"),"Reset UI failed to render")
  report.Layouts+=1;ctl:Destroy();ctl=nil;host:Destroy()
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result
