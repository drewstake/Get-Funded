local shared=game.ReplicatedStorage.MarketReign:Clone() shared.Name="SummaryStatsUIFixture" shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone() server.Name="SummaryStatsUIFixture" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui") gui.Name="SummaryStatsUIFixture" gui.IgnoreGuiInset=true gui.Parent=game.StarterGui
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
local ctl
local ok,result=pcall(function()
 local M=require(shared.MarketClient) local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine) local F=require(server.FundedAccounts)
 local C=require(shared.MarketConfig) local L=require(shared.ProgressionConfig)
 local e=E.new(C,91) local f=F.new(e,L,C) f:Start("fixture") f:Flag("fixture","TutorialDone")
 local a=e.Accounts[f:Owner("fixture")] a.Realized=1000 a.Balance=6000
 local original=M.New local session
 M.New=function()
  local snap=e:Snapshot(a.Id,"BX","1m",true) snap.CandlesBySeries={}
  session=original(nil,true,snap) session.Preview=false session.Ready=true session.CanTrade=true
  session.AccountKey=a.Id session.Portfolio=f:View("fixture") session.SummaryData=e:Summary(a)
  session.Send=function()return true,"Fixture","Orders",1 end
  return session
 end
 local host=Instance.new("Frame") host.Size=UDim2.fromOffset(1920,1080) host.Parent=gui
 ctl=UI.Mount(host) ctl.Root.UIDiagnostics:Invoke("Set","Screen","Trade") task.wait()
 local function tick(open)
  a.Positions.BX=open==0 and nil or {Id=1,Contract="BX",Direction=1,Quantity=1,Entry=5825}
  e.Books.BX.Last=(5825+open/50)/.25
  session.Portfolio=f:View("fixture") session.SummaryData=e:Summary(a) session.Changed:Fire() task.wait() task.wait()
 end
 local rows={}
 for _,v in ipairs({0,600,-150,2500,0})do
  tick(v)
  local c=ctl.Root.Canvas.AccountSummary
  assert(c.AccountsCard.AccountsValue.Text=="1 USABLE")
  assert(c.AccountsCard.AccountBadge.Label.Text=="$5K SELECTED")
  assert(c.ObjectiveCard.Amount.Text==M.Money(1000+v).." / $3,000")
  assert(not c.ObjectiveCard:FindFirstChild("Confirmed"))
  assert(not c.ObjectiveCard.Track:FindFirstChild("Percent"))
  assert(c.EquityCard.EquityValue.Text==M.Money(6000+v))
  assert(c.UnrealizedCard.UnrealizedValue.Text==M.Signed(v))
  table.insert(rows,{Open=v,Projected=ctl.Root:GetAttribute("UnlockProjected"),Confirmed=ctl.Root:GetAttribute("UnlockProgress")})
 end
 ctl.Root.Canvas.AccountSummary.AccountsCard.TestActivate:Invoke() task.wait() task.wait()
 assert(ctl.Root:GetAttribute("Screen")=="Dashboard","Accounts card did not navigate")
 assert(ctl.Root.Canvas.Dashboard.TierF5K.Status:FindFirstChildWhichIsA("TextLabel").Text=="SELECTED")
 assert(ctl.Root.Canvas.Dashboard.TierF10K.Status:FindFirstChildWhichIsA("TextLabel").Text=="LOCKED")
 session.Stats=f:Stats("fixture") session.StatsAt=os.clock()
 ctl.Root.UIDiagnostics:Invoke("Set","Screen","Stats") task.wait()
 local page=ctl.Root.Canvas.Stats local count=0
 for _,v in ipairs(page:GetChildren())do if v.Name:match("^Metric")then count+=1 end end
 assert(count==6 and page:GetAttribute("MetricColumns")==3)
 page.MetricTotal.Help.TestActivate:Invoke() task.wait()
 assert(ctl.Root.Canvas.StatsMetricHelp.Visible,"Tap help did not open")
 assert(ctl.Root.Canvas.StatsMetricHelp.Body.Text:find("Net realized",1,true))
 ctl.Root.Canvas.StatsMetricHelp.Close.TestActivate:Invoke() assert(not ctl.Root.Canvas.StatsMetricHelp.Visible)
 page.TabPeriodDated.TestActivate:Invoke() task.wait() task.wait()
 assert(ctl.Root.Canvas.Stats:GetAttribute("Period")=="Dated")
 local layouts={}
 for _,size in ipairs({{1280,720,3},{844,390,2},{390,844,1},{320,568,1}})do
  host.Size=UDim2.fromOffset(size[1],size[2]) task.wait(.08) ctl.Root.UIDiagnostics:Invoke("Render") task.wait()
  local sc=ctl.Root.Canvas.Stats assert(sc:GetAttribute("MetricColumns")==size[3])
  sc.MetricTotal.Help.TestActivate:Invoke()
  local help=ctl.Root.Canvas.StatsMetricHelp assert(help.Visible and help.Body.Text~="")
  assert(help.AbsolutePosition.X>=ctl.Root.AbsolutePosition.X and help.AbsolutePosition.Y>=ctl.Root.AbsolutePosition.Y)
  assert(help.AbsolutePosition.Y+help.AbsoluteSize.Y<=ctl.Root.AbsolutePosition.Y+ctl.Root.AbsoluteSize.Y)
  assert(sc.MetricTotal.Help.Question.Text=="?" and sc.MetricTotal.Help.Question.TextTransparency==0)
  help.Close.TestActivate:Invoke()
  table.insert(layouts,{Width=size[1],Height=size[2],Columns=size[3]})
  if size[1]<1000 then
   ctl.Root.UIDiagnostics:Invoke("Set","Screen","Trade") tick(600)
   local top=ctl.Root.Canvas.TopNavigation
   assert(top.Account.Brand.Text:find("$1,600.00 / $3,000",1,true))
   assert(math.abs(top.ObjectiveBar.Fill.Size.X.Offset-(top.ObjectiveBar.Size.X.Offset-4)*1600/3000)<1,"Mobile ratio "..size[1].." "..top.ObjectiveBar.Fill.Size.X.Offset.." / "..top.ObjectiveBar.Size.X.Offset)
   ctl.Root.UIDiagnostics:Invoke("Set","Screen","Stats")
  end
 end
 return {LiveReadouts=rows,AccountsNavigation=true,OwnedSelectedLocked=true,TapHelp=true,DatedScope=true,Layouts=layouts}
end)
if ctl then ctl:Destroy()end gui:Destroy() shared:Destroy() server:Destroy()
if not ok then error(result)end
return result
