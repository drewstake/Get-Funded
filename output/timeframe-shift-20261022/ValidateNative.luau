-- Detached native UI/series validation. Nothing is parented into the DataModel.
local H=game:GetService('HttpService');local SE=game:GetService('ScriptEditorService')
local endpoint='http://127.0.0.1:8837/'
local expected=H:JSONDecode(H:GetAsync(endpoint..'expected-original.json'))
local source=H:JSONDecode(H:GetAsync(endpoint..'candidate-bundle.json'))
local histories=H:JSONDecode(H:GetAsync(endpoint..'history-fixtures.json'))
local live=game.ReplicatedStorage.MarketReign
local function unchanged()
 for name,value in pairs(expected)do local m=assert(live:FindFirstChild(name:sub(1,-6)));assert(m.Source:gsub('\r\n','\n')==value,name..' live source changed');assert(SE:GetEditorSource(m):gsub('\r\n','\n')==value,name..' editor changed')end
 assert(not live:FindFirstChild('ChartTimeframes'),'New mapping already installed')
end
unchanged()
local root=Instance.new('Folder');root.Name='DetachedTimeframeValidation'
local gui=Instance.new('ScreenGui');gui.Name='DetachedTimeframeUI';local ctl
local ok,result=xpcall(function()
 local count=0
 for file,value in pairs(source)do local m=Instance.new('ModuleScript');m.Name=file:sub(1,-6);m.Source=value;m.Parent=root;count+=1;if count%20==0 then task.wait()end end
 assert(root.Parent==nil and gui.Parent==nil)
 local M=require(root.MarketClient);local UI=require(root.TerminalUI);local V=require(root.ChartViewport);local T=require(root.ChartTimeframes)
 local report={Checks={},Layouts={},HistoryCases={},Suites={},Detached=true}
 local function check(value,name)assert(value,name);table.insert(report.Checks,name)end
 -- This independent oracle specifies the user-approved mapping, not the implementation's values.
 local oracle={{Label='1m',Key='5m',Seconds=300,Icon='rbxassetid://99798012167473'},
  {Label='5m',Key='15m',Seconds=900,Icon='rbxassetid://98117480331927'},
  {Label='15m',Key='1h',Seconds=3600,Icon='rbxassetid://131026004162086'},
  {Label='1h',Key='1D',Seconds=86400,Icon='rbxassetid://76925568025497'}}
 check(#T.Order==4 and T.Default=='5m','Four visible tiers; new 1m defaults to existing five-minute data')
 for case,data in pairs(histories)do
  local before=H:JSONEncode(data);local session=M.New(nil,true,data)
  check(session.Timeframe=='5m',case..': client default selects the larger stored series')
  local entries={}
  for _,key in ipairs(M.ContractOrder)do
   for _,choice in ipairs(oracle)do
    local bars=session:Candles(key,choice.Key);check(bars==data.CandlesBySeries[key..':'..choice.Key],case..' '..key..' '..choice.Label..': exact original OHLCV objects')
    local state={};local view=assert(V.Resolve(state,bars,choice.Key,M.Contracts[key].Tick,false,{},900))
    check(view.Interval==choice.Seconds,case..' '..key..' '..choice.Label..': candle spacing uses original timestamps')
    local latest=bars[#bars].Time;V.Pan(state,view,50,0,900,400);V.Resolve(state,bars,choice.Key,M.Contracts[key].Tick,false,{},900)
    table.insert(entries,{Contract=key,Visible=choice.Label,Series=choice.Key,Interval=view.Interval,Candles=#bars,Latest=latest})
   end
   check(session.Quotes[key].Open==data.CandlesBySeries[key..':1D'][#data.CandlesBySeries[key..':1D']].Open,case..' '..key..': daily baseline retained')
  end
  session:Destroy();check(H:JSONEncode(data)==before,case..': no history, timestamp or quote mutation')
  report.HistoryCases[case]=entries
 end
 local holder=Instance.new('Frame');holder.Size=UDim2.fromOffset(1440,900);holder.Parent=gui
 ctl=UI.Mount(holder,{Preview=true,PreviewData=histories.CurrentBX})
 local chart=ctl.Chart;local s=ctl.State;local ctx=chart.Ctx
 check(s.Timeframe=='5m'and chart.Geometry~=nil,'Terminal mounts new default with actual candles')
 local originalButton=ctx.button;local originalRefresh=ctx.refresh;local calls={};local refreshes=0
 ctx.button=function(parent,name,label,x,y,w,h,callback,...)
  if name:match('^Time')then calls[name]=callback end
  return originalButton(parent,name,label,x,y,w,h,callback,...)
 end
 ctx.refresh=function()refreshes+=1 end
 for _,layout in ipairs({{Name='Desktop',W=740,H=500,Mobile=false,Head=56,Tools=48},{Name='Portrait',W=390,H=500,Mobile=true,Head=48,Tools=42},{Name='Landscape',W=700,H=340,Mobile=true,Head=46,Tools=0}})do
  table.clear(calls);s.Timeframe='5m';local panel=Instance.new('Frame');panel.Size=UDim2.fromOffset(layout.W,layout.H);panel.Parent=gui
  chart:BuildChrome(panel,layout.W,layout.H,layout.Mobile,layout.Head,layout.Tools)
  local toolbar=panel.Toolbar;local buttons={};local lastRight=-1
  for _,choice in ipairs(oracle)do
   local b=assert(toolbar:FindFirstChild('Time'..choice.Label));local icon=assert(b:FindFirstChild('TimeframeIcon'))
   check(icon.Image==choice.Icon,layout.Name..' '..choice.Label..': correct artwork')
   check(b:GetAttribute('CandleSeries')==choice.Key,layout.Name..' '..choice.Label..': canonical subscription binding')
   check(b.Position.X.Offset>=lastRight and b.Position.X.Offset+b.Size.X.Offset<=toolbar.Size.X.Offset,layout.Name..' '..choice.Label..': non-overlapping control bounds')
   lastRight=b.Position.X.Offset+b.Size.X.Offset
   chart.Placement={Kind='Line'};local before=refreshes;calls[b.Name]()
   check(s.Timeframe==choice.Key and chart.Placement==nil and refreshes==before+1,layout.Name..' '..choice.Label..': actual callback changes tier and cancels placement')
   table.insert(buttons,{Label=choice.Label,Series=choice.Key,X=b.Position.X.Offset,Width=b.Size.X.Offset,Icon=icon.Image})
  end
  check(not toolbar:FindFirstChild('Time1D'),layout.Name..': obsolete fifth choice removed')
  report.Layouts[layout.Name]=buttons;panel:Destroy()
 end
 ctx.button=originalButton;ctx.refresh=originalRefresh;s.Timeframe='5m';s.Overlay='Timeframes';originalRefresh();task.wait();task.wait()
 for _,choice in ipairs(oracle)do
  local b=assert(ctl.Root:FindFirstChild('Choose'..choice.Label,true),'Missing overlay choice '..choice.Label)
  check(b.Label.Text==choice.Label,'Overlay '..choice.Label..': new visible label')
 end
 check(not ctl.Root:FindFirstChild('Choose1D',true),'Overlay obsolete fifth choice removed')
 for _,name in ipairs({'ChartViewportTests','ChartToolsTests','ChartPaintPoolTests'})do
  local run=require(root[name]);local results=type(run)=='function'and run()or run.Run();report.Suites[name]=results
  check(results.Passed==true,name..': existing native suite passes')
  local rows=results.Results or results
  for _,entry in ipairs(rows)do check(entry.Passed,name..': '..tostring(entry.Name))end
 end
 unchanged();report.LiveSourcesAndEditorsUnchanged=true;report.Passed=true;report.CheckedUTC=os.date('!%Y-%m-%dT%H:%M:%SZ')
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();root:Destroy()
H:PostAsync(endpoint..'native-validation.json',H:JSONEncode({Ok=ok,Result=result}),Enum.HttpContentType.ApplicationJson)
if not ok then error(result)end
return {Passed=true,Checks=#result.Checks,Layouts=3,HistoryCases=3,Installed=false}
