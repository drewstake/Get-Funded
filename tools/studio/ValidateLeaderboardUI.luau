-- Run in Studio Edit or Client. Native, isolated UI fixtures; all objects are destroyed on exit.
local Run=game:GetService("RunService")
local parent=Run:IsRunning()and game.Players.LocalPlayer.PlayerGui or game.StarterGui
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="LeaderboardUIValidationModules";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="LeaderboardUIValidation";gui.Parent=parent
local report={}
local ok,err=pcall(function()
 local UI=require(shared.TerminalUI)
 local Client=require(shared.LeaderboardClient)
 local client=Client.new(true)
 client.Cache.Global={State="Ready",Rows={{UserId=1,Rank=1}},Your={UserId=1,Rank=1,Eligible=true}}
 client.CacheAt.Global=-math.huge
 local expired=client:Cached("Global")
 assert(expired.State=="Stale"and expired.Your.Rank==nil and expired.Rows[1].Rank==nil)
 assert(client.Cache.Global.Your.Rank==1,"Expired presentation mutated cached evidence")
 client:Destroy();table.insert(report,{State="Expired cache hides unverified ranks",Passed=true})
 for _,case in ipairs({{1440,900},{1000,600},{390,720},{360,582},{750,304},{680,262},{834,1100}})do
  local holder=Instance.new("Frame");holder.Name="Viewport";holder.Size=UDim2.fromOffset(case[1],case[2]);holder.Parent=gui
  local rows={};for i=1,100 do rows[i]={UserId=i,Name="Fixture"..i,DisplayName="Funded Trader "..i,Cents=(90-i)*123456,Eligible=true,Tier="$100K",Rank=i}end
  local own=table.clone(rows[100]);own.Rank=nil;own.Status="Outside top 100"
  local c=UI.Mount(holder,{Preview=true,LeaderboardData={Rows=rows,Your=own,State="Ready",Studio=true}})
  task.wait(.05)
  local lb=c.Root.Canvas.Leaderboard
  local list,pin=lb.Rows,lb.YourStanding
  assert(list.AbsolutePosition.Y+list.AbsoluteSize.Y<=pin.AbsolutePosition.Y,"List overlaps pinned standing")
  assert(pin.You.AbsolutePosition.Y+pin.You.AbsoluteSize.Y<=lb.AbsolutePosition.Y+lb.AbsoluteSize.Y+1,"Pinned row is clipped")
  assert(list.AbsoluteSize.Y>=list:FindFirstChild("Player1").AbsoluteSize.Y,"Less than one full row visible")
  assert(lb:GetAttribute("RowCount")==100 and pin.You.Profit.Text:find("12,345.60"),"Rows/profit missing")
  assert(pin.StandingStatus.Text=="Outside top 100" and pin.You.Rank.Text=="—","Unverified global rank shown")
  assert(lb.TabGlobal.AbsoluteSize.Y>=40 and lb.TabServer.AbsoluteSize.Y>=40,"Tabs too small")
  local nav=c.Root.Canvas:FindFirstChild("MobileNavigation")or c.Root.Canvas.Sidebar
  assert(nav.NavLeaderboard,"Missing navigation")
  for _,r in ipairs(list:GetChildren())do
   if r:IsA("Frame")then
    assert(r.PlayerName.AbsoluteSize.X>=35,"Player name has no usable width")
    assert(r.Profit.AbsolutePosition.X>=r.PlayerName.AbsolutePosition.X+r.PlayerName.AbsoluteSize.X,"Profit overlaps name")
   end
  end
  table.insert(report,{Width=case[1],Height=case[2],Rows=100,ListHeight=list.AbsoluteSize.Y,RowHeight=list.Player1.AbsoluteSize.Y,Passed=true})
  c:Destroy();holder:Destroy()
 end
 -- Validate all data-state labels using the same renderer, without any network/storage writes.
 for _,state in ipairs({"Loading","Empty","Error","Stale"})do
  local holder=Instance.new("Frame");holder.Size=UDim2.fromOffset(390,720);holder.Parent=gui
  local own={UserId=1,Name="Fixture",DisplayName="New Trader",Cents=0,Eligible=false,Tier="—",Status="Complete a trade to join"}
  local c=UI.Mount(holder,{Preview=true,LeaderboardData={Rows={},Your=own,State=state,Studio=true}})
  local lb=c.Root.Canvas.Leaderboard
  assert(lb:GetAttribute("State")==state and lb.YourStanding.StandingStatus.Text==own.Status)
  if state=="Error"or state=="Stale"then assert(lb.Retry.ControlLabel.Text=="Retry")end
  table.insert(report,{State=state,Passed=true});c:Destroy();holder:Destroy()
 end
end)
gui:Destroy();shared:Destroy()
assert(ok,err)
return report
