-- Native desktop/mobile fixtures with real callbacks, no live remotes or persistence.
local h=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="AccountCleanupUI";shared.Parent=game.ReplicatedStorage
local before=game.ReplicatedStorage.MarketReign:Clone();before.Name="AccountCleanupBeforeUI";before.Parent=game.ReplicatedStorage
local originals=h:JSONDecode(h:GetAsync("http://127.0.0.1:8774/backups/account-cleanup-before-20260929/studio/sources.json"))
for _,m in ipairs(before:GetChildren())do if m:IsA("LuaSourceContainer")then m.Source=originals["ReplicatedStorage.MarketReign."..m.Name]or m.Source end end
local server=game.ServerScriptService.MarketReign:Clone();server.Name="AccountCleanupUI";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="AccountCleanupUI";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local live={};local report={Layouts=0,Interactions=0,Issues={},UnchangedSurfaces={}}
local function hooks(root)
 root.TerminalUI.Source=root.TerminalUI.Source:gsub('b%.Activated:Connect%(function%(%.%.%.%)',function()
  return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
 end)
end
hooks(shared);hooks(before)
shared.StatsPieces.Source=shared.StatsPieces.Source:gsub('caption%(%)%;return api',function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestDropdown";hook.Parent=trigger;hook.OnInvoke=function(action,key)return api[action](api,key)end;caption();return api'
end)
local function deep(v)if type(v)~="table"then return v end local out={}for k,x in pairs(v)do out[k]=deep(x)end return out end
local function check(v,msg)assert(v,msg)end
local function signature(root)
 local rows={}
 local function visit(o,path)
  if o:IsA("BindableFunction")then return end
  local row={path,o.ClassName};local props={}
  if o:IsA("GuiObject")then props={"Position","Size","AnchorPoint","Visible","BackgroundColor3","BackgroundTransparency","BorderSizePixel","ZIndex","Rotation","ClipsDescendants","Active","Selectable"}end
  if o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox")then for _,p in ipairs({"Text","FontFace","TextColor3","TextSize","TextScaled","TextWrapped","TextXAlignment","TextStrokeColor3","TextStrokeTransparency"})do table.insert(props,p)end end
  if o:IsA("ImageLabel")or o:IsA("ImageButton")then for _,p in ipairs({"Image","ImageColor3","ImageTransparency","ScaleType"})do table.insert(props,p)end end
  if o:IsA("UICorner")then props={"CornerRadius"}elseif o:IsA("UIStroke")then props={"Color","Thickness","Transparency"}elseif o:IsA("UIGradient")then props={"Color","Transparency","Rotation"}end
  for _,p in ipairs(props)do table.insert(row,p.."="..tostring(o[p]))end
  table.insert(rows,table.concat(row,"|"));for _,child in ipairs(o:GetChildren())do visit(child,path.."/"..child.Name)end
 end
 visit(root,root.Name);table.sort(rows);return table.concat(rows,"\n")
end
local function audit(root,tag)
 for _,v in ipairs(root:GetDescendants())do
  if v:IsA("TextLabel")and v.Visible and v.Text~="" and not v.TextFits and not v.TextScaled and v.TextTruncate==Enum.TextTruncate.None then
   table.insert(report.Issues,tag.." text "..v:GetFullName():gsub(".*Canvas%.",""))
  end
 end
 report.Layouts+=1
end
local ok,err=pcall(function()
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts);local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local e=E.new(C,85);local f=F.new(e,L,C);f:Start("fixture");f:Flag("fixture","TutorialDone")
 local p=f:Profile("fixture");for _=1,4 do check(f:Restart("fixture",p.Active),"create retained attempts")end
 local a=e.Accounts[f:Owner("fixture")];a.Realized=38000;a.Balance=43000;f:Evaluate("fixture")
 for _,tier in ipairs({"F10K","F25K","F50K","F100K"})do f:Activate("fixture",tier)end
 e.Accounts[p.Tiers.F10K.Account].Depleted=true;e.Accounts[p.Tiers.F10K.Account].Locked=true
 e.Accounts[p.Tiers.F25K.Account].Retired=true;e.Accounts[p.Tiers.F50K.Account].Locked=true;e.Accounts[p.Tiers.F100K.Account].LegacyRetired=true
 a.Realized=-500;a.Balance=4500;f:Evaluate("fixture")
 local pf=f:View("fixture");local stats=f:Stats("fixture");local key=p.Active
 check(key=="F5K:5" and pf.UsableCount==1,"fixture must have only fifth $5K usable")
 local sessions={};local sends=0
 local function setup(root)
  local M=require(root.MarketClient);local original=M.New
  M.New=function()
   local snapshot=e:Snapshot(a.Id,"BX","1m",true);snapshot.CandlesBySeries={}
   local s=original(nil,true,snapshot);sessions[root]=s
   s.Preview=false;s.Ready=true;s.CanTrade=true;s.AccountKey=key;s.AccountToken=a.Id
   s.Portfolio=deep(pf);s.Stats=deep(stats);s.SummaryData=e:Summary(a);s.StatsAt=1
   function s:Send(action,req)
    if action=="Restart"then
     sends+=1;local id=sends
     task.delay(.05,function()
      local yes,message=f:Restart("fixture",req.Tier)
      s.Portfolio=f:View("fixture");s.Stats=f:Stats("fixture");s.StatsAt+=1
      s.AccountKey=p.Active;s.AccountToken=f:Owner("fixture");s.SummaryData=e:Summary(e.Accounts[f:Owner("fixture")])
      s.Replies:Fire({Kind="Restart",Tier=req.Tier,RequestId=id,Ok=yes,Message=message});s.Changed:Fire()
     end)
     return true,"Sent","Orders",id
    end
    return true,"Fixture","Orders",0
   end
   return s
  end
  return require(root.TerminalUI)
 end
 local UI=setup(shared);local Old=setup(before)
 local function mount(ui,w,hh)
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(w,hh);host.Parent=gui
  local ctl=ui.Mount(host);table.insert(live,{ctl,host});task.wait();task.wait()
  return ctl,host
 end
 local function show(ctl,screen,overlay)
  ctl.State.Screen=screen;ctl.State.Nav=screen;ctl.State.Overlay=overlay;ctl.State.Sheet=false;ctl.State.Toast=nil
  ctl.Root.UIDiagnostics:Invoke("Render");task.wait();task.wait()
  check(not ctl.Root:GetAttribute("RenderError"),tostring(ctl.Root:GetAttribute("RenderError")))
 end
 local sizes={{1920,1080},{1440,900},{1280,720},{1024,600},{844,390},{390,844},{360,640},{320,568}}
 for _,size in ipairs(sizes)do
  local ctl,host=mount(UI,size[1],size[2]);local s=sessions[shared]
  local tag=size[1].."x"..size[2]
  for _,screen in ipairs({"Dashboard","Stats","Trade","Shop","Leaderboard"})do
   show(ctl,screen)
   local canvas=ctl.Root.Canvas;local nav=canvas:FindFirstChild("Sidebar")or canvas.MobileNavigation
   for _,name in ipairs({"Positions","Review","Learn"})do check(not nav:FindFirstChild("Nav"..name),tag.." removed navigation remains")end
   for _,name in ipairs({"Trade","Accounts","Shop","Stats","Leaderboard"})do check(nav:FindFirstChild("Nav"..name),tag.." navigation missing")end
   if screen=="Dashboard"then
    check(not canvas.Dashboard:FindFirstChild("BlownTitle"),"history section")
    for _,row in ipairs(pf.Accounts)do check((canvas.Dashboard:FindFirstChild("Tier"..row.Key)~=nil)==row.Usable,"inactive dashboard card")end
    local reset=canvas.Dashboard["Tier"..key].ResetAccount
    check(reset.Active and reset.ControlLabel.Text=="Reset Account","drawdown reset hidden")
    reset.TestActivate:Invoke();task.wait();task.wait()
    check(sends==0 and ctl.State.Overlay=="ResetAccount","click skipped confirmation")
    local dialog=canvas.Dialog
    check(dialog.AbsoluteSize.X<=size[1] and dialog.AbsoluteSize.Y<=size[2],"reset dialog exceeds viewport")
    for _,name in ipairs({"Settlement","FreshBalance","Preserved","CancelReset","ConfirmReset"})do check(dialog.Content:FindFirstChild(name),"confirmation missing "..name)end
    audit(dialog,tag.." reset")
    dialog.Content.CancelReset.TestActivate:Invoke();task.wait();task.wait()
    check(sends==0 and not ctl.State.Overlay,"cancel submitted reset")
    report.Interactions+=2
   elseif screen=="Stats"then
    local page=canvas.Stats
    check(page:GetAttribute("Scope")=="F5K" and page.FundedDropdown.FundedDropdownLabel.Text=="$5K Funded","wrong default account")
    for _,name in ipairs({"ScopeDropdown","ScopeLabel","ScopeSummary","ScopeInfo","Coverage"})do check(not page:FindFirstChild(name),"removed scope/footer remains")end
    page.FundedDropdown.TestDropdown:Invoke("Open");task.wait()
    local options=canvas.StatsOverlays.DropdownOverlay.DropdownMenu.Options:GetChildren();check(#options==1 and options[1]:GetAttribute("Key")=="F5K","historical/locked tiers in picker")
    check(options[1].Label.Text=="$5K Funded","attempt suffix in stats")
    page.FundedDropdown.TestDropdown:Invoke("Close")
    check(page:GetAttribute("NetRealized")==stats.Scopes[2].Life.Net,"stats calculation changed")
    report.Interactions+=2
   elseif screen=="Trade"then
    if canvas:FindFirstChild("OrderTicket")then check(canvas.OrderTicket.Subtitle.Text=="$5K Funded","trade label has attempt suffix")end
    if canvas:FindFirstChild("TopNavigation")then
     canvas.TopNavigation.TradeActivity.TestActivate:Invoke();task.wait();task.wait()
     check(canvas.Activity.TabPositions and canvas.Activity.TabOrders and canvas.Activity.TabHistory,"mobile trade management inaccessible")
     canvas.Activity.TabOrders.TestActivate:Invoke();task.wait();task.wait();check(ctl.State.Tab=="Orders","mobile orders inaccessible")
     canvas.OptionsSheet.Done.TestActivate:Invoke();task.wait();task.wait();report.Interactions+=3
    else check(canvas.Activity.TabPositions and canvas.Activity.TabOrders,"desktop trade management missing")end
   end
   audit(canvas,tag.." "..screen)
  end
  ctl:Destroy();host:Destroy()
 end
 -- Status changes use the actual MarketClient Changed -> TerminalUI rebuild path.
 local ctl,host=mount(UI,1440,900);local s=sessions[shared];show(ctl,"Stats")
 local saved=deep(s.Portfolio)
 local function packet(portfolio,data)
  s.Portfolio=portfolio;if data then s.Stats=data;s.StatsAt+=1 end
  s.Changed:Fire();task.wait();task.wait()
 end
 local ten
 for _,r in ipairs(s.Portfolio.Accounts)do if r.Tier=="F10K"then r.Usable=true;r.Breached=false;r.Depleted=false;ten=r end end
 packet(s.Portfolio)
 check(ctl.Root.Canvas.Stats.FundedDropdown.TestDropdown:Invoke("Choose","F10K"),"new active option not selectable")
 task.wait();task.wait();check(ctl.State.StatsScope=="F10K","selection")
 ten.State="Inactive";packet(s.Portfolio)
 check(ctl.State.StatsScope=="F5K","inactive selection not defaulted")
 for _,flag in ipairs({"Retired","Locked","Inactive","Depleted","Breached"})do
  local pf2=deep(saved);for _,r in ipairs(pf2.Accounts)do if r.Key==key then r[flag]=true end end
  packet(pf2);check(ctl.Root.Canvas.Stats:GetAttribute("State")=="Empty","bad account status remained: "..flag)
 end
 packet(deep(saved),{Ready=true,Scopes={}})
 check(ctl.Root.Canvas.Stats:GetAttribute("State")=="Error" and ctl.Root.Canvas.Stats.FundedDropdown,"missing data state lost")
 packet(deep(saved),{Loading=true});check(ctl.Root.Canvas.Stats:GetAttribute("State")=="Loading","loading")
 packet(deep(saved),{Error="Fixture error"});check(ctl.Root.Canvas.Stats:GetAttribute("State")=="Error","error")
 packet(deep(saved),deep(stats));report.StatusRefreshes=10
 -- Confirm once through real UI callbacks; repeated clicks dispatch a single Restart.
 show(ctl,"Dashboard");ctl.Root.Canvas.Dashboard["Tier"..key].ResetAccount.TestActivate:Invoke();task.wait();task.wait()
 local confirm=ctl.Root.Canvas.Dialog.Content.ConfirmReset;local count=#p.Ledger
 for _=1,10 do confirm.TestActivate:Invoke()end
 task.wait(.15);check(sends==1 and #p.Ledger==count+1,"repeated clicks created more than one reset")
 check(ctl.State.Screen=="Trade" and not ctl.State.PendingRestart and not ctl.State.Overlay,"reset reply did not restore trading")
 check(ctl.Root.Canvas.OrderTicket.Subtitle.Text=="$5K Funded","post-reset trade label")
 report.ResetRequests=sends;ctl:Destroy();host:Destroy()
 -- Whole surface/style equality for unrelated pages and shared trading widgets.
 for _,size in ipairs({{1440,900},{390,844}})do
  for _,entry in ipairs({{"Shop","Shop"},{"Leaderboard","Leaderboard"},{"Trade","Chart"},{"Trade","AccountSummary"},{"Trade","TradeDock"},{"Trade","Activity"},{"Trade","Dialog","Settings"},{"Trade","Dialog","Help"},{"Trade","Dialog","Account"}})do
   local prints={};local present={}
   for i,ui in ipairs({Old,UI})do
    local c,holder=mount(ui,size[1],size[2]);show(c,entry[1],entry[3])
    local surface=c.Root.Canvas:FindFirstChild(entry[2]);present[i]=surface~=nil;prints[i]=surface and signature(surface)
    c:Destroy();holder:Destroy()
   end
   check(present[1]==present[2] and prints[1]==prints[2],"unrelated surface changed: "..entry[2].."/"..tostring(entry[3]).." "..size[1])
   if present[1]then table.insert(report.UnchangedSurfaces,entry[2].."/"..tostring(entry[3]).." "..size[1])end
  end
 end
end)
for _,item in ipairs(live)do pcall(function()item[1]:Destroy();item[2]:Destroy()end)end
gui:Destroy();shared:Destroy();before:Destroy();server:Destroy()
if not ok then report.Error=tostring(err)end
local all=h:JSONDecode(h:GetAsync("http://127.0.0.1:8774/output/account-cleanup-validation.json",true));all.UI=report
h:PostAsync("http://127.0.0.1:8774/results",h:JSONEncode(all),Enum.HttpContentType.ApplicationJson)
return report
