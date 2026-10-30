-- Disposable native UI fixtures and actual ChartView gesture handlers. No live trading/storage.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="UpgradeUIQA";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="UpgradeUIQA";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI);local Tools=require(shared.ChartTools);local Config=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local candles={};for i=1,160 do local o=5800+math.floor(math.sin(i*.17)*28)*.25;candles[i]={Time=i*60,Open=o,High=o+2,Low=o-2,Close=o+1,Volume=50}end
 local cache,quotes={},{};for _,key in ipairs(Config.ContractOrder)do
  quotes[key]={Last=5800,Open=5800,Bid=5799.75,Ask=5800.25,Spread=.5}
  for _,tf in ipairs(Config.Timeframes)do cache[key..":"..tf[1]]=candles end
 end
 local pf={Active="qa",RankId="Apprentice",Rank="Trading Apprentice",RankBadge=2,RankLevel=2,RankNext=L.Ranks[3],Tutorial="Done",StartingBalance=11250,StartingBonus=1250,
  Earned=25000,Trades=100,Wins=25,Titles={"Green Spark","Tape Reader"},Title="Tape Reader",Milestones={},Ranks={},Accounts={}}
 for _,m in ipairs(L.Milestones)do local r=table.clone(m);r.Key=m.Id;r.Earned=m.Id=="FirstWin"or m.Id=="Trades5";r.Progress=r.Earned and m.Goal or 0;table.insert(pf.Milestones,r);if not pf.Next and not r.Earned then pf.Next=r end end
 for i,r in ipairs(L.Ranks)do local x=table.clone(r);x.Earned=i<=2;table.insert(pf.Ranks,x)end
 local away={Id="1:1",Seconds=3665,MarketSeconds=800,Total=-275,Realized=-100,Unrealized=-25,RealizedChange=-250,CarriedIn=150,UnrealizedChange=-25,
  Coverage="Exits use actual exchange trades while the server runs. The market pauses when no server is running; no missing prices or outcomes are invented.",
  Rows={{Contract="BX",Direction=1,Quantity=5,Remaining=3,Realized=-100,RealizedChange=-250,UnrealizedChange=-25,Exits={{Reason="Stop loss",Quantity=2,Notional=11600,Change=-250,Realized=-100}}}}}
 local own={UserId=123,DisplayName="Current Player",Name="CurrentPlayer",Cents=-1200,Rank=3,Eligible=true}
 local board={State="Ready",Your=own,Rows={{UserId=1,DisplayName="A very long player display name",Cents=123456789012,Rank=1,Eligible=true},{UserId=2,DisplayName="Second Trader",Cents=2000000,Rank=2,Eligible=true},own}}
 local report={Checks={},Issues={},Layouts=0}
 local function check(v,message)assert(v,message);table.insert(report.Checks,message)end
 local function mount(width,height)
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(width,height);host.Parent=gui
  ctl=UI.Mount(host,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=9600,Step=1},PortfolioData=pf,LeaderboardData=board})
  ctl.State.Screen="Trade";ctl.Chart.Ctx.refresh();task.wait(.07);return host
 end
 local host=mount(1280,800);local chart=ctl.Chart;local s=ctl.State;local session=chart.Ctx.Session
 local panel=ctl.Root.Canvas.Chart
 local function paint()
  chart:Paint(panel.Position.X.Offset,panel.Position.Y.Offset,panel.Size.X.Offset,panel.Size.Y.Offset,false,false,true)
 end
 local state=chart.Geometry.State;state.Right=9600;state.Follow=false;state.Bars=72;state.AutoY=false;state.Low=5770;state.High=5830;paint()
 local originalRefresh=chart.Ctx.refresh;chart.Ctx.Options.Preview=false;chart.Ctx.onIdle=function()end;chart.Ctx.refresh=function()end
 local legacy=Tools.New("Rect",{Time=6000,Price=5795},{Time=6600,Price=5805},s.Contract,"1m");table.insert(s.Drawings,legacy);chart.Selected=legacy.Id
 for _,tf in ipairs(Config.Timeframes)do s.Timeframe=tf[1];check(#chart:Current()==1 and chart:SelectedDrawing()==legacy,"Legacy drawing shared on "..tf[1])end
 Tools.Edit(chart:Current()[1],Tools.Copy(legacy),"Corner3",{Time=6900,Price=5806},{});s.Timeframe="1m"
 check(chart:Current()[1].T2==6900 and chart:Current()[1].P2==5806,"Cross-timeframe edits share one drawing")
 chart:DeleteSelected();check(#chart:Current()==0,"Delete removes the shared drawing");chart:Undo();check(#chart:Current()==1,"Undo preserves legacy coordinates");table.clear(s.Drawings)
 local function position(x,y)local g=chart.Geometry;return g.Plot.AbsolutePosition+Vector2.new(g.Left+x,g.Top+y)end
 local function down(x,y)chart.Hover=position(x,y);chart:Began({UserInputType=Enum.UserInputType.MouseButton1,Position=chart.Hover})end
 local function move(x,y)chart.Hover=position(x,y);chart:Changed({UserInputType=Enum.UserInputType.MouseMovement,Position=chart.Hover})end
 local function finish()chart:Ended({UserInputType=Enum.UserInputType.MouseButton1,UserInputState=Enum.UserInputState.End})end
 local requests={};session.AccountKey="qa"
 session.CreateProtection=function(_,key,id,field,price,quantity)table.insert(requests,{Field=field,Price=price,Quantity=quantity});return true,"ok",nil,#requests end
 for _,side in ipairs({1,-1})do for _,offset in ipairs({-3,3})do
  s.Tool="Pan";chart.Pending=nil;session.Positions[s.Contract]={Id=10,Direction=side,Quantity=5,Entry=5800};paint()
  local g=chart.Geometry;local mark=chart.EntryMarker;local x,y=mark.X+mark.W/2,mark.Y+mark.H/2
  local right=state.Right;local before=#requests;down(x,y)
  check(chart.Drag and chart.Drag.Creating,"Entry label starts creation for direction "..side)
  move(x,y+1);finish();check(#requests==before,"Small movement never places protection")
  down(x,y);move(x,g.Y(5800+offset));paint()
  check(chart.Drag.Field==Tools.ProtectionField(side,5800,chart.Drag.Price),"Drag preview type follows entry side")
  check(ctl.Root:GetAttribute("ProtectionPreviewPrice")~=nil,"Live preview exposes protection price")
  move(x,g.Y(5800-offset));check(chart.Drag.Field==Tools.ProtectionField(side,5800,chart.Drag.Price),"Crossing entry switches SL/TP")
  chart:Cancel();paint();check(#requests==before,"Cancel sends no request")
  down(x,y);move(x,g.Y(5800+offset));local expected=chart.Drag.Field;finish()
  check(#requests==before+1 and requests[#requests].Field==expected,"Release creates correct protection: "..tostring(expected).." requests="..#requests.." before="..before)
  check(state.Right==right,"Protection drag never pans chart")
 end end
 chart.Pending=nil;session.Positions[s.Contract]={Id=10,Direction=1,Quantity=5,Entry=5800,Stop=5790};paint()
 local g=chart.Geometry;local mark=chart.EntryMarker;down(mark.X+10,mark.Y+mark.H/2);move(mark.X+10,g.Y(5805));finish()
 check(requests[#requests].Field=="Target","Remaining TP can be created after SL")
 session.Positions={};chart.Pending=nil;s.Tool="Rect";chart.Hover=nil;chart.Ctrl=true;chart.RectangleLockTime=nil;paint();g=chart.Geometry
 local candle=g.Data[math.floor(#g.Data/2)];local x,y=g.X(candle.Time)+1,g.Y(candle.High)-.5
 local pt=chart:PlacementPointAt(x,y,false)
 check(pt.Time==candle.Time and pt.Price==candle.High and pt.Snap,"Ctrl rectangle softly snaps to selected candle high")
 local free=chart:PlacementPointAt(x,g.Y(candle.High)-16,false);check(not free.Snap and free.Time==candle.Time,"Ctrl retains candle time while horizontal snap releases")
 chart.Ctrl=false;chart:Cancel();ctl:Destroy();ctl=nil;host:Destroy()
 for _,size in ipairs({{320,568},{390,844},{650,360},{1000,600},{1280,800},{1920,1080}})do
  local host=mount(size[1],size[2]);local c=ctl.Chart
  for _,screen in ipairs({"Trade","Leaderboard","Progress","ResetAccount","Away"})do
   pf.AwaySummary=screen=="Away"and away or nil;ctl.State.AwaySeen=nil
   ctl.State.Screen=screen=="ResetAccount"or screen=="Away"and "Trade"or screen
   if screen=="ResetAccount"or screen=="Away"then ctl.State.Screen="Trade";ctl.State.Overlay=screen else ctl.State.Overlay=nil end
   c.Ctx.refresh();task.wait(.07);report.Layouts+=1
   check(not ctl.Root:GetAttribute("RenderError"),size[1].." "..screen.." renders")
   local canvas=ctl.Root.Canvas
   local target=screen=="ResetAccount"and canvas:FindFirstChild("Dialog")or screen=="Away"and canvas:FindFirstChild("AwayDialog")or screen=="Leaderboard"and canvas:FindFirstChild("Leaderboard")or screen=="Progress"and canvas:FindFirstChild("Progress")
   if screen=="Leaderboard"then
    check(target~=nil,"Leaderboard mounts")
    check(target.Rows.YourStanding:GetAttribute("DisplayedBalance")==0 and own.Cents==-1200,"Negative balance clamped only in presentation")
    check(not target:FindFirstChild("ProgressionRank",true) and not target:FindFirstChild("Profit",true),"Leaderboard omits rank subtitles and lifetime profit")
   end
   if target then for _,o in ipairs(target:GetDescendants())do
    if o:IsA("TextLabel")and o.Visible and o.TextTruncate==Enum.TextTruncate.None and not o.TextFits then
     table.insert(report.Issues,size[1].." "..screen.." text overflow: "..o:GetFullName().." "..o.Text)
    end
   end end
   if screen=="Trade" and canvas:FindFirstChild("Sidebar")then
    local rail=canvas.Sidebar
    check(rail.ResetAccount.Position.Y.Offset<rail.Settings.Position.Y.Offset,"Reset immediately above Settings")
    check(rail.Rank.Position.Y.Offset>rail.MarketBG.Position.Y.Offset,"Rank below market tickers")
    check(rail.Rank.Position.Y.Offset+rail.Rank.Size.Y.Offset<=rail.ResetAccount.Position.Y.Offset,"Rank does not overlap Reset")
    check(rail.SidebarRankBadge~=nil,"Rank image accompanies name")
    pf.Rank="Rising Trader";pf.RankId="Rising";pf.RankBadge=4;c.Ctx.refresh();task.wait(.04)
    rail=ctl.Root.Canvas.Sidebar
    check(rail.Rank.Text=="Rising Trader" and rail.SidebarRankBadge:GetAttribute("BadgeIndex")==4,"Rank-up refresh updates both name and image")
    pf.Rank="Trading Apprentice";pf.RankId="Apprentice";pf.RankBadge=2
   end
  end
  pf.AwaySummary=nil;ctl:Destroy();ctl=nil;host:Destroy()
 end
 report.Cases=#report.Checks;return report
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result
