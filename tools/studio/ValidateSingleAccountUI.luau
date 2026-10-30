-- Isolated Edit-mode UI/trading fixture. No DataStore, player profile or live remote.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="SingleAccountQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="SingleAccountQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server}) do for _,m in ipairs(folder:GetDescendants()) do
 if m:IsA('LuaSourceContainer') then m.Source=m.Source:gsub('game%.ReplicatedStorage%.MarketReign','game.ReplicatedStorage.SingleAccountQA'):gsub('game%.ServerScriptService%.MarketReign','game.ServerScriptService.SingleAccountQA') end
end end
local gui=Instance.new('ScreenGui');gui.Name='SingleAccountQA';gui.IgnoreGuiInset=true;gui.DisplayOrder=100;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local M=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local config=require(shared.MarketConfig);local ladder=require(shared.ProgressionConfig)
 local e=E.new(config,916);local f=F.new(e,ladder,config);f:Join('isolated-ui')
 local original=M.New;local session
 M.New=function()
  local data={Quotes={},CandlesBySeries={},Time=3600,Step=1}
  for _,key in ipairs(config.ContractOrder) do
   local spec=config.Contracts[key];data.Quotes[key]={Last=spec.Last,Open=spec.Last,Bid=spec.Last-spec.Tick,Ask=spec.Last+spec.Tick}
   for _,tf in ipairs(config.Timeframes) do
    local list={};for i=1,60 do local price=spec.Last+math.sin(i*.7)*8*spec.Tick
     list[i]={Time=(i-1)*tf[2],Open=price,Close=price+spec.Tick,High=price+3*spec.Tick,Low=price-2*spec.Tick,Volume=10}
    end;data.CandlesBySeries[key..':'..tf[1]]=list
   end
  end
  session=original(nil,true,data);session.Preview=false;session.Ready=true;session.CanTrade=true;session.ConnectionStatus='ISOLATED TEST · NOT SAVED'
  local function update()
   local a=e.Accounts[f:Owner('isolated-ui')];local snap=e:Snapshot(a.Id,'BX','1m',true)
   session.Portfolio=f:View('isolated-ui');session.AccountKey=a.Id;session.AccountToken=a.Id
   session.SummaryData=snap.Summary;session.Positions=snap.Positions;session.Orders=snap.Orders;session.History=snap.History;session.Fills=snap.Fills
   session.Limit=snap.Limit;session.Capacity=snap.Capacity;session.Stats=f:Stats('isolated-ui')
  end
  session.Send=function(_,action,req)
   if action=='Subscribe' or action=='Stats' then return true,'Fixture','Orders',0 end
   session.NextId+=1;local requestId=session.NextId;req=req or {};req.Action=action
   local accepted,value
   if action=='Restart' then accepted,value=f:Restart('isolated-ui',session.AccountToken)
   elseif action=='Flag' then accepted,value=f:Flag('isolated-ui',req.Stage)
   else accepted,value=F.Perform(e,f:Owner('isolated-ui'),req) end
   e:ProcessStops();f:Evaluate('isolated-ui');update()
   task.defer(function()
    session.Replies:Fire({Ok=accepted,Message=type(value)=='table' and F.Describe(value) or value,Kind=action,RequestId=requestId,Result=type(value)=='table' and value or nil})
    for _,event in ipairs(f:TakeEvents('isolated-ui') or {}) do session:_event(event) end
    session.Changed:Fire()
   end)
   return true,'Fixture','Orders',requestId
  end
  update();return session
 end
 local report={Layouts={},Flow={},Suites={}}
 for _,name in ipairs({'SingleAccountTests','MarketTests','WorldTests','TradeLimitsTests','TradeAmendmentTests','SecurityTests'}) do
  local suite=require(server[name]);report.Suites[name]=type(suite)=='function' and suite() or suite.Run()
 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1000,600},{1280,720},{1920,1080}}) do
  local host=Instance.new('Frame');host.Name='Viewport';host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  ctl=UI.Mount(host);task.wait(.1);session.Changed:Fire();task.wait(.05)
  for _,mode in ipairs({'Trade','Coach1','Coach2','Coach3','Coach4','Coach5','Progress','Stats','CurrentStats','Leaderboard','Help','Blown'}) do
   local state=ctl.State;state.Screen=(mode=='Progress' or mode=='Stats' or mode=='Leaderboard') and mode or mode=='CurrentStats' and 'Stats' or 'Trade'
   state.StatsPeriod=mode=='CurrentStats' and 'Current' or 'Life';state.CoachDismissed=true;state.Coach=tonumber(mode:match('Coach(%d)'));state.Overlay=nil
   local a=e.Accounts[f:Owner('isolated-ui')];local old=a.Depleted
   if mode=='Blown' then a.Depleted=true;state.BlownTier=a.Id;state.BlownEvent=tostring(f:Profile('isolated-ui').Run);state.Overlay='Blown'
   elseif mode=='Help' then state.Overlay='Help' end
   session.Portfolio=f:View('isolated-ui');ctl.Root.UIDiagnostics:Invoke('Render');task.wait(.06)
   local errors={};local overflow={}
   if ctl.Root:GetAttribute('RenderError') then table.insert(errors,ctl.Root:GetAttribute('RenderError')) end
   if ctl.Root:GetAttribute('ChartError') then table.insert(errors,ctl.Root:GetAttribute('ChartError')) end
   for _,obj in ipairs(ctl.Root.Canvas:GetDescendants()) do
    if obj:IsA('TextLabel') and obj.Visible and obj.Text~='' and not obj.TextFits and not obj.TextScaled and obj.TextTruncate==Enum.TextTruncate.None then
     table.insert(overflow,{Path=obj:GetFullName(),Text=obj.Text,Size={obj.AbsoluteSize.X,obj.AbsoluteSize.Y}})
    end
    if obj.Name=='NavAccounts' or obj.Name=='NavShop' or obj.Name=='AccountSwitcher' or obj.Name=='CopyTrading' or obj.Name=='SelectAccount' then table.insert(errors,'Obsolete control '..obj.Name) end
   end
   table.insert(report.Layouts,{Width=size[1],Height=size[2],Mode=mode,Errors=errors,Overflow=overflow})
   a.Depleted=old
  end
  -- The real MarketClient methods and UI coach respond to fills from this disposable engine.
  ctl.State.Screen='Trade';ctl.State.Overlay=nil;ctl.State.Coach=3;ctl.State.CoachBase=nil
  ctl.Root.UIDiagnostics:Invoke('Render');session.Changed:Fire();task.wait(.05)
  assert(session:Place('BX',1,1,'Market',nil,100,200));task.wait(.1)
  assert(ctl.State.Coach==4,'Coach did not follow entry fill')
  assert(session:Close('BX'));task.wait(.1)
  assert(ctl.State.Coach==5,'Coach did not follow closing fill')
  assert(session.Portfolio.Awards.FirstTrade,'First trade title missing')
  table.insert(report.Flow,{Width=size[1],GuidedTrade=true,Landing='Trade',Balance=session:Summary().Balance})
  ctl:Destroy();ctl=nil;host:Destroy()
 end
 e:Audit();return report
end,debug.traceback)
if ctl then ctl:Destroy() end;gui:Destroy();shared:Destroy();server:Destroy()
assert(ok,result)
return result
