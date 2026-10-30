-- Disposable engines and native UI, with real market-update callbacks and no live remotes/storage.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="LiveBalanceQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="LiveBalanceQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do if m:IsA("LuaSourceContainer")then
 m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.LiveBalanceQA"):gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.LiveBalanceQA")
end end end
local gui=Instance.new("ScreenGui");gui.Name="LiveBalanceQA";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local report={Passed=true,Checks=0,Layouts={},Suites={},StorageAccessed=false}
 local function check(value,message)assert(value,message);report.Checks+=1 end
 local E=require(server.MarketEngine);local F=require(server.FundedAccounts);local T=require(server.TestLiquidity)
 local C=require(shared.MarketConfig);local L=table.clone(require(shared.ProgressionConfig));L.StartingBalance=40000
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local Board=require(shared.LeaderboardClient);local boardNew=Board.new;Board.new=function()return boardNew(true)end
 local Purchase=require(shared.DepthPurchase);local purchaseNew=Purchase.new
 Purchase.new=function(session,_,changed)return purchaseNew(session,true,changed)end
 local original=Market.New
 for _,name in ipairs({"TradeLimitsTests","SingleAccountTests"})do
  local rows=require(server[name]).Run();report.Suites[name]=rows
  for _,row in ipairs(rows)do check(row.Passed,name..": "..row.Name..": "..tostring(row.Detail))end
 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1000,600},{1280,720},{1920,1080}})do
  local e=E.new(C,712);local f=F.new(e,L,C);f:Join("balance-qa");f:Profile("balance-qa").Tutorial="Done"
  local a=e.Accounts[f:Owner("balance-qa")]
  check(e:ContractLimit(a)==40,"$40K starts with a 40-contract limit")
  check(T.Submit(e,a.Id,{Contract="BX",Direction=1,Quantity=40,Type="Market"}),"Open 40 contracts")
  local entry=a.Positions.BX.Entry;local session
  local function update()
   local snap=e:Snapshot(a.Id,"BX","1m",true)
   session.AccountKey=a.Id;session.AccountToken=a.Id;session.Portfolio=f:View("balance-qa")
   session.SummaryData=snap.Summary;session.Positions=snap.Positions;session.Orders=snap.Orders;session.History=snap.History;session.Fills=snap.Fills
   session.Quotes=snap.Quotes;session.Limit=snap.Limit;session.Capacity=snap.Capacity;session.Triggers=snap.Triggers
   for key,quote in pairs(snap.Quotes)do session.Prices[key]=quote.Last end
  end
  Market.New=function()
   local data={Quotes={},CandlesBySeries={},Time=3600,Step=1}
   for _,key in ipairs(C.ContractOrder)do
    local price=C.Contracts[key].Last;data.Quotes[key]={Last=price,Open=price,Bid=price,Ask=price}
    for _,tf in ipairs(C.Timeframes)do
     local candles={};for i=1,60 do candles[i]={Time=(i-1)*tf[2],Open=price,High=price+1,Low=price-1,Close=price,Volume=10}end
     data.CandlesBySeries[key..":"..tf[1]]=candles
    end
   end
   session=original(40000,true,data);session.Ready=true;session.CanTrade=true;session.ConnectionStatus="Isolated fixture"
   session.Send=function()return true,"Fixture",nil,0 end
   update();return session
  end
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  ctl=UI.Mount(host);task.wait(.08);session.Changed:Fire();task.wait(.08)
  local balanceLabel=ctl.Root.Canvas.AccountSummary:FindFirstChild("BalanceValue",true)
  check(balanceLabel and balanceLabel.Text=="$40,000.00","Initial balance uses live account value")
  for _,value in ipairs({50000,30000,40000,50000})do
   local book=e.Books.BX;book.Last=math.round((entry+(value-40000)/(40*book.Spec.Multiplier))/book.Spec.Tick)
   update();ctl.State.Qty=50;session.Changed:Fire();task.wait(.08)
   local current=ctl.Root.Canvas.AccountSummary:FindFirstChild("BalanceValue",true)
   check(current==balanceLabel,"Price-only updates preserve the balance control")
   check(current.Text==Market.Money(value) and current.TextFits,"Live balance renders gains and losses")
   check(ctl.Root:GetAttribute("Balance")==value and ctl.Root:GetAttribute("SettledBalance")==40000,"Display and settled balance stay separate: expected "..value..", actual "..tostring(ctl.Root:GetAttribute("Balance"))..", settled "..tostring(ctl.Root:GetAttribute("SettledBalance")))
   check(session.SummaryData.Balance==40000 and session.Limit==40 and ctl.State.Qty==40,"Open gains do not raise sizing")
   check(session.Capacity.BX.Buy==0 and session.Capacity.BG.Buy==0,"All 40 contracts remain reserved across markets")
   for _,key in ipairs({"BX","BG"})do
    check(not e:Submit(a.Id,{Contract=key,Direction=1,Quantity=10,Type="Market"}),"Server rejects ten extra "..key.." contracts")
   end
   check(not ctl.Root:GetAttribute("RenderError"),"No render errors")
  end
  -- Rejoining cannot convert an open gain into additional settled buying power.
  local P=require(server.Participants);local CP=require(server.WorldCheckpoint)
  local population=setmetatable({Engine=e,Config=C,Random=P.RNG.new(712),Agents={}},P)
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,population))),C)
  local restoredAccount=restored.Accounts[a.Id]
  check(restored:Summary(restoredAccount).Equity==50000 and restored:ContractLimit(restoredAccount)==40,"Save/reload keeps the cap at 40")
  check(restored:OrderCapacity(restoredAccount,"BX",1)==0,"Reload does not unlock extra entry capacity")
  check(T.Submit(e,a.Id,{Contract="BX",Direction=-1,Quantity=40,Type="Market",ReduceOnly=true}),"Full position can close")
  update();session.Changed:Fire();task.wait(.08)
  check(a.Balance==50000 and session.SummaryData.Unrealized==0 and session.Limit==50,"Closed profit unlocks the next trade's 50-contract cap")
  check(ctl.Root.Canvas.AccountSummary:FindFirstChild("BalanceValue",true).Text=="$50,000.00","Closing never double-counts open profit")
  ctl.State.Overlay="QuantityLimit";ctl.State.QuantityLimit=50;ctl.State.QuantitySymbol="BX";ctl.Chart.Ctx.refresh();task.wait(.08)
  local message=ctl.Root:FindFirstChild("LimitMessage",true)
  check(message and message.TextFits and message.Text:find("settled balance",1,true),"Sizing explanation fits")
  ctl.State.Overlay="Help";ctl.Chart.Ctx.refresh();task.wait(.08)
  check(not ctl.Root:GetAttribute("RenderError"),"Help renders with the live balance definition")
  e:Audit();restored:Audit()
  table.insert(report.Layouts,{Width=size[1],Height=size[2],EntryLimit=40,OpenGainLimit=40,AfterCloseLimit=50})
  ctl:Destroy();ctl=nil;host:Destroy()
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end
gui:Destroy();shared:Destroy();server:Destroy()
assert(ok,result)
return result
