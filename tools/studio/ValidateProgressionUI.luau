-- Isolated Edit views generated from the funded model; no DataStore or remotes.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ProgressionUIValidation";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="ProgressionUIValidation";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="ProgressionUIValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local controller local report={Views=0,Issues={}}
local ok,err=pcall(function()
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local config=require(shared.MarketConfig);local ladder=require(shared.ProgressionConfig)
 local e=E.new(config,1);local f=F.new(e,ladder,config);f:Start("fixture");f:Flag("fixture","TutorialDone")
 local a=e.Accounts[f:Owner("fixture")]
 local original=Market.New local view
 function Market.New(base)
  local session=original(base,true)
  session.Preview=false;session.Ready=true;session.CanTrade=true;session.Portfolio=view;session.AccountKey="F5K"
  session.ConnectionStatus="ISOLATED UI TEST";session.PersistenceMode="Test"
  function session:Send()return true,"Isolated test"end
  return session
 end
 for _,profit in ipairs({0,3000,8000,18000,38000,77999.99,78000}) do
  a.Realized=profit;a.Balance=5000+profit;f:Evaluate("fixture");view=f:View("fixture")
  for _,size in ipairs({{320,568},{390,844},{844,390},{1440,900},{1920,1080}}) do
   local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
   controller=UI.Mount(host)
   for _,screen in ipairs({"Trade","Dashboard"}) do
    controller.Root.UIDiagnostics:Invoke("Set","Screen",screen);task.wait(.07)
    for _,label in ipairs(controller.Root.Canvas:GetDescendants()) do
     if label:IsA("TextLabel") and label.Visible and label.Text~="" and not label.TextFits and not label.TextScaled and label.TextTruncate==Enum.TextTruncate.None then
      table.insert(report.Issues,string.format("%dx%d %s profit %.2f: %s '%s'",size[1],size[2],screen,profit,label.Name,label.Text))
     end
    end
    if profit==3000 and screen=="Dashboard" then
     local amount=controller.Root.Canvas:FindFirstChild("Amount",true)
     assert(amount and amount.Text=="$0 / $5,000","Stage did not reset at $3,000")
    end
    report.Views+=1
   end
   controller:Destroy();controller=nil;host:Destroy()
  end
 end
 assert(#report.Issues==0,table.concat(report.Issues,"\n"))
end)
if controller then controller:Destroy()end
gui:Destroy();shared:Destroy();server:Destroy()
assert(ok,err)
return report
