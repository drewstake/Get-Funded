-- Disposable UI fixture. Does not open profiles, send trades, or access persistence.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="ProgressRedesignQA";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="ProgressRedesignQA";gui.IgnoreGuiInset=true;gui.DisplayOrder=150;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local ladder=require(shared.ProgressionConfig)
 local original=Market.New;local view
 Market.New=function()
  local session=original(nil,true)
  session.Ready=true;session.Portfolio=view;session.AccountKey="Fixture";session.AccountToken="Fixture"
  session.ConnectionStatus="ISOLATED UI PREVIEW";session.CanTrade=false
  return session
 end
 local function portfolio(state)
  local earned=state=="Complete" and 7 or state=="Negative" and 2 or state=="Halfway" and 2 or state=="Balance" and 3 or state=="Legacy" and 2 or 0
  local pf={Rank=earned==7 and "Get Funded Legend" or earned>=2 and "First Win" or "New Trader",Tutorial="Done",Run=1,RunProfit=5812.5,
   Earned=state=="Negative" and -44796.25 or state=="Halfway" and 250 or state=="Complete" and 95000 or state=="Balance" and 2800 or 0,
   Titles={},Milestones={},Accounts={{Key="Fixture",State="Live",Balance=ladder.StartingBalance,CanRestart=true}},Active="Fixture",Failed=state=="Failed",Migrated=state=="Legacy"}
  for i,m in ipairs(ladder.Milestones)do
   local goal=m.Profit or m.Goal
   local row={Key=m.Id,Kind=m.Kind,Name=m.Name,Title=m.Title,Goal=goal,Progress=i<=earned and goal or 0,Earned=i<=earned}
   if i==earned+1 and state=="Halfway" then row.Progress=250 end
   if i==earned+1 and state=="Balance" then row.Progress=2800 end
   table.insert(pf.Milestones,row)
   if row.Earned then table.insert(pf.Titles,row.Title)elseif not pf.Next then pf.Next=row end
  end
  if state=="Legacy" then table.insert(pf.Titles,"Legacy Market Champion")end
  return pf
 end
 local report={Layouts={},Issues={}}
 local function check(root,state,size,tab)
  local page=assert(root.Canvas:FindFirstChild("Progress"),"Progress missing")
  assert(page:IsA("Frame"),"Progress must not scroll")
  local c=page.Content;local hero=c:FindFirstChild("NextMilestone")
  local prefix=string.format("%s %dx%d %s ",state,size[1],size[2],tab)
  if hero then
   local expected=state=="Complete" and 1 or state=="Halfway" and .5 or state=="Balance" and .56 or 0
   assert(math.abs(hero.Track:GetAttribute("Progress")-expected)<.001,"Incorrect progress")
   assert(hero.Track.Fill.Visible==(expected>0),"Zero progress sliver")
   if hero:GetAttribute("CopyBottom")>hero:GetAttribute("TrackTop")-2 then table.insert(report.Issues,prefix.."hero text overlaps track")end
   if state=="Negative"then assert(hero.ProgressNote.Text:find("44,796"),"Recovery note missing")end
   if state=="Balance"then assert(hero.Goal.Text:find("balance +"),"Balance requirement missing")end
  end
  for _,obj in ipairs(page:GetDescendants())do
   assert(not obj:IsA("ScrollingFrame"),"Nested scrolling is forbidden")
   local visible=obj:IsA("GuiObject")and obj.Visible
   local ancestor=obj.Parent
   while visible and ancestor~=page do
    if ancestor:IsA("GuiObject")and not ancestor.Visible then visible=false end
    ancestor=ancestor.Parent
   end
   if visible then
    if obj:IsA("TextLabel")and obj.Text~=""and not obj.TextFits and not obj.TextScaled then table.insert(report.Issues,prefix.."text overflow "..obj.Name..": "..obj.Text)end
    local pw,ph=obj.Parent.AbsoluteSize.X,obj.Parent.AbsoluteSize.Y
    local width=pw*obj.Size.X.Scale+obj.Size.X.Offset;local hh=ph*obj.Size.Y.Scale+obj.Size.Y.Offset
    local left=pw*obj.Position.X.Scale+obj.Position.X.Offset-width*obj.AnchorPoint.X
    local top=ph*obj.Position.Y.Scale+obj.Position.Y.Offset-hh*obj.AnchorPoint.Y
    if left<-.5 or top<-.5 or left+width>pw+1 or top+hh>ph+1 then table.insert(report.Issues,prefix.."bounds "..obj:GetFullName())end
   end
  end
  for _,name in ipairs({"UpcomingTitles","EarnedTitles"})do
   local panel=c:FindFirstChild(name)
   if panel then
    for _,row in ipairs(panel:GetChildren())do
     if row:IsA("Frame")and row:FindFirstChild("StatusIcon")and row.Position.Y.Offset+row.Size.Y.Offset>panel.Size.Y.Offset-40 then table.insert(report.Issues,prefix.."row overlaps page controls "..row.Name)end
    end
   end
  end
 end
 for _,state in ipairs({"Fresh","Negative","Halfway","Balance","Complete","Legacy","Failed"})do
  view=portfolio(state)
  -- Extra legacy titles exercise pagination and ensure the last title stays reachable.
  if state=="Legacy"then for i=1,15 do table.insert(view.Titles,"Legacy Achievement "..i)end end
  for _,size in ipairs({{320,510},{320,568},{390,844},{749,303},{749,361},{844,390},{1000,600},{1440,900},{1920,1080}})do
   local host=Instance.new("Frame");host.Name="Viewport";host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui;task.wait(.04)
   ctl=UI.Mount(host);ctl.State.Screen="Progress";ctl.State.CoachDismissed=true
   local issueStart=#report.Issues;local visited={}
   for _,tab in ipairs({"Overview","Upcoming","Earned"})do
    ctl.State.ProgressViewState={Tab=tab}
    ctl.Root.UIDiagnostics:Invoke("Render");task.wait(.04)
    assert(not ctl.Root:GetAttribute("RenderError"),ctl.Root:GetAttribute("RenderError"))
    check(ctl.Root,state,size,tab)
    for _,name in ipairs({"UpcomingTitles","EarnedTitles"})do
     local panel=ctl.Root.Canvas.Progress.Content:FindFirstChild(name)
     if panel and not visited[name]then
      visited[name]=true;local seen={};local total=panel:GetAttribute("ItemCount")
      for page=1,panel:GetAttribute("PageCount")do
       ctl.State.ProgressViewState[name]=page;ctl.Root.UIDiagnostics:Invoke("Render");task.wait(.02)
       check(ctl.Root,state,size,tab.." page "..page)
       panel=ctl.Root.Canvas.Progress.Content[name]
       for _,row in ipairs(panel:GetChildren())do if row:IsA("Frame")and row:FindFirstChild("StatusIcon")then seen[row.Name]=true end end
      end
      local count=0;for _ in pairs(seen)do count+=1 end;assert(count==total,"Pagination lost titles")
     end
    end
   end
   table.insert(report.Layouts,{State=state,Width=size[1],Height=size[2],Issues=#report.Issues-issueStart})
   ctl:Destroy();ctl=nil;host:Destroy()
  end
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end
gui:Destroy();shared:Destroy()
assert(ok,result)
local H=game:GetService("HttpService");H:PostAsync("http://127.0.0.1:8774/results",H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
return result
