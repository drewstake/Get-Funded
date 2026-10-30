local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ShopUIValidation";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="ShopUIValidation";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
local gui=Instance.new("ScreenGui");gui.Name="ShopUIValidation";gui.IgnoreGuiInset=true;gui.DisplayOrder=100;gui.Parent=game.StarterGui
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
local ctl
local ok,result=pcall(function()
 local M=require(shared.MarketClient);local UI=require(shared.TerminalUI);local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local e=E.new(C,51);local f=F.new(e,L,C);f:Start("fixture");f:Flag("fixture","TutorialDone")
 local a=e.Accounts[f:Owner("fixture")];a.Realized=8000;a.Balance=13000;f:Evaluate("fixture")
 f:Activate("fixture","F10K");f:Activate("fixture","F25K")
 local p=f:Profile("fixture");p.WalletCents=10000000
 for seq=1,7 do assert(f:Purchase("fixture","F5K",seq)) end
 local dead=e.Accounts[p.Tiers.F10K.Account];dead.Realized=-10000;dead.Balance=0;dead.Locked=true;dead.Depleted=true;f:Evaluate("fixture")
 local original=M.New;local session;local sent=0
 function M.New()
  local snap=e:Snapshot(a.Id,"BX","1m",true);snap.CandlesBySeries={}
  session=original(nil,true,snap);session.Preview=false;session.Ready=true;session.CanTrade=true;session.AccountToken=a.Id
  session.Portfolio=f:View("fixture");session.SummaryData=e:Summary(a);session.Stats=f:Stats("fixture");session.StatsAt=os.clock()
  function session:Send(action,request)
   if action=="Purchase" then
    sent+=1;local id=sent
    task.delay(.05,function()
     local yes,message,receipt=f:Purchase("fixture",request.Tier,request.PurchaseSequence)
     session.Portfolio=f:View("fixture");session.Replies:Fire({Kind="Purchase",Ok=yes,Message=message,Receipt=receipt,RequestId=id});session.Changed:Fire()
    end)
    return true,"Sent","Orders",id
   end
   return true,"Isolated UI fixture","Orders",0
  end
  return session
 end
 local host=Instance.new("Frame");host.Size=UDim2.fromOffset(1440,900);host.Parent=gui
 ctl=UI.Mount(host);local hook=ctl.Root.UIDiagnostics
 hook:Invoke("Set","Screen","Shop");task.wait(.05)
 assert(ctl.Root.Canvas.Shop and ctl.Root.Canvas.Sidebar.NavShop,"Shop navigation absent")
 local before=#p.Ledger;local wallet=p.WalletCents
 ctl.Root.Canvas.Shop.ShopF5K.Buy.TestActivate:Invoke();task.wait(.05)
 local confirm=ctl.Root.Canvas.Dialog.Content.ConfirmPurchase
 for _=1,10 do confirm.TestActivate:Invoke() end
 task.wait(.15)
 assert(sent==1 and #p.Ledger==before+1 and p.WalletCents==wallet-200000,"Repeated clicks created extra purchase")
 assert(ctl.State.Overlay=="PurchaseComplete" and ctl.Root.Canvas.Dialog,"Styled durable confirmation missing")
 hook:Invoke("Set","Overlay",nil)
 local report={Views=0,RepeatedClickRequests=sent,Issues={},Layouts={}}
 for _,size in ipairs({{320,568},{390,844},{844,390},{1280,720},{1440,900},{1920,1080}}) do
  host.Size=UDim2.fromOffset(size[1],size[2]);task.wait(.06)
  for _,screen in ipairs({"Shop","Dashboard","Stats","Trade"}) do
   ctl.State.Overlay=nil;ctl.State.Screen=screen;hook:Invoke("Render");task.wait(.05)
   local surface=ctl.Root.Canvas:FindFirstChild(screen=="Dashboard" and "Dashboard" or screen)
   if screen~="Trade" then assert(surface,"Missing "..screen) end
   local nav=ctl.Root.Canvas:FindFirstChild("MobileNavigation") or ctl.Root.Canvas:FindFirstChild("Sidebar")
   assert(nav and nav.NavShop,"Shop tab missing at "..size[1])
   for _,label in ipairs(ctl.Root.Canvas:GetDescendants()) do
    if label:IsA("TextLabel") and label.Visible and label.Text~="" and not label.TextFits and not label.TextScaled and label.TextTruncate==Enum.TextTruncate.None then
     table.insert(report.Issues,string.format("%dx%d %s %s: %s",size[1],size[2],screen,label:GetFullName():gsub(".*Canvas%.",""),label.Text))
    end
    if label:IsA("TextLabel") then assert(not label.Text:lower():find("re%-earn") and not label.Text:lower():find("legacy"),"Obsolete UI wording") end
   end
   report.Views+=1
  end
  for _,overlay in ipairs({"Purchase","PurchaseComplete","Blown","Accounts"}) do
   ctl.State.Screen="Shop";ctl.State.ShopIntent={Tier="F25K",Name="$25K Funded",Size=25000,Price=15000,Sequence=p.PurchaseSequence+1}
   ctl.State.BlownTier=dead.InstanceKey;ctl.State.BlownEvent=dead.InstanceKey
   ctl.State.Overlay=overlay;hook:Invoke("Render");task.wait(.05)
   local dialog=ctl.Root.Canvas.Dialog
   assert(dialog.AbsoluteSize.X<=size[1] and dialog.AbsoluteSize.Y<=size[2],"Dialog exceeds viewport")
   for _,label in ipairs(dialog:GetDescendants()) do
    if label:IsA("TextLabel") and label.Visible and label.Text~="" and not label.TextFits and not label.TextScaled and label.TextTruncate==Enum.TextTruncate.None then
     table.insert(report.Issues,string.format("%dx%d %s %s: %s",size[1],size[2],overlay,label.Name,label.Text))
    end
   end
   report.Views+=1
  end
  local items={};for i=1,20 do table.insert(items,{Name="$100K #"..i,Status="Copied",Message="Filled 1 contract"}) end
  session.Replies:Fire({RequestId=999,Kind="Place",Ok=true,Message="Copy fixture",Copies={Leader="$100K #100",Items=items,Copied=20,Rejected=0,Skipped=0,Total=20}})
  task.wait(.03)
  local copyReport=ctl.Root:FindFirstChild("CopyReport");assert(copyReport and copyReport.Position.Y.Offset+copyReport.Size.Y.Offset<=size[2],"Copy report exceeds viewport")
  assert(copyReport.Rows.CanvasSize.Y.Offset==560,"Copy rows missing");if size[2]<600 then assert(copyReport.Rows.CanvasSize.Y.Offset>copyReport.Rows.Size.Y.Offset,"Long copy report must scroll") end
  copyReport:Destroy();report.Views+=1
  table.insert(report.Layouts,size[1].."x"..size[2])
 end
 ctl.State.Overlay=nil;ctl.State.Screen="Shop";p.WalletCents=0;session.Portfolio=f:View("fixture");hook:Invoke("Render");task.wait()
 local buy=ctl.Root.Canvas.Shop.ShopF5K.Buy
 assert(buy.Active and buy.ControlLabel.Text=="Purchase" and buy:GetAttribute("Gloss")=="Grey","Unaffordable Purchase must look grey and allow balance feedback")
 assert(not ctl.Root.Canvas.Shop.ShopF5K:FindFirstChild("Availability"),"Shop account counts or deficit text remained")
 local requests=sent;local accounts=#p.Ledger
 buy.TestActivate:Invoke();task.wait()
 assert(ctl.State.Error=="Insufficient balance." and ctl.State.Toast=="Insufficient balance." and not ctl.State.Overlay,"Missing insufficient balance feedback")
 assert(sent==requests and #p.Ledger==accounts and p.WalletCents==0,"Unaffordable click attempted a purchase")
 report.InsufficientBalanceFeedback=true
 assert(not ctl.Root.Canvas.Shop.ShopF100K.Buy.Active,"Locked account remained enabled")
 return report
end)
if ctl then ctl:Destroy() end
gui:Destroy();shared:Destroy();server:Destroy()
assert(ok,result);return result
