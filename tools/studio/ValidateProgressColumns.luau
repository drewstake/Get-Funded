-- Run against a fresh cloned shared module graph in Studio Edit mode.
-- Disposable UI fixtures only; no player profiles, remotes or data stores.
local shared=game.ReplicatedStorage.ProgressColumnsQA
local View=require(shared.ProgressView)
local Config=require(shared.ProgressionConfig)
local gui=Instance.new("ScreenGui");gui.Name="ProgressColumnsLayoutQA";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local report={Layouts=0,Issues={}}
local function whole(n)
 local s=tostring(math.floor(math.abs(n)));return (n<0 and "-$"or "$")..s:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end
local function signed(n)return (n<0 and "-"or "+")..whole(math.abs(n))end
local function portfolio(net,trades,wins,legacy)
 local pf={RankId="Rookie",Rank="Market Rookie",RankLevel=1,RankBadge=1,Title="Your story starts here",Earned=net,Trades=trades,Wins=wins,Titles={},Milestones={},Ranks={}}
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
local cases={
 {Name="Fresh",Data=portfolio(0,0,0)},
 {Name="Quick10K",Data=portfolio(10000,3,2)},
 {Name="Mixed",Data=portfolio(250000,620,145)},
 {Name="Complete",Data=portfolio(5000000,5000,2500)},
 {Name="LegacyLoss",Data=portfolio(-50000,100,60,true)},
 {Name="Loading",Data={New=true}},
}
local ok,err=xpcall(function()
 for _,size in ipairs({{320,568},{390,844},{650,400},{749,303},{864,600},{1024,768},{1440,900},{1920,1080}})do
  for _,case in ipairs(cases)do
   local seen={}
   for _,tab in ipairs({"Trades","Wins","Profit","Ranks"})do
    local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
    local state={Collection=tab=="Ranks"and "Ranks"or "Titles",Track=tab}
    local opts={State=state,Whole=whole,Signed=signed}
    local page=View.Build(host,case.Data,0,0,size[1],size[2],opts);task.wait(.03)
    local prefix=size[1].." "..case.Name.." "..tab
    for _,o in ipairs(page:GetDescendants())do
     if o:IsA("TextLabel")or o:IsA("TextButton")then
      if not o.TextFits then table.insert(report.Issues,prefix.." text overflow: "..o:GetFullName().." "..o.Text)end
      local p=o.Parent
      if p:IsA("GuiObject")and (o.Position.X.Offset<0 or o.Position.X.Offset+o.Size.X.Offset>p.Size.X.Offset+.1 or o.Position.Y.Offset+o.Size.Y.Offset>p.Size.Y.Offset+.1)then
       table.insert(report.Issues,prefix.." bounds: "..o:GetFullName())
      end
     end
    end
    if not case.Data.New then
     if tab~="Ranks"then
      local lanes=0
      for _,lane in ipairs(page.Content:GetChildren())do if lane:GetAttribute("Kind")then
       lanes+=1;local priorY=-1;local priorGoal=0;local nextCount=0
       for _,m in ipairs(Config.Milestones)do if m.Kind==lane:GetAttribute("Kind")then
        local tile=assert(lane:FindFirstChild(m.Id),"Missing title "..m.Id);seen[m.Id]=true
        assert(tile.Position.Y.Offset>priorY and m.Goal>priorGoal,"Column reordered")
        priorY=tile.Position.Y.Offset;priorGoal=m.Goal
        if tile:GetAttribute("Next")then nextCount+=1 end
       end end
       assert(nextCount<=1,"Multiple next titles in one column")
      end end
      assert(lanes==(size[1]-24>=840 and 3 or 1),"Wrong column count")
     end
     page.CanvasPosition=Vector2.new(0,200);task.wait()
     local expected=page.CanvasPosition.Y;page:Destroy()
     page=View.Build(host,case.Data,0,0,size[1],size[2],opts);task.wait()
     assert(math.abs(page.CanvasPosition.Y-expected)<1,"Refresh lost scroll position")
    end
    report.Layouts+=1;host:Destroy()
   end
   if not case.Data.New then for _,m in ipairs(Config.Milestones)do assert(seen[m.Id],"Unreachable title "..m.Id)end end
  end
 end
end,debug.traceback)
gui:Destroy();assert(ok,err)
return report
