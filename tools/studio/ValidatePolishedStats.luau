-- Isolated native integration/layout checks. Synthetic closes are computed by the real server modules.
-- Run through the local verification bridge; originals are read from the saved source backup.
local h=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign:Clone() shared.Name="PolishedStatsChecks" shared.Parent=game.ReplicatedStorage
local baseline=game.ReplicatedStorage.MarketReign:Clone() baseline.Name="PolishedStatsBeforeChecks"
local originals=h:JSONDecode(h:GetAsync("http://127.0.0.1:8772/backups/polished-stats-before-20260929/studio/sources.json"))
for _,m in ipairs(baseline:GetChildren())do if m:IsA("LuaSourceContainer")then
 local original=originals["ReplicatedStorage.MarketReign."..m.Name]
 if original then m.Source=original else m:Destroy()end
end end
baseline.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone() server.Name="PolishedStatsChecks" server.MarketServer.Enabled=false server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui") gui.Name="PolishedStatsChecks" gui.IgnoreGuiInset=true gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.Parent=game.StarterGui
local report={Layouts=0,Interactions=0,States={},UnchangedPages={},Issues={}}
local live={}
local function hook(source)
 return source:gsub('b%.Activated:Connect%(function%(%.%.%.%)',function()
  return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
 end):gsub('if options%.Preview then return "Trade"end','if options.Preview then return s.Screen or "Trade"end')
end
shared.TerminalUI.Source=hook(shared.TerminalUI.Source)
baseline.TerminalUI.Source=hook(baseline.TerminalUI.Source)
shared.StatsView.Source=shared.StatsView.Source:gsub('local function bind%(button,fn%) return button%.Activated:Connect%(fn%) end',function()
 return 'local function bind(button,fn) local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=button;return button.Activated:Connect(fn) end'
end)
shared.StatsPieces.Source=shared.StatsPieces.Source:gsub('caption%(%)%;return api',function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestDropdown";hook.Parent=trigger;hook.OnInvoke=function(action,key) return api[action](api,key)end;caption();return api'
end)
local function deep(v)if type(v)~="table"then return v end local out={}for k,x in pairs(v)do out[k]=deep(x)end return out end
local function check(ok,msg)assert(ok,msg)end
local function audit(page,tag)
 local cw=page.AbsoluteSize.X
 for _,v in ipairs(page:GetDescendants())do
  local shown=true local p=v
  while p and p~=page do if p:IsA("GuiObject")and not p.Visible then shown=false end p=p.Parent end
  if shown and v:IsA("GuiObject")then
   if v.AbsolutePosition.X<page.AbsolutePosition.X-2 or v.AbsolutePosition.X+v.AbsoluteSize.X>page.AbsolutePosition.X+cw+2 then
    if not v.Name:find("Watermark")then table.insert(report.Issues,tag.." overflow "..v:GetFullName())end
   end
   if v:IsA("TextLabel")and v.Text~="" and not v.TextFits then table.insert(report.Issues,tag.." text "..v.Name.." "..v.Text)end
  end
 end
 local kids={}for _,v in ipairs(page:GetChildren())do if v:IsA("GuiObject")and v.Visible and not v.Name:match("Depth$")then table.insert(kids,v)end end
 for i,a in ipairs(kids)do for j=i+1,#kids do local b=kids[j]
  local ap,bp,as,bs=a.AbsolutePosition,b.AbsolutePosition,a.AbsoluteSize,b.AbsoluteSize
  if ap.X<bp.X+bs.X-1 and bp.X<ap.X+as.X-1 and ap.Y<bp.Y+bs.Y-1 and bp.Y<ap.Y+as.Y-1 then table.insert(report.Issues,tag.." overlap "..a.Name.."/"..b.Name)end
 end end
 report.Layouts+=1
end
local function signature(root)
 local rows={}
 local function visit(o,path)
  if o:IsA("BindableFunction")then return end
  local row={path,o.ClassName}
  local props={}
  if o:IsA("GuiObject")then props={"Position","Size","AnchorPoint","Visible","BackgroundColor3","BackgroundTransparency","BorderSizePixel","ZIndex","Rotation","ClipsDescendants","Active","Selectable"}end
  if o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox")then for _,p in ipairs({"Text","FontFace","TextColor3","TextSize","TextScaled","TextWrapped","TextXAlignment","TextStrokeColor3","TextStrokeTransparency"})do table.insert(props,p)end end
  if o:IsA("ImageLabel")or o:IsA("ImageButton")then for _,p in ipairs({"Image","ImageColor3","ImageTransparency","ScaleType"})do table.insert(props,p)end end
  if o:IsA("UICorner")then props={"CornerRadius"}elseif o:IsA("UIStroke")then props={"Color","Thickness","Transparency"}elseif o:IsA("UIGradient")then props={"Color","Transparency","Rotation"}end
  for _,p in ipairs(props)do table.insert(row,p.."="..tostring(o[p]))end
  table.insert(rows,table.concat(row,"|"))
  for _,child in ipairs(o:GetChildren())do visit(child,path.."/"..child.Name)end
 end
 visit(root,root.Name) table.sort(rows) return table.concat(rows,"\n")
end
local ok,result=pcall(function()
 local E=require(server.MarketEngine) local F=require(server.FundedAccounts) local S=require(server.TradeStats)
 local C=require(shared.MarketConfig) local L=require(shared.ProgressionConfig)
 local e=E.new(C,91) local f=F.new(e,L,C) f:Start("stats-fixture") f:Flag("stats-fixture","TutorialDone")
 local a=e.Accounts[f:Owner("stats-fixture")]
 local function add(account,values,dated)
  for i,value in ipairs(values)do S.Add(account.Stats,{Pnl=value,ClosedAt=dated and 1789948800+i*86400 or nil,TradeId=i});account.Realized+=value;account.Balance+=value;account.CompletedTrades=(account.CompletedTrades or 0)+1 end
 end
 add(a,{750,-225,0,-50},true)
 local rich=f:Stats("stats-fixture") local pf=f:View("stats-fixture")
 local b=e:AddAccount("stats-old",5000,5,.8,true) add(b,{-440,120},false) b.Retired=true b.Depleted=true
 local combined=S.Finish(S.Include(S.Include(S.Empty(),e,a),e,b))
 rich.Scopes[1].Life=combined
 local legacy=e:AddAccount("stats-legacy",50000,5,.8,true) add(legacy,{90},true)
 table.insert(rich.Scopes,{Key="L50000",Name="Legacy practice · not in funded totals",Short="Legacy",Kind="Legacy",Life=S.Finish(S.Include(S.Empty(),e,legacy)),Current=S.Finish(S.Empty())})
 local zero=S.Finish(S.Empty())
 local function dataFor(agg)return {Scopes={{Key="F5K",Kind="Tier",Name="$5K Funded",Life=agg,Current=agg}},Ready=true}end
 local partial=deep(combined) partial.Partial=true partial.CountUnknown=true partial.UntrackedNet=31 partial.UntrackedTrades=3 partial.AllTrades+=3 partial.Net+=31 partial.DailyComplete=false
 local noLossAccount=e:AddAccount("stats-no-loss",5000,5,.8,true) add(noLossAccount,{200},true)
 local noLoss=S.Finish(S.Include(S.Empty(),e,noLossAccount))
 local evenAccount=e:AddAccount("stats-even",5000,5,.8,true) add(evenAccount,{0},true)
 local even=S.Finish(S.Include(S.Empty(),e,evenAccount))
 local negativeAccount=e:AddAccount("stats-negative",5000,5,.8,true) add(negativeAccount,{-200},true)
 local negative=S.Finish(S.Include(S.Empty(),e,negativeAccount))
 local UI=require(shared.TerminalUI) local Before=require(baseline.TerminalUI)
 local function mount(ui,ww,hh,data,scope,period)
  local host=Instance.new("Frame") host.Name="Host" host.Size=UDim2.fromOffset(ww,hh) host.Parent=gui
  local ctl=ui.Mount(host,{Preview=true,StatsData=data,PortfolioData=pf,StatsScope=scope,StatsPeriod=period})
  table.insert(live,{ctl,host}) task.wait() task.wait()
  check(not ctl.Root:GetAttribute("RenderError"),tostring(ctl.Root:GetAttribute("RenderError")))
  return ctl,host
 end
 local function dispose(ctl,host)ctl:Destroy()host:Destroy()end
 local sizes={{1920,1080},{1440,900},{1280,720},{1024,600},{844,390},{390,844},{360,640},{320,568}}
 local states={{"Ready",rich},{"Zero",dataFor(zero)},{"Partial",dataFor(partial)},{"NoLoss",dataFor(noLoss)},{"Even",dataFor(even)},{"Negative",dataFor(negative)},
  {"Loading",{Loading=true}},{"Error",{Error="Stats are temporarily unavailable. Your trades and saved results are not affected."}},{"Empty",{New=true,Scopes={}}}}
 for _,size in ipairs(sizes)do
  for _,state in ipairs(states)do
   local ctl,host=mount(UI,size[1],size[2],state[2]) local page=ctl.Root.Canvas.Stats
   check(page~=nil,"Stats missing") audit(page,size[1].."x"..size[2].." "..state[1])
   local want=({Loading=true,Error=true,Empty=true})[state[1]]and state[1]or"Ready"
   check(page:GetAttribute("State")==want,state[1].." state")
   if want=="Ready"then
    local resolved,agg=require(shared.StatsView).Resolve(state[2],{})
    check(resolved.Key=="F5K","default must be first funded tier")
    for _,name in ipairs({"ScopeDropdown","ScopeLabel","ScopeSummary","ScopeInfo","Coverage"})do check(not page:FindFirstChild(name),"removed text/control remains: "..name)end
    local metrics=require(shared.StatsPieces).FromAggregate(agg)
    for _,m in ipairs(metrics)do check(page:FindFirstChild(m.Key.."Value",true).Text==m.Value,m.Key.." must match server aggregate")end
    check(page:GetAttribute("NetRealized")==agg.Net,"net changed")
    local drop=page.FundedDropdown.TestDropdown
    drop:Invoke("Open") task.wait()
    local layer=ctl.Root.Canvas.StatsOverlays local menu=layer.DropdownOverlay.DropdownMenu
    for _,row in ipairs(menu.Options:GetChildren())do if row:IsA("TextButton")then
     check(row:FindFirstChild("Label") and row.Label.Text~="" and row.Label.TextFits,"dropdown label unreadable")
     check(not row.Label:FindFirstChildOfClass("UIGradient"),"gradient tints option label")
    end end
    check(menu.AbsolutePosition.X>=layer.AbsolutePosition.X and menu.AbsolutePosition.Y>=layer.AbsolutePosition.Y,"menu starts outside Stats")
    check(menu.AbsolutePosition.X+menu.AbsoluteSize.X<=layer.AbsolutePosition.X+layer.AbsoluteSize.X+1,"menu width")
    check(menu.AbsolutePosition.Y+menu.AbsoluteSize.Y<=layer.AbsolutePosition.Y+layer.AbsoluteSize.Y+1,"menu height")
    drop:Invoke("Close")check(not layer:FindFirstChild("DropdownOverlay"),"menu did not close")
    page.HeroCard.TotalHelp.TestActivate:Invoke() task.wait()
    local help=layer.StatsMetricHelp check(help.Visible and help.Copy.Body.Text~="","help did not open")
    check(help.AbsolutePosition.Y+help.AbsoluteSize.Y<=layer.AbsolutePosition.Y+layer.AbsoluteSize.Y+1,"help height")
    help.Close.TestActivate:Invoke() report.Interactions+=4
   end
   dispose(ctl,host)
  end
 end
 local ctl,host=mount(UI,1440,900,rich)
 local function page()return ctl.Root.Canvas.Stats end
 for _,scope in ipairs(rich.Scopes)do if scope.Kind~="All" then for _,period in ipairs({"Life","Dated"})do
  check(page().FundedDropdown.TestDropdown:Invoke("Choose",scope.Key),"funded choice rejected")task.wait()task.wait()
  if page():GetAttribute("Period")~=period then page().DailyStats.DatedButton.TestActivate:Invoke()task.wait()task.wait()end
  check(page():GetAttribute("Scope")==scope.Key and page():GetAttribute("Period")==period,"filters not independent")
  local expected=period=="Dated"and scope.Life.Dated or scope[period]
  check(page():GetAttribute("NetRealized")==expected.Net,"wrong selected aggregate")
  report.Interactions+=2
 end end end
 if page():GetAttribute("Period")~="Life" then page().DailyStats.DatedButton.TestActivate:Invoke()task.wait()task.wait()end
 page().DailyStats.DatedButton.TestActivate:Invoke()task.wait()task.wait()
 check(page():GetAttribute("Period")=="Dated","dated action")report.Interactions+=1
 check(page().DailyStats.DatedButton.DatedButtonLabel.Text=="View lifetime stats","dated scope needs a return action")
 page().DailyStats.DatedButton.TestActivate:Invoke()task.wait()task.wait()
 check(page():GetAttribute("Period")=="Life","return to lifetime")
 check(not page().FundedDropdown.TestDropdown:Invoke("Choose","ALL"),"combined scope must not be a picker option")
 check(not page().FundedDropdown.TestDropdown:Invoke("Choose","not-a-scope"),"invalid selection")
 -- No fallback from unavailable dated data to Lifetime.
 local missing=deep(rich) missing.Scopes[2].Life.Dated=nil
 local _,missingAggregate=require(shared.StatsView).Resolve(missing,{StatsScope="F5K",StatsPeriod="Dated"})
 check(not missingAggregate,"Dated must not silently display Lifetime")
 local defaultScope,defaultAggregate,defaultPeriod=require(shared.StatsView).Resolve(rich,{StatsScope="ALL",StatsPeriod="Current"})
 check(defaultScope.Key=="F5K" and defaultPeriod=="Life" and defaultAggregate==rich.Scopes[2].Life,"stale selections must resolve to first-tier lifetime")
 dispose(ctl,host)
 -- Exercise the existing server-packet refresh path without live remotes, trades, or persistence.
 local Market=require(shared.MarketClient) local originalNew=Market.New local session
 Market.New=function()
  session=originalNew(nil,true,e:Snapshot(a.Id,"BX","1m",true))
  session.Preview=false session.Ready=true session.CanTrade=true session.AccountKey=a.Id
  session.Portfolio=pf session.SummaryData=e:Summary(a) session.Stats=rich session.StatsAt=1
  session.Send=function()return true,"Fixture","Stats",1 end
  return session
 end
 local hostLive=Instance.new("Frame")hostLive.Size=UDim2.fromOffset(1440,900)hostLive.Parent=gui
 local liveCtl=UI.Mount(hostLive) table.insert(live,{liveCtl,hostLive})
 liveCtl.Root.UIDiagnostics:Invoke("Set","Screen","Stats")task.wait()task.wait()
 check(liveCtl.Root.Canvas.Stats:GetAttribute("NetRealized")==rich.Scopes[2].Life.Net,"initial server packet")
 for i,aggregate in ipairs({noLoss,negative,partial,zero})do
  session.Stats=dataFor(aggregate) session.StatsAt=10+i session.Changed:Fire()task.wait()task.wait()
  check(liveCtl.Root.Canvas.Stats:GetAttribute("NetRealized")==aggregate.Net,"Stats packet did not refresh UI")
  check(liveCtl.Root.Canvas.Stats.HeroCard.TotalValue.Text==require(shared.StatsPieces).FromAggregate(aggregate)[1].Value,"headline did not refresh")
 end
 report.ServerPacketRefreshes=4
 dispose(liveCtl,hostLive)Market.New=originalNew
 -- Compare every native GUI/style property for the sidebar and each other page against the original source.
 for _,size in ipairs({{1440,900},{390,844}})do
  for _,name in ipairs({"Stats","Trade","Dashboard","Shop","Leaderboard","Positions","Review","Learn","Account","Settings","Help"})do
   local snapshots={}
   for i,ui in ipairs({Before,UI})do
    local c,holder=mount(ui,size[1],size[2],rich)
    local nav=c.Root.Canvas:FindFirstChild("Sidebar")or c.Root.Canvas:FindFirstChild("MobileNavigation")
    if name~="Stats"then
     local btn
     if name=="Account"then btn=nav:FindFirstChild("AccountSwitcher")or c.Root.Canvas.TopNavigation.Account
     elseif name=="Settings"or name=="Help"then btn=nav:FindFirstChild(name)
     else btn=nav:FindFirstChild("Nav"..(name=="Dashboard"and"Accounts"or name))end
     if btn and btn:FindFirstChild("TestActivate")then btn.TestActivate:Invoke()task.wait()task.wait()
     else c.State.Screen=name;c.State.StatsHelp=nil;holder.Size=UDim2.fromOffset(size[1]+1,size[2]);task.wait();holder.Size=UDim2.fromOffset(size[1],size[2]);task.wait();task.wait()end
    end
    local canvas=c.Root.Canvas
    -- For Stats or its global popups, compare the unchanged sidebar plus the global dialog.
    if name=="Stats"or name=="Account"or name=="Settings"or name=="Help"or name=="Positions"or name=="Review"or name=="Learn"then
     local rail=canvas:FindFirstChild("Sidebar")or canvas:FindFirstChild("MobileNavigation")
     snapshots[i]=signature(rail)..(canvas:FindFirstChild("Dialog")and signature(canvas.Dialog)or"")
    else snapshots[i]=signature(canvas)end
    dispose(c,holder)
   end
   check(snapshots[1]==snapshots[2],"Unrelated UI changed: "..name.." "..size[1])
   table.insert(report.UnchangedPages,{Name=name,Width=size[1]})
  end
 end
 report.States={"loading","error/retry","no-account/start","zero trades","break-even","loss-only","no losses/infinity","missing dates","partial/unknown counts","dated-only","legacy separate","best-day over 100%"}
 report.Calculations=require(server.StatsTests).Run()
 return report
end)
for _,entry in ipairs(live)do pcall(function()entry[1]:Destroy()entry[2]:Destroy()end)end
gui:Destroy() shared:Destroy()baseline:Destroy()server:Destroy()
if not ok then error(result)end
h:PostAsync("http://127.0.0.1:8772/results",h:JSONEncode(report))
return report
