-- Disposable presentation fixtures: no remotes, profiles, or trading actions.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local shared=game.ReplicatedStorage.TypographyQA
local UI=require(shared.TerminalUI)
local Config=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local gui=Instance.new("ScreenGui");gui.Name="TypographyQA";gui.IgnoreGuiInset=false;gui.DisplayOrder=200;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=Players.LocalPlayer.PlayerGui
local result=Instance.new("StringValue");result.Name="Results";result.Parent=gui
local command=Instance.new("StringValue");command.Name="Command";command.Parent=gui
local function portfolio(net,trades,wins,legacy)
 local pf={RankId="Rookie",Rank="Market Rookie",RankLevel=1,RankBadge=1,Title="Your story starts here",Earned=net,Trades=trades,Wins=wins,Titles={},Milestones={},Ranks={},Tutorial="Done",Run=1}
 for _,m in ipairs(Config.Milestones)do
  local a=table.clone(m);a.Key=m.Id;a.Progress=math.min(m.Goal,math.max(0,m.Kind=="Trades"and trades or m.Kind=="Wins"and wins or net));a.Earned=a.Progress==a.Goal
  if legacy then a.Earned=true;a.EarlierGoal=true end
  if a.Earned then table.insert(pf.Titles,a.Title);pf.Title=a.Title elseif not pf.Next then pf.Next=a end
  table.insert(pf.Milestones,a)
 end
 for i,r in ipairs(Config.Ranks)do
  local a=table.clone(r);a.Earned=trades>=r.Trades and wins>=r.Wins and (r.Profit==0 or net>=r.Profit)
  if a.Earned then pf.RankId=r.Id;pf.Rank=r.Name;pf.RankLevel=i;pf.RankBadge=r.Badge elseif not pf.RankNext then pf.RankNext=a end
  table.insert(pf.Ranks,a)
 end
 return pf
end
local portfolios={portfolio(0,0,0),portfolio(250000,620,145),portfolio(5000000,5000,2500),portfolio(-50000,100,60,true)}
local function stats(kind)
 if kind==7 then return {Loading=true}elseif kind==8 then return {Error="The exchange is reconnecting. Try again in a moment."}elseif kind==9 then return {New=true}elseif kind==10 then return {Scopes={}}end
 local a={Net=42758.75,Wins=73,Losses=27,Even=3,Trades=103,AllTrades=103,WinRate=73/103,AvgWin=1000.75,AvgLoss=1124.3,WinLossRatio=.89,ProfitFactor=2.4,Gains=73054.75,Loss=30356.1,DayCount=12,WinningDays=9,DayWinRate=.75,BestDayShare=.36,DailyComplete=true,UntrackedTrades=0,UntrackedNet=0,UndatedTrades=0}
 if kind==2 then a.Net=-25670.5
 elseif kind==3 then a.Net=1234567890123.45;a.Gains=2345678901234.56;a.Loss=1111111011111.11;a.AvgWin=54321987.65;a.AvgLoss=7654321.09
 elseif kind==4 then a.Partial=true;a.CountUnknown=true;a.DailyComplete=false
 elseif kind==5 then for k,v in pairs(a)do if type(v)=="number"then a[k]=0 end end;a.WinRate=nil;a.WinLossRatio=nil;a.ProfitFactor=nil;a.BestDayShare=nil
 elseif kind==6 then a.NoLosses=true;a.ProfitFactor=nil;a.WinLossRatio=nil end
 return {Scopes={{Key="ALL",Current=a}},Run=1}
end
local function standings(kind)
 local rows={}
 local names={"GoldenTrader","MoonlightMarketNavigator","SilverFox","Drew", "玩家交易大师🌟", "WWWWWWWWWWWWWWWWWWWW"}
 for i=1,12 do rows[i]={UserId=i,DisplayName=names[(i-1)%#names+1],Name="Trader"..i,Cents=(10-i)*234567890,Rank=i,ProgressionVersion=Config.ProgressionVersion,ProgressionRankId=Config.Ranks[math.min(i,#Config.Ranks)].Id}end
 local own=table.clone(rows[4])
 if kind==2 then rows[1].Cents=123456789012345;own.Rank=nil;own.Status="Outside top 100"
 elseif kind==3 then rows={};own.ProgressionVersion=nil
 elseif kind==4 then return {Rows={},Your=own,State="Error"}elseif kind==5 then own=table.clone(rows[1])end
 return {Rows=rows,Your=own,State=kind==3 and "Loading"or "Ready"}
end
local controller,host
local function mount(width,height,page,kind,tab,help)
 if controller then controller:Destroy();controller=nil end
 if host then host:Destroy()end
 host=Instance.new("Frame");host.Name="Viewport";host.Size=UDim2.fromOffset(width,height);host.BackgroundTransparency=1;host.Parent=gui
 local options={Preview=true,PortfolioData=portfolios[page=="Progress"and kind or 2]}
 if page=="Stats"then options.StatsData=stats(kind)elseif page=="Leaderboard"then options.LeaderboardData=standings(kind)end
 controller=UI.Mount(host,options)
 controller.State.Screen=page;controller.State.Nav=page;controller.State.CoachDismissed=true
 controller.State.StatsHelp=help
 controller.State.ProgressViewState={Collection=tab=="Ranks"and "Ranks"or "Titles",Track=tab or "Trades"}
 controller.Root.UIDiagnostics:Invoke("Render")
 task.wait(.12)
 return controller.Root.Canvas:FindFirstChild(page)
end
local report={Layouts=0,Issues={},Sizes={},ScrollChecks=0}
local function audit(page,tag)
 if not page then table.insert(report.Issues,tag.." missing page");return end
 local function shown(o)
  local p=o;while p and p~=page do if p:IsA("GuiObject")and not p.Visible then return false end;p=p.Parent end;return true
 end
 local function issue(s)table.insert(report.Issues,tag.." "..s)end
 for _,o in ipairs(page:GetDescendants())do
  if (o:IsA("TextLabel")or o:IsA("TextButton"))and o.Text~=""and shown(o)then
   if not o.TextFits then issue("TextFits "..o:GetFullName():gsub(".-Canvas%.","").." "..o.Text)end
   if o.TextScaled then issue("TextScaled "..o.Name)end
   local p=o.Parent
   if p:IsA("GuiObject")and not p:IsA("ScrollingFrame")then
    local op,os,pp,ps=o.AbsolutePosition,o.AbsoluteSize,p.AbsolutePosition,p.AbsoluteSize
    if op.X<pp.X-1 or op.X+os.X>pp.X+ps.X+1 or op.Y<pp.Y-2 or op.Y+os.Y>pp.Y+ps.Y+1 then issue("Bounds "..o:GetFullName():gsub(".-Canvas%.",""))end
   end
   for _,b in ipairs(p:GetChildren())do
    if b:IsA("TextLabel")and b~=o and b.Text~=""and shown(b)and o.Name<b.Name then
     local a1,a2=o.AbsolutePosition,o.AbsolutePosition+o.AbsoluteSize
     local b1,b2=b.AbsolutePosition,b.AbsolutePosition+b.AbsoluteSize
     if a1.X<b2.X-1 and b1.X<a2.X-1 and a1.Y<b2.Y-1 and b1.Y<a2.Y-1 then issue("Overlap "..o.Name.."/"..b.Name)end
    end
   end
  end
 end
 for _,o in ipairs(page:GetChildren())do
  if o:IsA("GuiObject")and o.Visible and not page:IsA("ScrollingFrame")then
   if o.AbsolutePosition.Y+o.AbsoluteSize.Y>page.AbsolutePosition.Y+page.AbsoluteSize.Y+1 then issue("PageBounds "..o.Name)end
  end
 end
 report.Layouts+=1
end
local ok,err=xpcall(function()
 for _,size in ipairs(script:GetAttribute("PreviewOnly")and {}or {{320,568},{390,844},{749,303},{844,390},{1024,768},{1280,720},{1440,900},{1920,1080}})do
  table.insert(report.Sizes,size)
  for kind=1,4 do for _,tab in ipairs({"Trades","Profit","Ranks"})do
   local page=mount(size[1],size[2],"Progress",kind,tab);audit(page,size[1].." Progress "..kind.." "..tab)
   page.CanvasPosition=Vector2.new(0,240);task.wait();local previous=page.CanvasPosition.Y
   controller.Root.UIDiagnostics:Invoke("Render");task.wait()
   assert(math.abs(controller.Root.Canvas.Progress.CanvasPosition.Y-previous)<1,"Progress scroll changed")
   report.ScrollChecks+=1
  end end
  for kind=1,10 do audit(mount(size[1],size[2],"Stats",kind),size[1].." Stats "..kind)end
  for kind=1,5 do audit(mount(size[1],size[2],"Leaderboard",kind),size[1].." Leaderboard "..kind)end
 end
end,debug.traceback)
report.Error=not ok and err or nil
result.Value=Http:JSONEncode(report)
mount(gui.AbsoluteSize.X,gui.AbsoluteSize.Y,"Stats",1)
command.Changed:Connect(function(value)
 local c=Http:JSONDecode(value)
 local page=mount(c.Width or gui.AbsoluteSize.X,c.Height or gui.AbsoluteSize.Y,c.Page or "Stats",c.Kind or 1,c.Tab,c.Help)
 if c.Scroll then page.CanvasPosition=Vector2.new(0,c.Scroll)end
end)
