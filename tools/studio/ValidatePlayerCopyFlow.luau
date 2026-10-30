-- Exercise the real notification and tutorial paths with an in-memory exchange.
local shared=game.ReplicatedStorage.CopyReviewShared
local server=game.ServerScriptService.CopyReviewServer
local H=game.HttpService
local fixture=H:JSONDecode(shared.Fixture.Value)
local Market=require(shared.MarketClient);local Board=require(shared.LeaderboardClient)
local original,originalBoard=Market.New,Board.new
local C=require(shared.MarketConfig);local F=require(server.FundedAccounts)
local e=require(server.MarketEngine).new(C,442);local f=F.new(e,require(shared.ProgressionConfig),C)
f:Start('copy-flow');f:Flag('copy-flow','TutorialDone')
local session
Market.New=function()
 session=original(nil,true,fixture.Snapshot)
 session.Preview=false;session.Ready=true;session.CanTrade=true;session.ConnectionStatus='ISOLATED · NOT SAVED'
 local function update()
  local a=e.Accounts[f:Owner('copy-flow')];local snap=e:Snapshot(a.Id,'BX','1m',true)
  session.Portfolio=f:View('copy-flow');session.AccountKey=a.Id;session.AccountToken=a.Id
  session.SummaryData=snap.Summary;session.Positions=snap.Positions;session.Orders=snap.Orders;session.History=snap.History;session.Fills=snap.Fills
  session.Limit=snap.Limit;session.Capacity=snap.Capacity;session.Stats=f:Stats('copy-flow')
 end
 session.Send=function(_,action,req)
  if action=='Subscribe'or action=='Stats'then return true,'Fixture','Orders',0 end
  session.NextId+=1;local id=session.NextId;req=req or {};req.Action=action
  local ok,value
  if action=='Flag'then ok,value=f:Flag('copy-flow',req.Stage)
  elseif action=='Restart'then ok,value=f:Restart('copy-flow',session.AccountToken)
  else ok,value=F.Perform(e,f:Owner('copy-flow'),req)end
  e:ProcessStops();f:Evaluate('copy-flow');update()
  task.defer(function()
   session.Replies:Fire({Ok=ok,Message=type(value)=='table'and F.Describe(value)or value,Kind=action,RequestId=id,Result=type(value)=='table'and value or nil})
   for _,event in ipairs(f:TakeEvents('copy-flow')or {})do session:_event(event)end
   session.Changed:Fire()
  end)
  return true,'Fixture','Orders',id
 end
 update();return session
end
Board.new=function()return originalBoard(true,{State='Empty',Rows={}})end
local gui=Instance.new('ScreenGui');gui.Name='CopyFlowQA';gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local host=Instance.new('Frame');host.Size=UDim2.fromOffset(390,844);host.Parent=gui
local ctl;local report={StorageAccessed=false}
local ok,err=xpcall(function()
 ctl=require(shared.TerminalUI).Mount(host)
 ctl.State.Coach=3;ctl.State.CoachBase=nil;ctl.State.CoachDismissed=true
 ctl.Root.UIDiagnostics:Invoke('Render');session.Changed:Fire();task.wait(.05)
 session:Place('BX',1,1,'Market',nil,500,1500);task.wait(.06)
 assert(ctl.State.Coach==4,'Tutorial did not advance after entry')
 session:Close('BX');task.wait(.06)
 assert(ctl.State.Coach==5,'Tutorial did not advance after close')
 report.FirstClose=ctl.State.Toast
 assert(report.FirstClose=='Trade closed · '..Market.Signed(ctl.State.ToastPnl),'Close notification must contain only Trade closed and signed P&L')
 assert(ctl.Root.Canvas.Toast.Message.Text=='Trade closed'and ctl.Root.Canvas.Toast.Pnl.Text==Market.Signed(ctl.State.ToastPnl),'Close card copy differs')
 ctl.State.Coach=nil
 for _=2,25 do session:Place('BX',1,1,'Market',nil,500,1500);task.wait();session:Close('BX');task.wait()end
 task.wait(.06)
 report.Milestone=ctl.State.ToastFollowup
 assert(f:Profile('copy-flow').Awards.FirstTrade,'25 closes must preserve the FirstTrade award ID')
 assert(report.Milestone:find('Title earned: Opening Bell',1,true),'Earned title was not announced')
 task.wait(3.1)
 assert(ctl.State.Toast==report.Milestone and ctl.State.ToastPnl==nil,'Earned title must follow the close card')
 local label=ctl.Root.Canvas.Toast.Message;assert(label.TextFits,'Milestone notification does not fit')
 -- Presentation fixture for a server-confirmed rank plus several rewards in one close.
 session.Portfolio.RankId='Apprentice';session.Portfolio.Rank='Trading Apprentice'
 session:_event({Kind='TradeClosed',Account=session.AccountKey,TradeId=999999,Reason='Trade',Pnl=1234567.89,Rewards={'Profit Scout','Golden Edge','Momentum Maker','Market Pro'}})
 task.wait(.06)
 report.Combined=ctl.State.ToastFollowup
 assert(report.Combined:find('Rank up: Trading Apprentice',1,true),'Rank gain missing from closing confirmation')
 assert(report.Combined:find('4 titles earned',1,true),'Multiple rewards should have compact copy')
 assert(ctl.Root.Canvas.Toast.Pnl.TextFits,'Large closing P&L does not fit')
 task.wait(3.1)
 assert(ctl.State.Toast==report.Combined and ctl.Root.Canvas.Toast.Message.TextFits,'Combined achievement notification does not fit')
 report.Trades=f:View('copy-flow').Trades;report.Balance=session:Summary().Balance;report.GuidedTrade=true
 e:Audit()
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();Market.New=original;Board.new=originalBoard
report.Ok=ok;report.Error=err
H:PostAsync('http://127.0.0.1:8786/results/notification-flow.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
return report
