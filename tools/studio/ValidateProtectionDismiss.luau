-- Disposable native UI callbacks and captured requests; never sends live orders or writes saved data.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ProtectionDismissQA";shared.Parent=game.ReplicatedStorage
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
local gui=Instance.new("ScreenGui");gui.Name="ProtectionDismissQA";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI);local Config=require(shared.MarketConfig)
 local quotes,cache={},{}
 for _,key in ipairs(Config.ContractOrder)do
  local c=Config.Contracts[key];quotes[key]={Last=c.Last,Bid=c.Last-c.Tick,Ask=c.Last+c.Tick}
  for _,tf in ipairs(Config.Timeframes)do
   local candles={};for i=1,80 do candles[i]={Time=i*tf[2],Open=c.Last,Close=c.Last+c.Tick,High=c.Last+2*c.Tick,Low=c.Last-2*c.Tick,Volume=50}end
   cache[key..":"..tf[1]]=candles
  end
 end
 local report={Passed=true,Checks=0,Layouts={}}
 local function check(v,message)assert(v,message);report.Checks+=1 end
 local function amount(a,b)return math.abs(a-b)<.000001 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1280,800}})do
  local holder=Instance.new("Frame");holder.Size=UDim2.fromOffset(size[1],size[2]);holder.Parent=gui
  ctl=UI.Mount(holder,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=4800,Step=1}})
  local s,ctx=ctl.State,ctl.Chart.Ctx;local session=ctx.Session
  local requests={};session.Preview=false;session.Ready=true;session.CanTrade=true
  session.Send=function(self,action,request)
   self.NextId+=1;table.insert(requests,{Action=action,Value=table.clone(request or {})})
   return true,"Captured by fixture","Positions",self.NextId
  end
  local function refresh()ctx.refresh();task.wait(.04);check(not ctl.Root:GetAttribute("RenderError"),"No render error")end
  local function get(path)
   local node=ctl.Root.Canvas
   for part in path:gmatch("[^.]+")do node=assert(node:FindFirstChild(part),"Missing "..path)end
   return node
  end
  local function click(path)get(path).TestActivate:Invoke();task.wait(.04)end
  local function open()
   local button=ctl.Root.Canvas:FindFirstChild("RiskControls",true)or get("OrderTicket.Fields.StopCard.Settings")
   button.TestActivate:Invoke();task.wait(.04)
   local panel=get("ProtectionDialog")
   check(not panel:FindFirstChild("SaveSettings",true)and not panel:FindFirstChild("Cancel",true),"No save or cancel buttons")
   return panel
  end
  local function saved(stopOn,targetOn)
   check(s.Overlay==nil and s.ProtectionDraft==nil and not ctl.Root.Canvas:FindFirstChild("ProtectionDialog"),"Close dismisses the dialog")
   check(s.StopOn==stopOn and s.TargetOn==targetOn,"Ticket uses closed dialog settings")
   check(session.ProtectionPreferences.StopOn==stopOn and session.ProtectionPreferences.TargetOn==targetOn,"Settings reach persistent preference path")
   local last=requests[#requests];check(last and last.Action=="ProtectionPreferences"and last.Value.StopOn==stopOn and last.Value.TargetOn==targetOn,"One preference request contains both toggles")
  end
  open();click("ProtectionDialog.Fields.StopProtection.Toggle");click("ProtectionDialog.Fields.TargetProtection.Toggle")
  check(#requests==0 and s.StopOn and s.TargetOn,"Toggles remain a draft until closing")
  click("ProtectionDialog.Dismiss");saved(false,false);check(#requests==1,"X saves once")
  open();check(not get("ProtectionDialog.Fields.StopProtection.Toggle"):GetAttribute("On")and not get("ProtectionDialog.Fields.TargetProtection.Toggle"):GetAttribute("On"),"Reopening retains both disabled switches")
  click("OverlayBackdrop");saved(false,false)
  local buy=ctl.Root.Canvas:FindFirstChild("BuyLong",true);buy.TestActivate:Invoke();task.wait(.04)
  local order=requests[#requests]
  check(order.Action=="Place"and order.Value.StopDollars==nil and order.Value.TargetDollars==nil,"Next order has no disabled SL or TP")
  s.PendingOrder=nil;s.Toast=nil;refresh()
  open();click("ProtectionDialog.Fields.StopProtection.Toggle");click("ProtectionDialog.Fields.TargetProtection.Toggle")
  get("ProtectionDialog.Fields.StopProtection.Distance.Value").Text="$123.45"
  get("ProtectionDialog.Fields.TargetProtection.Distance.Value").Text="$456.78"
  click("ProtectionDialog.Dismiss");saved(true,true)
  check(amount(s.StopDollars,123.45)and amount(s.TargetDollars,456.78)and amount(session.ProtectionPreferences.StopDollars,123.45),"X commits typed amounts even before focus loss")
  open();get("ProtectionDialog.Fields.StopProtection.Distance.Value").Text="234.56"
  click("OverlayBackdrop");saved(true,true);check(amount(s.StopDollars,234.56),"Backdrop commits typed amount")
  open();get("ProtectionDialog.Fields.StopProtection.Distance.Value").Text="-1"
  local before=#requests;click("ProtectionDialog.Dismiss")
  check(s.Overlay=="Protection"and s.ProtectionDraft~=nil and #requests==before and amount(s.StopDollars,234.56),"Invalid amount keeps dialog open without saving")
  get("ProtectionDialog.Fields.StopProtection.Distance.Value").Text="345.67"
  local save=session.SetProtectionPreferences
  session.SetProtectionPreferences=function()return false,"Fixture validation failure"end
  click("ProtectionDialog.Dismiss")
  check(s.Overlay=="Protection"and amount(s.StopDollars,234.56)and #requests==before,"Failed save retains the draft and prior defaults")
  session.SetProtectionPreferences=save;click("ProtectionDialog.Dismiss");saved(true,true)
  check(amount(s.StopDollars,345.67),"Retry saves retained draft")
  local panel=open();local pos=panel.AbsolutePosition-holder.AbsolutePosition
  check(pos.X>=0 and pos.Y>=0 and pos.X+panel.AbsoluteSize.X<=size[1]+1 and pos.Y+panel.AbsoluteSize.Y<=size[2]+1,"Popup stays within screen")
  check(panel.Actions.Position.Y.Offset>=panel.Fields.Position.Y.Offset+panel.Fields.Size.Y.Offset,"Footer stays clear of inputs")
  for _,node in ipairs(panel:GetDescendants())do
   if node:IsA("TextLabel")and node.Text~=""then check(node.TextFits,"Text fits: "..node.Name)end
  end
  table.insert(report.Layouts,{Width=size[1],Height=size[2],PopupHeight=panel.Size.Y.Offset})
  ctl:Destroy();ctl=nil;holder:Destroy()
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end
gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result
