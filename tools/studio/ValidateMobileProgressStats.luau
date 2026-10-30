-- Isolated Edit-mode QA. Load local UI into cloned modules; never touches player saves.
-- Pass Preview=true to retain portrait and landscape fixtures for screenshots.
return function(options)
 options=options or {}
 if _G.MobileProgressStatsQA then _G.MobileProgressStatsQA();_G.MobileProgressStatsQA=nil end
 local H=game:GetService("HttpService")
 local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="MobileProgressStatsModules";shared.Parent=game.ReplicatedStorage
 local server=game.ServerScriptService.MarketReign:Clone();server.Name="MobileProgressStatsServer";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
 local gui=Instance.new("ScreenGui");gui.Name="MobileProgressStatsQA";gui.IgnoreGuiInset=true;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.DisplayOrder=100;gui.Parent=game.StarterGui
 local controllers={}
 local function cleanup()
  for _,ctl in ipairs(controllers)do ctl:Destroy()end;table.clear(controllers)
  gui:Destroy();shared:Destroy();server:Destroy()
 end
 local ok,result=xpcall(function()
  for _,name in ipairs({"TerminalUI","ProgressView","StatsView"})do shared[name].Source=H:GetAsync("http://127.0.0.1:8797/src/shared/"..name..".luau")end
  for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do if m:IsA("LuaSourceContainer")then
   m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.MobileProgressStatsModules")
    :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.MobileProgressStatsServer")
  end end end
  shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("RunService:IsStudio%(%)and not options.Preview","RunService:IsStudio()")
  shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
   return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
  end)
  shared.StatsView.Source=shared.StatsView.Source:gsub("local function bind%(button,fn%) return button.Activated:Connect%(fn%) end",function()
   return 'local function bind(button,fn)local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=button;return button.Activated:Connect(fn)end'
  end)
  local UI=require(shared.TerminalUI);local View=require(shared.ProgressView)
  local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
  local E=require(server.MarketEngine);local F=require(server.FundedAccounts);local M=require(shared.MarketClient)
  local function portfolio(net,trades,wins)
   local e=E.new(C,91);local f=F.new(e,L,C);f:Start("fixture");f:Flag("fixture","TutorialDone")
   local a=e.Accounts[f:Owner("fixture")];a.Realized=net;a.Stats.Trades=trades;a.Stats.Wins=wins;a.Stats.Losses=trades-wins
   f:Evaluate("fixture",true)
   return f:View("fixture"),f:Stats("fixture"),e,f
  end
  local pf,stats=portfolio(18500,32,8)
  local function host(w,h,x,y)
   local frame=Instance.new("Frame");frame.Size=UDim2.fromOffset(w,h);frame.Position=UDim2.fromOffset(x or 0,y or 0);frame.BackgroundTransparency=1;frame.Parent=gui
   return frame
  end
  local function mount(w,h,screen,data,statsData,x,y)
   local frame=host(w,h,x,y)
   local ctl=UI.Mount(frame,{Preview=true,PortfolioData=data or pf,StatsData=statsData or stats})
   table.insert(controllers,ctl);ctl.State.CoachDismissed=true;ctl.State.Screen=screen;ctl.State.Nav=screen
   ctl.Root.UIDiagnostics:Invoke("Render");task.wait(.05)
   assert(not ctl.Root:GetAttribute("RenderError"),ctl.Root:GetAttribute("RenderError"))
   return ctl,frame
  end
  local report={Layouts={},RankCases=0,Issues={}}
  local function checkText(page,prefix)
   for _,o in ipairs(page:GetDescendants())do if (o:IsA("TextLabel")or o:IsA("TextButton"))and o.Visible then
    if not o.TextFits then table.insert(report.Issues,prefix.." overflow: "..o:GetFullName().." ["..o.Text.."]")end
    local parent=o.Parent
    if parent:IsA("GuiObject")and not parent:IsA("ScrollingFrame")then
     if o.AbsolutePosition.X<parent.AbsolutePosition.X-1 or o.AbsolutePosition.X+o.AbsoluteSize.X>parent.AbsolutePosition.X+parent.AbsoluteSize.X+1
      or o.AbsolutePosition.Y<parent.AbsolutePosition.Y-1 or o.AbsolutePosition.Y+o.AbsoluteSize.Y>parent.AbsolutePosition.Y+parent.AbsoluteSize.Y+1 then
      table.insert(report.Issues,prefix.." bounds: "..o:GetFullName())
     end
    end
   end end
  end
  local function checkRank(page,data)
   assert(not page.Content:FindFirstChild("TabRanks")and not page.Content:FindFirstChild("NextMilestone"),"Old rank/title controls remain")
   for _,r in ipairs(L.Ranks)do assert(not page.Content:FindFirstChild(r.Id),"Full rank ladder remains")end
   local card=assert(page.Content:FindFirstChild("NextRank"))
   if data.RankNext then
    local rank=L.Ranks[data.RankLevel+1];assert(card:GetAttribute("RankId")==rank.Id and card.Rank.Text==rank.Name,"Wrong next rank")
    assert(card.Eyebrow.Text=="NEXT RANK")
    for key,current in pairs({Trades=data.Trades,Wins=data.Wins,Profit=data.Earned})do
     local req=assert(card:FindFirstChild("Requirement"..key));assert(req:GetAttribute("Current")==current and req:GetAttribute("Goal")==rank[key],"Rank requirement differs from server")
     assert(req:GetAttribute("Met")== (key=="Profit" and current+1e-6>=rank[key]or current>=rank[key]),"Requirement state wrong")
     assert(math.abs(card["Track"..key]:GetAttribute("Progress")-math.clamp(current/rank[key],0,1))<.0001,"Progress bar wrong")
     local value=card["Amount"..key].Text;assert(value:find(" / ",1,true),"Missing progress fraction")
    end
   else
    assert(card.Eyebrow.Text=="ALL RANKS EARNED"and card:FindFirstChild("Complete"),"Highest rank state missing")
    assert(not card:FindFirstChild("RequirementTrades"),"Invented next rank at maximum")
   end
  end
  if options.Preview then
   local back=Instance.new("Frame");back.Name="Backdrop";back.Size=UDim2.fromScale(1,1);back.BackgroundColor3=Color3.fromRGB(20,23,32);back.BorderSizePixel=0;back.Parent=gui
   local screen=options.Screen or "Progress"
   for _,size in ipairs({{390,844,12,28},{844,390,430,28}})do
    local ctl=mount(size[1],size[2],screen,pf,stats,size[3],size[4])
    if options.Scroll and screen=="Progress"then ctl.Root.Canvas.Progress.CanvasPosition=Vector2.new(0,options.Scroll)end
    local caption=Instance.new("TextLabel");caption.Text=screen.." · "..size[1].." × "..size[2];caption.Font=Enum.Font.GothamBold;caption.TextSize=14;caption.TextColor3=Color3.new(1,1,1);caption.BackgroundTransparency=1;caption.Size=UDim2.fromOffset(size[1],22);caption.Position=UDim2.fromOffset(size[3],2);caption.Parent=gui
   end
   task.wait(.3);return {Preview=screen}
  end
  for _,size in ipairs({{320,568},{390,844},{430,932},{568,320},{749,303},{844,390},{932,430},{1440,900}})do
   for _,screen in ipairs({"Progress","Stats"})do
    local ctl,frame=mount(size[1],size[2],screen)
    local canvas=ctl.Root.Canvas;local page=canvas[screen]
    checkText(page,size[1].."x"..size[2].." "..screen)
    if size[1]<1000 then
     assert(not canvas:FindFirstChild("TopNavigation"),"Unused mobile header remains")
     assert(page.Position.Y.Offset==6,"Removed header space not reclaimed")
     local nav=canvas.MobileNavigation
     assert(page.AbsolutePosition.Y+page.AbsoluteSize.Y<=nav.AbsolutePosition.Y,"Page overlaps navigation")
     for _,child in ipairs(nav:GetChildren())do assert(child.Name~="Rule","Cyan navigation line remains")end
     for _,name in ipairs({"Trade","Progress","Stats","More"})do assert(nav:FindFirstChild("Nav"..name),"Missing bottom button")end
     nav.NavMore.TestActivate:Invoke();task.wait(.05)
     assert(ctl.State.Overlay=="Menu"and canvas:FindFirstChild("Dialog"),"Bottom More cannot open menu")
     ctl.Root.UIDiagnostics:Invoke("Set","Overlay",nil);page=canvas[screen]
    end
    if screen=="Progress"then
     checkRank(page,pf)
     page.CanvasPosition=Vector2.new(0,230);task.wait();local scroll=page.CanvasPosition.Y
     ctl.Root.UIDiagnostics:Invoke("Render");task.wait()
     assert(math.abs(canvas.Progress.CanvasPosition.Y-scroll)<1,"Progress refresh lost scroll position")
     -- Same live controller rotates and rebuilds within the available content area.
     if size[1]==390 then
      frame.Size=UDim2.fromOffset(844,390);task.wait(.08);ctl.Root.UIDiagnostics:Invoke("Render");task.wait()
      assert(not canvas:FindFirstChild("TopNavigation"));checkRank(canvas.Progress,pf);checkText(canvas.Progress,"Rotation")
     end
    else
     assert(not page:FindFirstChild("Subtitle")and not page:FindFirstChild("ScopeDescription"),"Removed Stats copy remains")
     assert(page.HeroCard.Position.Y.Offset==page.Title.Size.Y.Offset+12,"Stats header space remains")
     assert(page.HeroCard.TotalHelp:FindFirstChild("TestActivate"),"Metric help missing")
     page.HeroCard.TotalHelp.TestActivate:Invoke();task.wait()
     assert(canvas.StatsOverlays:FindFirstChild("StatsMetricHelp"),"Stats scope help unavailable")
    end
    table.insert(report.Layouts,{Width=size[1],Height=size[2],Screen=screen,Passed=true})
    ctl:Destroy();table.remove(controllers);frame:Destroy()
   end
  end
  local cases={{0,0,0},{-4500,70,12},{18500,32,8},{24999.99,25,10},{25000,25,10}}
  for _,r in ipairs(L.Ranks)do table.insert(cases,{r.Profit,r.Trades,r.Wins})end
  for _,case in ipairs(cases)do
   local data=portfolio(case[1],case[2],case[3])
   for _,w in ipairs({272,796})do
    local frame=host(w,568);local state={Collection="Ranks"}
    local page=View.Build(frame,data,0,0,w,568,{State=state,Whole=function(n)return M.Money(n):gsub("%.00$","")end,Signed=M.Signed})
    task.wait(.03);checkRank(page,data);checkText(page,"Rank "..data.RankId.." "..w)
    assert(state.Collection=="Titles","Old rank tab selection not migrated")
    report.RankCases+=1;frame:Destroy()
   end
  end
  -- A packet refresh advances the next rank without preserving stale requirements.
  local ctl,frame=mount(390,844,"Progress")
  ctl.Chart.Ctx.Session.Portfolio=portfolio(25000,25,10);ctl.Root.UIDiagnostics:Invoke("Render");task.wait()
  assert(ctl.Root.Canvas.Progress.Content.NextRank:GetAttribute("RankId")==L.Ranks[3].Id,"Rank refresh stale")
  ctl:Destroy();table.remove(controllers);frame:Destroy()
  H:PostAsync("http://127.0.0.1:8797/results/layouts.json",H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
  return report
 end,debug.traceback)
 if options.Preview and ok then _G.MobileProgressStatsQA=cleanup else cleanup()end
 if not ok then error(result)end
 return result
end
