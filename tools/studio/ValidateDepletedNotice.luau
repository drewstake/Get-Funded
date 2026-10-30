-- Isolated native UI fixture. No remote orders, real profiles or DataStore access.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="DepletedNoticeUIShared";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="DepletedNoticeUIServer"
for _,m in ipairs(server:GetDescendants())do if m:IsA("BaseScript")then m.Enabled=false end end;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do if m:IsA("LuaSourceContainer")then
 m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.DepletedNoticeUIShared")
  :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.DepletedNoticeUIServer")
end end end
local Market=require(shared.MarketClient);local Board=require(shared.LeaderboardClient)
local original,originalBoard=Market.New,Board.new
local C=require(shared.MarketConfig)
local e=require(server.MarketEngine).new(C,126)
local f=require(server.FundedAccounts).new(e,require(shared.ProgressionConfig),C)
f:Join("notice-test");f:Flag("notice-test","TutorialDone")
local id=f:Owner("notice-test");local session
local quotes,cache={},{}
for _,key in ipairs(C.ContractOrder)do
 local price=C.Contracts[key].Last;quotes[key]={Last=price,Open=price}
 for _,tf in ipairs(C.Timeframes)do cache[key..":"..tf[1]]={{Time=0,Open=price,High=price,Low=price,Close=price,Volume=1}}end
end
Market.New=function()
 session=original(nil,true,{Quotes=quotes,CandlesBySeries=cache,Time=1,Step=1})
 session.Preview=false;session.Ready=true;session.CanTrade=true;session.AccountKey=id;session.AccountToken=id
 session.Portfolio=f:View("notice-test");session.Stats=f:Stats("notice-test")
 session.Send=function()return false,"Isolated UI fixture"end
 return session
end
Board.new=function()return originalBoard(true,{State="Empty",Rows={}})end
local gui=Instance.new("ScreenGui");gui.Name="DepletedNoticeQA";gui.Parent=game.StarterGui
local host=Instance.new("Frame");host.Size=UDim2.fromOffset(1280,800);host.Parent=gui
local ctl
local ok,result=xpcall(function()
 ctl=require(shared.TerminalUI).Mount(host)
 local s=ctl.State;local checks=0
 local function render()ctl.Root.UIDiagnostics:Invoke("Render")end
 local function check(v,message)checks+=1;assert(v,message)end
 session:_event({Kind="TradeClosed",Account=id,TradeId=1,Reason="Trade",Pnl=12,Rewards={"Fixture title"}})
 render();check(s.ToastPnl==12 and s.ToastFollowup~=nil,"Normal close notification missing")
 local a=e.Accounts[id];a.Depleted=true;a.Locked=true;f:Evaluate("notice-test")
 session.Portfolio=f:View("notice-test")
 for _,event in ipairs(f:TakeEvents("notice-test")or{})do session:_event(event)end
 render()
 check(s.Overlay=="Blown","Account-blown message missing")
 check(s.Toast==nil and s.ToastPnl==nil and s.ToastFollowup==nil,"Close card remains under blown message")
 session:_event({Kind="TradeClosed",Account=id,TradeId=2,Reason="Account depleted",Pnl=-10000})
 session:_event({Kind="TradeClosed",Account=id,TradeId=3,Reason="Trade",Pnl=-10000})
 render();check(s.ToastPnl==nil and s.Overlay=="Blown","Delayed close revived the duplicate message")
 task.wait(3.2);render();check(s.Toast==nil,"Cancelled close timer revived a follow-up")
 -- A new healthy attempt still gets its normal close notification.
 assert(f:Restart("notice-test",id));id=f:Owner("notice-test")
 session.AccountKey=id;session.AccountToken=id;session.Portfolio=f:View("notice-test");s.Overlay=nil
 session:_event({Kind="TradeClosed",Account=id,TradeId=4,Reason="Stop loss",Pnl=-25})
 render();check(s.ToastPnl==-25,"Healthy new account lost its ordinary close message")
 return {Passed=true,Cases=checks}
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();Market.New=original;Board.new=originalBoard
shared:Destroy();server:Destroy()
if not ok then error(result)end
return result
