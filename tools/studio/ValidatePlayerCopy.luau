-- Disposable Edit-mode layout checks. Uses production rendering and server-shaped data.
local H=game.HttpService
local shared=game.ReplicatedStorage.CopyReviewShared
local fixture=H:JSONDecode(shared.Fixture.Value)
local UI=require(shared.TerminalUI)
local Market=require(shared.MarketClient)
local Board=require(shared.LeaderboardClient)
local copy=function(v)return H:JSONDecode(H:JSONEncode(v))end
local original=Market.New;local session
Market.New=function(...)
 session=original(...)
 session.SummaryData=copy(fixture.Snapshot.Summary)
 session.Portfolio=copy(fixture.Portfolio);session.Stats=copy(fixture.Stats)
 session.Positions={};session.Orders={};session.History={};session.Fills={}
 session.Ready=true;session.CanTrade=true;session.AccountKey=fixture.Portfolio.Active
 session.ConnectionStatus="Connected";session.Regime="High volatility"
 return session
end
local originalBoard=Board.new;local board
Board.new=function(...)
 board=originalBoard(...);return board
end
local gui=Instance.new("ScreenGui");gui.Name="CopyReviewLayoutQA";gui.IgnoreGuiInset=true;gui.DisplayOrder=100;gui.Parent=game.StarterGui
local report={Layouts={},Issues={},IntentionalNameTruncation={},StorageAccessed=false};local ctl
local scenarios={"Trade","Limit","Positions","Orders","History","Titles","ProfitTitles","Ranks","Help","Settings","Protection","QuantityLimit","Close","Blown","BlownClosing","Menu","Tools","Contracts","Timeframes","Coach1","Coach2","Coach3","Coach4","Coach5","Stats","StatsHelp","StatsLoading","StatsError","StatsEmpty","StatsPartial","Board","BoardLoading","BoardError","BoardEmpty","LongToast","AllTitles","TopRank"}
local function inspect(mode,size)
 local error=ctl.Root:GetAttribute("RenderError")
 if error then table.insert(report.Issues,{Size=size,Mode=mode,Error=error})end
 for _,o in ipairs(ctl.Root:GetDescendants())do
  if (o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox"))and o.Text~=""and o.TextTransparency<.99 then
   local visible=true;local p=o
   while p and p~=ctl.Root do if p:IsA("GuiObject")and not p.Visible then visible=false;break end;p=p.Parent end
   if visible and not o.TextFits then
    local target=o.Name=='PlayerName'and o.TextTruncate==Enum.TextTruncate.AtEnd and report.IntentionalNameTruncation or report.Issues
    table.insert(target,{Size=size,Mode=mode,Path=o:GetFullName():gsub('StarterGui.CopyReviewLayoutQA.Viewport.Workspace.Canvas.',''),Text=o.Text,Box=tostring(o.AbsoluteSize),Bounds=tostring(o.TextBounds)})
   end
  end
 end
end
local ok,err=xpcall(function()
 for _,size in ipairs({{320,568},{390,844},{402,874},{749,303},{844,390},{1024,768},{1280,720},{1920,1080}})do
  local host=Instance.new("Frame");host.Name="Viewport";host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  ctl=UI.Mount(host,{Preview=true,PreviewData=fixture.Snapshot,PortfolioData=copy(fixture.Portfolio)})
  local state=ctl.State;local hook=ctl.Root.UIDiagnostics
  task.wait(.03)
  for _,mode in ipairs(scenarios)do
   session.Portfolio=copy(fixture.Portfolio);session.Stats=copy(fixture.Stats);session.SummaryData=copy(fixture.Snapshot.Summary)
   session.Positions={};session.Orders={};session.History={};session.Fills={}
   state.Screen="Trade";state.Overlay=nil;state.Sheet=false;state.Coach=nil;state.CoachDismissed=true;state.Tab="Positions";state.Type="Market";state.Toast=nil;state.ToastPnl=nil;state.StatsHelp=nil
   state.ProgressViewState={Collection="Titles",Track="Trades"}
   local held={Id=1,Contract="BX",Direction=1,Quantity=10,Entry=5840,Unrealized=-12345.67,Stop=5830,Target=5870}
   if mode=="Limit"then state.Type="Limit"end
   if mode=="Positions"or mode=="Close"or mode=="Coach4"then session.Positions.BX=held;session.SummaryData.Count=1;session.SummaryData.Unrealized=held.Unrealized end
   if mode=="Orders"then state.Tab="Orders";session.Orders={{Id=1,Contract="BX",Kind="Take profit",Type="Limit",Quantity=10,Price=5870,Status="Working"}}end
   if mode=="History"or mode=="Coach5"then state.Tab="History";session.History={{Contract="BX",Quantity=10,Entry=5840,Exit=5850,Pnl=5000,Time="12:34:56"}}end
   if mode=="Titles"or mode=="ProfitTitles"or mode=="Ranks"or mode=="AllTitles"or mode=="TopRank"then
    state.Screen="Progress";state.ProgressViewState={Collection=mode=="Ranks"and "Ranks"or "Titles",Track=mode=="ProfitTitles"and "Profit"or "Trades"}
    if mode=="AllTitles"then session.Portfolio.Next=nil;session.Portfolio.Completed=true;for _,m in ipairs(session.Portfolio.Milestones)do m.Earned=true;m.Progress=m.Goal end end
    if mode=="TopRank"then session.Portfolio.Rank="Market Sovereign";session.Portfolio.RankLevel=8;session.Portfolio.Title="Get Funded Legend"end
   elseif mode:match("^Stats")then
    state.Screen="Stats"
    if mode=="StatsHelp"then state.StatsHelp="Total"
    elseif mode=="StatsLoading"then session.Stats={Loading=true}
    elseif mode=="StatsError"then session.Stats={Error="The exchange is reconnecting. Try again in a moment."}
    elseif mode=="StatsEmpty"then session.Stats={New=true}
    elseif mode=="StatsPartial"then local a=session.Stats.Scopes[1].Current;a.Partial=true;a.UntrackedTrades=25;a.UntrackedNet=-2500;a.CountUnknown=true;a.UndatedTrades=25 end
   elseif mode:match("^Board")then
    state.Screen="Leaderboard"
    local row={UserId=101,Name="SamplePlayer",DisplayName="A Very Long Player Display Name",Cents=1234567890123,Rank=1,ProgressionVersion=1,ProgressionRankId="Sovereign"}
    board.Data={State=mode=="Board"and "Ready"or mode:sub(6),Rows=mode=="Board"and {row}or {},Your=mode=="Board"and row or nil}
   elseif mode:match("^Coach")then state.Coach=tonumber(mode:sub(6))
   elseif mode=="LongToast"then state.Toast="Trade closed · +$1,234,567.89";state.ToastPnl=1234567.89;state.ToastKind="success"
   elseif mode~="Trade"and mode~="Limit"and mode~="Positions"and mode~="Orders"and mode~="History"then
    state.Overlay=mode
    if mode=="Protection"then state.ProtectionDraft={StopOn=true,TargetOn=true,StopDollars=500,TargetDollars=1500}end
    if mode=="QuantityLimit"then state.QuantityLimit=100;state.QuantitySymbol="BX";state.QuantityAccount="Trading account"end
    if mode=="Close"then state.CloseContract="BX"end
    if mode=="Blown"or mode=="BlownClosing"then
     state.Overlay="Blown";session.Portfolio.Failed=true
     local row=session.Portfolio.Accounts[1];row.Depleted=true;row.CanRestart=mode=="Blown";row.Closing=mode=="BlownClosing";row.Realized=-12345.67
     state.BlownTier=row.Key;state.BlownEvent=row.DepletionEvent
    end
   end
   hook:Invoke("Render");task.wait(.025)
   inspect(mode,size[1].."x"..size[2])
  end
  table.insert(report.Layouts,{Width=size[1],Height=size[2],Scenarios=#scenarios})
  ctl:Destroy();ctl=nil;host:Destroy()
 end
end,debug.traceback)
Market.New=original;Board.new=originalBoard
if ctl then ctl:Destroy()end;gui:Destroy()
report.Ok=ok;report.Error=err
H:PostAsync('http://127.0.0.1:8786/results/layout-validation.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return report
