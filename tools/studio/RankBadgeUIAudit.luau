-- Client-only disposable rendered fixtures. No remote calls or profile writes.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="RankBadgeUIQA";shared.Parent=game.ReplicatedStorage
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("if RunService:IsStudio%(%)and not options.Preview then","if RunService:IsStudio()then")
local gui=Instance.new("ScreenGui");gui.Name="RankBadgeUIQA";gui.IgnoreGuiInset=true;gui.DisplayOrder=200;gui.Parent=game.Players.LocalPlayer.PlayerGui
local report={Layouts={},Issues={}};local ctl
local ok,err=xpcall(function()
 local H=game:GetService("HttpService");local pf=H:JSONDecode(game.ReplicatedStorage.RankBadgeQAView.Value)
 local Market=require(shared.MarketClient);local original=Market.New
 Market.New=function()local s=original(nil,true);s.Ready=true;s.CanTrade=false;s.Portfolio=pf;s.AccountKey=pf.Active;s.AccountToken=pf.Active;return s end
 local UI=require(shared.TerminalUI);local L=require(shared.ProgressionConfig)
 game:GetService("ContentProvider"):PreloadAsync({L.BadgeAtlas})
 local rows={}
 for i=1,8 do rows[i]={UserId=91000+i,Name="MaximumUsernameTwenty",DisplayName=i%2==0 and "A Very Long Display Name To Check"or "Trader "..i,
  Cents=i==1 and 8999999999999999 or (9-i)*125000,Eligible=true,Rank=i,ProgressionRankId=L.Ranks[9-i].Id,ProgressionVersion=1}end
 rows[8].ProgressionVersion=nil;rows[8].Tier="10K Trader" -- unsupported old row must render pending
 local own=table.clone(rows[2]);own.Status="#2"
 local data={Rows=rows,Your=own,State="Ready",Studio=true}
 local stats=H:JSONDecode(game.ReplicatedStorage.RankBadgeQAStats.Value)
 local function scan(page,prefix)
  for _,o in ipairs(page:GetDescendants())do
   if o:IsA("TextLabel")or o:IsA("TextButton")then
    local visible=o.Visible;local p=o.Parent
    while visible and p~=page do if p:IsA("GuiObject")and not p.Visible then visible=false end;p=p.Parent end
    if visible and o.Text~=""then
     if page.Name~="Stats"and o.Font~=Enum.Font.FredokaOne then table.insert(report.Issues,prefix.." font "..o.Name)end
     if page.Name~="Stats"and o.TextScaled then table.insert(report.Issues,prefix.." scaled "..o.Name)end
     if not o.TextFits and not o.TextScaled and o.TextTruncate==Enum.TextTruncate.None then table.insert(report.Issues,prefix.." text overflow "..o.Name..": "..o.Text)end
     if o.Text:match("Run %d")or o.Text:match("%d+ attempts?$")or o.Text:match("%d+ closed trades$")or o.Text:find("10K Trader",1,true)or o.Text:find("Legacy 5K",1,true)then table.insert(report.Issues,prefix.." obsolete copy "..o.Text)end
    end
   end
   if o:IsA("ImageLabel")and o:GetAttribute("BadgeIndex")then
    -- PreloadAsync above verifies successful fetching; offscreen instances may defer rendering.
    assert(o.ImageRectSize.X==256,"Wrong uploaded atlas cell size")
   end
  end
 end
 for _,size in ipairs({{320,568},{390,844},{749,303},{844,390},{1000,600},{1440,900},{1920,1080}})do
  for _,screen in ipairs({"Progress","Ranks","Leaderboard","Stats"})do
   local host=Instance.new("Frame");host.Name="Viewport";host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
   local opts={Preview=true,PortfolioData=pf};if screen=="Leaderboard"then opts.LeaderboardData=data elseif screen=="Stats"then opts.StatsData=stats end
   ctl=UI.Mount(host,opts);ctl.State.CoachDismissed=true
   if screen=="Ranks"then ctl.State.ProgressViewState={Collection="Ranks"}end
   ctl.State.Screen=screen=="Ranks"and "Progress"or screen;ctl.Root.UIDiagnostics:Invoke("Render");task.wait(.12)
   assert(not ctl.Root:GetAttribute("RenderError"),ctl.Root:GetAttribute("RenderError"))
   local page=assert(ctl.Root.Canvas:FindFirstChild(ctl.State.Screen));local prefix=size[1].."x"..size[2].." "..screen
   local images={};for _,o in ipairs(page:GetDescendants())do if o:IsA("ImageLabel")and o:GetAttribute("BadgeIndex")and o.Image~=""then table.insert(images,o)end end
   game:GetService("ContentProvider"):PreloadAsync(images,function(id,status)assert(status==Enum.AssetFetchStatus.Success,"Badge fetch failed: "..id.." "..tostring(status))end)
   task.wait(.05)
   local before=#report.Issues;scan(page,prefix)
   if screen=="Leaderboard"then
    local pending=page.Rows:FindFirstChild("Player91008");assert(pending.ProgressionRank.Text=="Rank updating…"and pending.RankBadge.Image=="")
    assert(page.Rows.Player91001.Podium.Text=="1ST"and page.Rows.Player91002.Podium.Text=="2ND"and page.Rows.Player91003.Podium.Text=="3RD")
    assert(page.Rows.Player91002:GetAttribute("CurrentPlayer"))
   elseif screen=="Stats"then assert(not page:FindFirstChild("AttemptsLabel",true)and not page:FindFirstChild("ClosedTradesLabel",true))end
   table.insert(report.Layouts,{Width=size[1],Height=size[2],Screen=screen,Issues=#report.Issues-before})
   ctl:Destroy();ctl=nil;host:Destroy()
  end
 end
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy();assert(ok,err)
return report
