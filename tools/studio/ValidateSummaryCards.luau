-- Isolated Edit-mode layout verification. Does not connect to the exchange or send orders.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="SummaryCardsValidation";shared.Parent=game.ReplicatedStorage
local gui=Instance.new("ScreenGui");gui.Name="SummaryCardsValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local results={}
local ok,err=pcall(function()
 local Market=require(shared.MarketClient)
 local originalNew=Market.New
 local preset={}
 function Market.New(...)
  local session=originalNew(...)
  session.SummaryData.Balance=preset.Balance or 5000
  session.SummaryData.Unrealized=preset.Pnl or 0
  session.SummaryData.Equity=session.SummaryData.Balance+session.SummaryData.Unrealized
  session.Portfolio=preset.Portfolio
  return session
 end
 local UI=require(shared.TerminalUI)
 local sizes={{320,568},{390,844},{844,390},{1000,600},{1280,720},{1440,900},{1920,1080}}
 for _,size in ipairs(sizes)do
  for _,large in ipairs({false,true})do
   preset=large and{Balance=1234567.89,Pnl=-12345.67,Portfolio={ActiveShort="$100K",ActiveKind="Funded",Earned=3150,FirstProfit=25,Next={Name="$25K Funded",Short="$25K",Unlock=8000,Goal=5000,Progress=150,Remaining=4850}}}or{}
   local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
   local controller=UI.Mount(host,{Preview=true})
   task.wait(.1)
   local canvas=controller.Root.Canvas
   local summary=canvas.AccountSummary
   local issues={}
   for _,label in ipairs(summary:GetDescendants())do
    if label:IsA("TextLabel")and not label.TextFits then table.insert(issues,"Text overflow: "..label.Name.." / "..label.Text)end
    if label:IsA("GuiObject")and not label:FindFirstAncestor("Texture")then
     local pos=label.AbsolutePosition-summary.AbsolutePosition
     if pos.X<-.5 or pos.Y<-.5 or pos.X+label.AbsoluteSize.X>summary.AbsoluteSize.X+.5 or pos.Y+label.AbsoluteSize.Y>summary.AbsoluteSize.Y+.5 then
      table.insert(issues,"Bounds: "..label.Name)
     end
    end
   end
   if size[1]>=1000 and size[2]>=600 then
    assert(summary.ObjectiveCard.Track.Well,"Missing progress track")
    assert(summary.BalanceCard.AccountBadge,"Missing account badge")
    assert(canvas.Chart.Position.Y.Offset>=summary.Position.Y.Offset+summary.Size.Y.Offset,"Chart overlaps summary")
    assert(canvas.OrderTicket.Position.Y.Offset==canvas.Chart.Position.Y.Offset,"Ticket/chart misaligned")
    if large then
     assert(summary.UnrealizedValue.TextColor3==Color3.fromRGB(255,143,166),"Negative P&L color")
     assert(summary.ObjectiveCard.Title.Text=="$25K Funded","Next tier headline")
     assert(summary.ObjectiveCard.Track.Fill,"Missing earned progress")
    end
   end
   table.insert(results,{Width=size[1],Height=size[2],LargeValues=large,Issues=issues})
   controller:Destroy();host:Destroy()
  end
 end
end)
gui:Destroy();shared:Destroy()
assert(ok,err)
return results
