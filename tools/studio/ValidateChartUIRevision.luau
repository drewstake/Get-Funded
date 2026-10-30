-- Isolated Studio Edit integration fixture. Uses the real portfolio evaluator and client Changed path.
-- No remote requests, live account writes, or DataStore access.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ChartRevisionFixture";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="ChartRevisionFixture";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="ChartRevisionFixture";gui.Parent=game.StarterGui
local controller
local ok,result=pcall(function()
 local M=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local config=require(shared.MarketConfig);local ladder=require(shared.ProgressionConfig)
 local e=E.new(config,91);local f=F.new(e,ladder,config);f:Start("fixture");f:Flag("fixture","TutorialDone")
 local a=e.Accounts[f:Owner("fixture")]
 local new=M.New;local session
 M.New=function()
  session=new(nil,true);session.Preview=false;session.Ready=true;session.CanTrade=true;session.AccountKey=a.Id;session.Portfolio=f:View("fixture")
  session.Send=function()return true,"Fixture","Orders",1 end
  return session
 end
 local holder=Instance.new("Frame");holder.Size=UDim2.fromOffset(1280,720);holder.Parent=gui
 controller=UI.Mount(holder)
 local r=controller.Root;local rows={}
 for _,earned in ipairs({0,1250,3000,4250})do
  a.Realized=earned;a.Balance=a.Base+earned;f:Evaluate("fixture")
  session.Portfolio=f:View("fixture");session.Changed:Fire();task.wait();task.wait()
  local nextStage=session.Portfolio.Next
  local card=r.Canvas.Dashboard.NextUnlock
  assert(card.Amount.Text==M.Money(nextStage.Projected).." / "..M.Money(nextStage.Goal):gsub('%.00',''),"Live amount mismatch")
  local fill=card.Progress.Fill
  assert(fill.Visible==(nextStage.Progress>0),"Zero-to-positive bar visibility")
  local ratio=nextStage.Progress/nextStage.Goal
  if ratio>0 then assert(math.abs(fill.Size.X.Offset/(card.Progress.Size.X.Offset-4)-ratio)<.02,"Live bar ratio")end
  table.insert(rows,{Realized=earned,Amount=card.Amount.Text,Goal=nextStage.Goal,Progress=nextStage.Progress})
 end
 controller.State.Qty=3;controller.State.StopDollars=100;controller.State.TargetDollars=200
 session.Changed:Fire();task.wait()
 assert(r:GetAttribute("StopEffectiveDollars")==112.5 and r:GetAttribute("TargetEffectiveDollars")==187.5,"Quantity-aware protection estimates")
 controller.State.Contract="BT";session.Changed:Fire();task.wait()
 assert(r:GetAttribute("StopEffectiveDollars")==105 and r:GetAttribute("TargetEffectiveDollars")==195,"Instrument change recomputes dollar rounding")
 controller.State.Type="Limit";controller.State.Limit=22000;session.Changed:Fire();task.wait()
 assert(r:GetAttribute("StopBuyPrice")==21998.25 and r:GetAttribute("StopSellPrice")==22001.75,"Entry change recomputes protection prices")
 return {Passed=true,LiveProgress=rows,Protection={BX={112.5,187.5},BT={105,195},NQEntry=22000}}
end)
if controller then controller:Destroy()end gui:Destroy();shared:Destroy();server:Destroy()
if not ok then error(result)end
return result
