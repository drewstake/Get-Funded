-- Isolated Studio integration fixture. Uses actual callbacks and server calculations; no DataStores.
local shared=game.ReplicatedStorage.MarketReign:Clone() shared.Name="UIPolishFixtureModules" shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone() server.Name="UIPolishFixtureServer" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui") gui.Name="UIPolishFixture" gui.IgnoreGuiInset=true gui.DisplayOrder=100 gui.Parent=game.StarterGui
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end):gsub("return shell,commit",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestCommit";hook.OnInvoke=commit;hook.Parent=shell;return shell,commit'
end)
local M=require(shared.MarketClient) local UI=require(shared.TerminalUI)
local E=require(server.MarketEngine) local F=require(server.FundedAccounts) local S=require(server.TradeStats)
local C=require(shared.MarketConfig) local L=require(shared.ProgressionConfig)
local e=E.new(C,91) local f=F.new(e,L,C) f:Start("ui-test") f:Flag("ui-test","TutorialDone")
local a=e.Accounts[f:Owner("ui-test")] a.Realized=1000 a.Balance=6000
local session local original=M.New
M.New=function()
 local snap=e:Snapshot(a.Id,"BX","1m",true) snap.CandlesBySeries={}
 session=original(nil,true,snap) session.Preview=false session.Ready=true session.CanTrade=true
 session.AccountKey=a.Id session.Portfolio=f:View("ui-test") session.SummaryData=e:Summary(a)
 session.Capacity=snap.Capacity session.Limit=snap.Limit session.Send=function()return true,"Test","Orders",1 end
 return session
end
local host=Instance.new("Frame") host.Size=UDim2.fromOffset(1920,936) host.Parent=gui
local ctl=UI.Mount(host) local state=ctl.State
local report={Quantity={},Layouts={},Live={},Charts={},Checks={}}
local fixture={Gui=gui,Host=host,Controller=ctl,Session=session,Shared=shared,Server=server,Report=report}
_G.UIPolishFixture=fixture
local function draw()ctl.Root.UIDiagnostics:Invoke("Render") task.wait(.035)end
local function get(name)return assert(ctl.Root.Canvas:FindFirstChild(name,true),"Missing "..name)end
local function click(object)object.TestActivate:Invoke();task.wait(.04)end
local function check(name,yes)assert(yes,name);table.insert(report.Checks,name)end
function fixture:Resize(w,h)host.Size=UDim2.fromOffset(w,h);task.wait(.07);draw()end
function fixture:Screen(screen)state.Screen=screen;state.Nav=screen=="Dashboard"and"Accounts"or screen;state.Overlay=nil;draw()end
function fixture:Tick(open)
 a.Positions.BX=open==0 and nil or {Id=1,Contract="BX",Direction=1,Quantity=1,Entry=5825}
 e.Books.BX.Last=(5825+open/50)/.25
 session.Portfolio=f:View("ui-test") session.SummaryData=e:Summary(a)
 session.Changed:Fire();task.wait(.06)
end
function fixture:Stats(kind)
 local eng=E.new(C,91) local funded=F.new(eng,L,C) funded:Start("stats") funded:Flag("stats","TutorialDone")
 local account=eng.Accounts[funded:Owner("stats")]
 local rows=kind=="Empty"and{}or kind=="Winning"and{100,200}or kind=="Losing"and{-100,-200}or kind=="Even"and{0,0}or{750,-225,-50,0}
 local day=DateTime.fromUniversalTime(2026,9,20).UnixTimestamp
 for i,v in ipairs(rows)do S.Add(account.Stats,{Pnl=v,ClosedAt=day+(i-1)*86400,TradeId=i});account.Realized+=v;account.Balance+=v;account.CompletedTrades=(account.CompletedTrades or 0)+1 end
 session.Stats=funded:Stats("stats");session.StatsAt=os.clock();self:Screen("Stats")
 return rows
end
function fixture:Destroy()ctl:Destroy();gui:Destroy();shared:Destroy();server:Destroy();_G.UIPolishFixture=nil end
local ok,err=pcall(function()
 fixture:Screen("Trade")
 for _,tier in ipairs(L.Tiers)do
  session.Portfolio.ActiveName=tier.Name session.Limit=tier.MaxContracts
  for _,symbol in ipairs(C.ContractOrder)do
   state.Contract=symbol session.Capacity[symbol]={Buy=tier.MaxContracts,Sell=tier.MaxContracts}
   state.Qty=tier.MaxContracts state.Overlay=nil draw()
   local qty=get("Quantity")
   -- Consecutive + and direct-entry events share one pending popup.
   qty.Increase.TestActivate:Invoke();qty.Value.Text=tostring(tier.MaxContracts+12);qty.TestCommit:Invoke()
   task.wait(.07)
   assert(state.Qty==tier.MaxContracts and state.Overlay=="QuantityLimit")
   local message=get("LimitMessage").Text
   assert(message:find(tostring(tier.MaxContracts).." "..symbol,1,true) and message:find(tier.Name,1,true))
   local count=0 for _,x in ctl.Root:GetDescendants()do if x.Name=="LimitMessage"then count+=1 end end assert(count==1)
   click(get("GotIt"));assert(state.Overlay==nil)
   qty=get("Quantity");qty.Value.Text=tostring(tier.MaxContracts+1);qty.TestCommit:Invoke();task.wait(.06)
   assert(state.Qty==tier.MaxContracts and state.Overlay=="QuantityLimit")
   click(get("GotIt"))
   table.insert(report.Quantity,{Account=tier.Name,Symbol=symbol,Maximum=tier.MaxContracts,Plus=true,Direct=true,SinglePopup=true})
  end
 end
 state.Contract="BX" session.Limit=10 session.Capacity.BX={Buy=2,Sell=3} state.Qty=3 draw()
 click(get("Quantity").Increase);assert(state.Qty==3 and get("LimitMessage").Text:find("3 BX",1,true));click(get("GotIt"))
 session.Capacity.BX={Buy=0,Sell=0};session.Changed:Fire();task.wait(.05);draw()
 check("No remaining capacity clamps to zero",state.Qty==0)
 click(get("Quantity").Increase);assert(get("LimitMessage").Text:find("0 BX",1,true));click(get("GotIt"))
 session.Limit=5 session.Capacity.BX={Buy=5,Sell=5} session.Portfolio=f:View("ui-test");session.Changed:Fire();task.wait(.05);draw()
 check("Recovered capacity restores usable quantity",state.Qty==1)
 local fields=get("Fields")
 check("Removed max label and protection Settings",not ctl.Root:FindFirstChild("QtyMaxPill",true)and not ctl.Root:FindFirstChild("ProtectionSettings",true))
 click(fields.StopCard.Toggle);check("Stop loss toggles off",not state.StopOn)
 click(get("Fields").StopCard.Toggle);check("Stop loss toggles on",state.StopOn)
 click(get("Fields").TargetCard.Toggle);check("Take profit toggles off",not state.TargetOn)
 click(get("Fields").TargetCard.Toggle);check("Take profit toggles on",state.TargetOn)
 for _,pair in ipairs({{"Stop",125.5},{"Target",287.5}})do
  local box=get("Fields")[pair[1].."Card"].Distance box.Value.Text=tostring(pair[2]);assert(box.TestCommit:Invoke())
  check(pair[1].." direct dollars",state[pair[1].."Dollars"]==pair[2])
 end
 for _,open in ipairs({0,600,-150,2500,0})do
  fixture:Tick(open)
  local card=get("ObjectiveCard") assert(card.Amount.Text==M.Money(1000+open).." / $3,000")
  assert(not card:FindFirstChild("Confirmed")and not card.Track:FindFirstChild("Percent"))
  assert(session.Portfolio.Accounts[2].State=="Locked","Unrealized profit unlocked account")
  table.insert(report.Live,{Open=open,Live=ctl.Root:GetAttribute("UnlockProjected"),Closed=ctl.Root:GetAttribute("UnlockProgress")})
 end
 fixture:Tick(600);a.Realized+=600;a.Balance+=600;fixture:Tick(0)
 check("Closure reconciles live dollars",get("ObjectiveCard").Amount.Text=="$1,600.00 / $3,000"and ctl.Root:GetAttribute("UnlockProgress")==1600)
 click(get("AccountsCard"));check("Accounts navigation",state.Screen=="Dashboard")
 check("Accounts duplicate removed",not ctl.Root.Canvas.Dashboard:FindFirstChild("NextUnlock"))
 check("Selected and locked tiers retained",get("TierF5K").Status:FindFirstChildWhichIsA("TextLabel").Text=="SELECTED"and get("TierF10K").Status:FindFirstChildWhichIsA("TextLabel").Text=="LOCKED")
 state.Overlay="Settings";draw();check("Main Settings available",get("SoundToggle")~=nil)
 for _,size in ipairs({{1920,936,3},{1280,720,3},{844,390,2},{390,844,1},{320,568,1}})do
  fixture:Resize(size[1],size[2])
  for _,kind in ipairs({"Empty","Winning","Losing","Even","Mixed"})do
   fixture:Stats(kind)
   local stats=ctl.Root.Canvas.Stats assert(stats:GetAttribute("MetricColumns")==size[3])
   local count=0 for _,v in stats:GetChildren()do if v.Name:match("^Metric")then count+=1 end end assert(count==6)
   for _,name in ipairs({"MetricTradeWin","MetricDayWin","MetricFactor"})do
    local card=stats[name] local chart=card:FindFirstChild("Gauge")or card.Donut
    assert(chart:GetAttribute("Renderer")=="CircularStroke"and not chart:FindFirstChild("Segment"))
    local win,loss,neutral=chart:GetAttribute("WinShare"),chart:GetAttribute("LossShare"),chart:GetAttribute("NeutralShare")
    assert(math.abs((win or 0)+loss+neutral-1)<1e-6)
    if kind=="Winning"then assert(win==1 and loss==0)elseif kind=="Losing"then assert(win==0 and loss==1)elseif kind=="Even"or kind=="Empty"then assert(neutral==1)end
    assert(chart.Position.X.Offset>=0 and chart.Position.X.Offset+chart.Size.X.Offset<=card.Size.X.Offset)
   end
   table.insert(report.Charts,{Width=size[1],Height=size[2],State=kind,Columns=size[3]})
  end
  click(get("TabPeriodDated"));assert(get("Stats"):GetAttribute("Period")=="Dated")
  click(get("MetricTradeWin").Help);assert(ctl.Root.Canvas.StatsMetricHelp.Visible);click(ctl.Root.Canvas.StatsMetricHelp.Close)
  fixture:Screen("Trade");fixture:Tick(600)
  if size[1]<1000 then
   local top=get("TopNavigation") assert(top.Account.Brand.Text:find("$2,200.00 / $3,000",1,true))
   assert(top.ObjectiveBar.Fill.Size.X.Offset>0)
  end
  click(get("Quantity").Increase)
  fixture:Screen("Dashboard");assert(not get("Dashboard"):FindFirstChild("NextUnlock"))
  for _,v in ctl.Root:GetDescendants()do
   if v:IsA("TextLabel")or v:IsA("TextButton")then
    local t=v.Text:lower();assert(not t:find("simulated",1,true)and not t:find("virtual funds",1,true),v:GetFullName())
   end
  end
  table.insert(report.Layouts,{Width=size[1],Height=size[2],Accounts=true,Trade=true,Stats=true})
 end
 fixture:Resize(1920,936);fixture:Stats("Mixed")
end)
if not ok then report.Error=tostring(err) end
return report
