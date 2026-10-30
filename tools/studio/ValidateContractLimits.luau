-- Disposable engines and GUI only. Never accesses a live account, remote or DataStore.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ContractLimitsQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="ContractLimitsQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do
 if m:IsA("LuaSourceContainer")then m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.ContractLimitsQA"):gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.ContractLimitsQA")end
end end
local gui=Instance.new("ScreenGui");gui.Name="ContractLimitsQA";gui.Parent=game.StarterGui
local controller
local ok,result=xpcall(function()
 local report={Passed=true,Suites={},UI={}}
 for _,name in ipairs({"TradeLimitsTests","MarketTests","WorldTests","SingleAccountTests","TradeAmendmentTests","SecurityTests"})do
  local test=require(server[name]);local value=type(test)=="function"and test()or test.Run()
  report.Suites[name]=value
  if value.Passed==false then report.Passed=false end
  for _,row in ipairs(value.Results or value)do if row.Passed==false then report.Passed=false end end
 end
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts)
 local C=require(shared.MarketConfig);local L=require(shared.ProgressionConfig)
 local e=E.new(C,51);local f=F.new(e,L,C);f:Start("ui-test")
 local a=e.Accounts[f:Owner("ui-test")]
 local original=Market.New;local session
 Market.New=function()
  local data={Quotes={},CandlesBySeries={},Time=3600,Step=1}
  for _,key in ipairs(C.ContractOrder)do
   local price=C.Contracts[key].Last;data.Quotes[key]={Last=price,Open=price,Bid=price,Ask=price}
   for _,tf in ipairs(C.Timeframes)do data.CandlesBySeries[key..":"..tf[1]]={{Time=0,Open=price,High=price+1,Low=price-1,Close=price,Volume=1}}end
  end
  session=original(nil,true,data);session.Ready=true;session.CanTrade=true
  return session
 end
 local host=Instance.new("Frame");host.Size=UDim2.fromOffset(1280,800);host.Parent=gui
 controller=UI.Mount(host,{Preview=true})
 for _,pair in ipairs({{500,5},{5000,5},{5999.99,5},{6000,6},{10000,10},{50000,50},{59975,59},{101000,101},{250000,250}})do
  a.Balance=pair[1];a.Realized=a.Balance-a.Base
  local snap=e:Snapshot(a.Id,"BX","1m",true)
  session.SummaryData=snap.Summary;session.Limit=snap.Limit;session.Capacity=snap.Capacity;session.Portfolio=f:View("ui-test")
  controller.State.Qty=pair[2]+1
  controller.Chart.Ctx.refresh();task.wait(.1)
  local quantity=controller.Root:FindFirstChild("Quantity",true)
  assert(quantity and quantity.Value.Text==tostring(pair[2]),"Ticket quantity mismatch for balance "..pair[1])
  assert(controller.State.Qty==pair[2] and snap.Capacity.BX.Buy==pair[2] and session.Portfolio.Accounts[1].Limit==pair[2])
  assert(not controller.Root:GetAttribute("RenderError"),"UI render error")
  table.insert(report.UI,{Balance=pair[1],Maximum=pair[2],Displayed=quantity.Value.Text})
 end
 return report
end,debug.traceback)
if controller then controller:Destroy()end
gui:Destroy();shared:Destroy();server:Destroy()
assert(ok,result)
return result
