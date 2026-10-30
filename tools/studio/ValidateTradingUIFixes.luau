-- Isolated Studio Edit validation. No remote orders or saved portfolio changes.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="TradingUIFixValidation";shared.Parent=game.ReplicatedStorage
local mock=[==[
local originalNew=Market.New
-- Portfolio presets for isolated layout checks. The live game receives these views from the server.
function Market.FixturePortfolio(kind)
 if kind=="new"then return{New=true,Revision=0}end
 local tiers=Progression.Tiers
 local view={Revision=1,Active="F5K",ActiveKind="Funded",ActiveName=tiers[1].Name,ActiveShort=tiers[1].Short,ActiveSize=tiers[1].Size,
  Tutorial=kind=="tour"and"Pending"or"Done",Started=true,Earned=0,Capital=0,Open=0,ActiveCount=0,Accounts={},Legacy={},
  Copy={Enabled=false,Followers={},Sizing="Same"},CopyIntro=false}
 local states=kind=="ladder"and{"Active","Active","Active","Unlocked","Locked"}or{"Active","Locked","Locked","Locked","Locked"}
 if kind=="ladder"then view.Earned=18210.5;view.FirstProfit=42.5;view.Copy={Enabled=true,Leader="F10K",Followers={"F5K","F25K"},Sizing="Same"}
  view.Legacy={{Key="L50000",Name="$50K Practice",Size=50000,Balance=50203.75,Equity=50203.75,Unrealized=0,Realized=203.75,Allowance=50203.75,Positions=0,Orders=0,Breached=false}}end
 for i,t in ipairs(tiers)do
  local row={Key=t.Id,Name=t.Name,Short=t.Short,Size=t.Size,Unlock=t.Unlock,LossLimit=t.LossLimit,MaxContracts=t.MaxContracts,Goal=t.Unlock-(tiers[i-1] and tiers[i-1].Unlock or 0),Progress=view.Earned-(tiers[i-1] and tiers[i-1].Unlock or 0),State=states[i]or"Locked"}
  if row.State=="Active"then
   row.Balance=kind=="ladder" and (i==1 and 0 or t.Size+(i==2 and 18120.25 or i==3 and 5090.25 or 0)) or t.Size;row.Equity=row.Balance;row.Unrealized=0;row.Realized=row.Balance-t.Size
   row.Allowance=row.Equity;row.Positions=0;row.Orders=0;row.Breached=kind=="ladder"and i==1;row.Attempt=1
   view.Capital+=t.Size;view.ActiveCount+=1
   if view.Copy.Enabled then row.Role=view.Copy.Leader==t.Id and"Lead"or table.find(view.Copy.Followers,t.Id)and"Follow"or nil end
  end
  if row.State=="Locked"and not view.Next then view.Next={Key=t.Id,Name=t.Name,Short=t.Short,Unlock=t.Unlock,Goal=row.Goal,Progress=row.Progress,Remaining=math.max(0,t.Unlock-view.Earned)}end
  table.insert(view.Accounts,row)
 end
 view.CopyAvailable=view.ActiveCount>=2
 return view
end
function Market.New(base)
 local fixture={Quotes={},CandlesBySeries={},Time=2400,Step=1}
 for _,key in ipairs(Config.ContractOrder)do
  local c=Config.Contracts[key]
  fixture.Quotes[key]={Last=c.Last,Open=c.Last-4*c.Tick,Bid=c.Last-c.Tick,Ask=c.Last+c.Tick,Spread=2*c.Tick,Volume=200}
  for _,tf in ipairs(Config.Timeframes)do
   local candles={}
   for i=1,40 do
    local price=c.Last+math.floor(math.sin(i*.5)*8)*c.Tick
    candles[i]={Time=(i-1)*tf[2],Open=price,Close=price+(i%2==0 and 2 or -2)*c.Tick,High=price+4*c.Tick,Low=price-4*c.Tick,Volume=10+i}
   end
   fixture.CandlesBySeries[key..":"..tf[1]]=candles
  end
 end
 local self=originalNew(base,true,fixture)
 self.Preview=false;self.Ready=true;self.CanTrade=true;self.PersistenceMode="Test";self.ConnectionStatus="ISOLATED UI TEST"
 self.Portfolio=Market.FixturePortfolio("starter");self.AccountKey="F5K"
 self.TestLog={};self.Regime="UI fixture"
 function self:Send(action,req)
  self.NextId+=1;req=req or{};req.Action=action
  table.insert(self.TestLog,table.clone(req))
  if action=="Start"or action=="Account"or action=="Activate"or action=="Copy"or action=="Flag"or action=="Restart"then
   task.defer(function()self.Replies:Fire({RequestId=self.NextId,Ok=true,Kind=action,Message="Isolated UI test · "..action})self.Changed:Fire()end)
   return true,"Isolated UI test · "..action,"Positions",self.NextId
  end
  if action=="Place" and self.TestReject then
   local requestId=self.NextId
   task.defer(function()self.Replies:Fire({RequestId=requestId,Ok=false,Kind=action,Message="Insufficient simulated margin after existing positions and working orders. Maximum currently available: 2 BT."});self.Changed:Fire()end)
   return true,"Sending","Orders",requestId
  end
  if action=="Place"then
   local c=Config.Contracts[req.Contract]
   if req.Type=="Limit"then
    table.insert(self.Orders,{Id=self.NextId,Contract=req.Contract,Kind="Limit",Quantity=req.Quantity,Price=req.Price,Status="Working"})
   else
    self.Positions[req.Contract]={Id=self.NextId,Contract=req.Contract,Direction=req.Direction,Quantity=req.Quantity,Entry=c.Last,Unrealized=25,
     Stop=req.StopDollars and Market.Protection(c,req.Quantity,req.StopDollars,c.Last,req.Direction,"Stop").Price,Target=req.TargetDollars and Market.Protection(c,req.Quantity,req.TargetDollars,c.Last,req.Direction,"Target").Price}
   end
  elseif action=="Close"then self.Positions[req.Contract]=nil
  elseif action=="Cancel"then
   for i,o in ipairs(self.Orders)do if o.Id==req.OrderId then table.remove(self.Orders,i);break end end
  elseif action=="AmendProtection"then self.Positions[req.Contract][req.Protection]=req.Price
  end
  local count=0 for _ in pairs(self.Positions)do count+=1 end
  self.SummaryData.Count=count;self.SummaryData.Unrealized=count*25;self.SummaryData.Equity=self.SummaryData.Balance+count*25
  local requestId=self.NextId
  task.defer(function()self.Replies:Fire({RequestId=requestId,Ok=true,Kind=action,Message="Isolated UI test · "..action});self.Changed:Fire()end)
  return true,"Isolated UI test · "..action,"Positions",self.NextId
 end
 Market.TestSession=self
 return self
end
]==]
shared.MarketClient.Source=shared.MarketClient.Source:gsub("return Market%s*$",function()return mock.."\nreturn Market"end)
-- Exercise actual callbacks through hooks present only in this disposable clone.
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end):gsub("return shell,commit",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestCommit";hook.OnInvoke=commit;hook.Parent=shell;return shell,commit'
end):gsub("local controller={Root=root,State=s,Chart=chartView}",function()
 return "local controller={Root=root,State=s,Chart=chartView};function controller:TestRender()render()end"
end)

-- Test-only input-state hook on a disposable source clone; never installed in the real GUI.
shared.UIFeedback.Source=shared.UIFeedback.Source:gsub('b.MouseEnter:Connect%(function%(%)',function()
 return [[local hook=Instance.new("BindableFunction");hook.Name="TestFeedback";hook.Parent=b
 hook.OnInvoke=function(name)
  if name=="Down"then self:Mem(k()).PressedAt=os.clock()end
  if name=="Hover"then self:Mem(k()).Hover=true end
  state(name);darken(name=="Down")
 end
 b.MouseEnter:Connect(function()]]
end)
local gui=Instance.new("ScreenGui");gui.Name="TradingUIFixValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local results={Layouts={},Rejections=0,Successes=0,GeometrySamples=0,PnlUpdates=0,Selectors=0}
local controller
local ok,err=pcall(function()
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 for _,size in ipairs({{320,568},{390,844},{844,390},{1000,600},{1280,720},{1440,900},{1920,1080}})do
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  controller=UI.Mount(host);local s=controller.State;local session=Market.TestSession
  s.Screen="Trade";s.Contract="BT";s.Qty=5;controller:TestRender();task.wait(.12)
  local function get(name)return assert(controller.Root.Canvas:FindFirstChild(name,true),"Missing "..name)end
  local function geometry(b)return {b.Position,b.Size,b.AnchorPoint,b.AbsolutePosition,b.AbsoluteSize}end
  local baseline={BuyLong=geometry(get("BuyLong")),SellShort=geometry(get("SellShort"))}
  local function sample()
   assert(not controller.Root:GetAttribute("RenderError"),controller.Root:GetAttribute("RenderError"))
   for name,g in pairs(baseline)do
    local b=get(name);local actual=geometry(b)
    for i,value in ipairs(g)do assert(actual[i]==value,name.." geometry changed "..i.." at "..size[1].."x"..size[2].." / "..tostring(actual[i]).." vs "..tostring(value))end
    local scale=b:FindFirstChild("PressScale");assert(not scale or scale.Scale==1,"Trade button scaled")
   end
   results.GeometrySamples+=1
  end
  session.TestReject=true
  for i=1,8 do
   local name=i%2==1 and "BuyLong"or"SellShort"
   get(name).TestFeedback:Invoke("Hover");sample()
   get(name).TestFeedback:Invoke("Down");sample()
   get(name).TestActivate:Invoke();sample()
   local start=os.clock()
   repeat task.wait();sample()until os.clock()-start>.22
   get(name).TestFeedback:Invoke("Release");sample()
   get(name).TestFeedback:Invoke("Leave");sample()
   local message=get("Toast").Message
   assert(message.Text:find("Maximum currently available",1,true)and message.TextFits,"Rejection toast clipped")
   results.Rejections+=1
  end
  session.TestReject=false
  for _,name in ipairs({"BuyLong","SellShort"})do
   session.Positions={};session.SummaryData.Count=0;session.Changed:Fire();task.wait(.07);sample()
   get(name).TestFeedback:Invoke("Down");get(name).TestActivate:Invoke()
   local start=os.clock();repeat task.wait();sample()until os.clock()-start>.32
   assert(session.Positions.BT,"Successful fixture reply missing");results.Successes+=1
  end
  session.Positions={};session.SummaryData.Count=0;session.Changed:Fire();task.wait(.08)
  for _,value in ipairs({125.5,-93.25,0,201.75,-1.25})do
   session.SummaryData.Unrealized=value;session.SummaryData.Equity=5000+value
   session.Changed:Fire();task.wait(.08)
   local label=get("UnrealizedValue")
   assert(label.Text==Market.Signed(value),"P&L value froze")
   local expected=value<0 and Color3.fromRGB(255,76,122)or nil
   local icon=get("UnrealizedCard"):FindFirstChild("IconPanel")
   if icon then assert(icon.Rotation==0,"P&L arrow flipped")end
   if value>0 then results.PositiveColor=tostring(label.TextColor3)elseif value<0 then results.NegativeColor=tostring(label.TextColor3)end
   results.PnlUpdates+=1
  end
  assert(results.PositiveColor~=results.NegativeColor,"P&L colors froze")
  for _,key in ipairs(Market.ContractOrder)do
   s.Contract=key;controller:TestRender();task.wait(.05)
   assert(not controller.Root:FindFirstChild("BidAsk",true),"Bid/ask readout remains")
   assert(session.Quotes[key].Bid and session.Quotes[key].Ask and session.Quotes[key].Spread,"Execution quotes removed")
   for _,b in ipairs(controller.Root.Canvas:GetDescendants())do
    if b.Name=="ContractSelector"then
     local label=b.ControlLabel;local chevron=assert(b:FindFirstChild("Chevron"))
     assert(label.Text:sub(1,#key)==key and label.TextFits,"Ticker text clipped "..key)
     assert(label.TextXAlignment==Enum.TextXAlignment.Left and label.Position.X.Offset==12)
     assert(label.AbsolutePosition.X+label.AbsoluteSize.X+4<=chevron.AbsolutePosition.X,"Ticker and chevron overlap")
     assert(chevron.AbsolutePosition.X+chevron.AbsoluteSize.X<b.AbsolutePosition.X+b.AbsoluteSize.X,"Chevron clipped")
     assert(chevron.Left.Rotation>0 and chevron.Right.Rotation<0,"Chevron not downward")
     assert(b:IsA("TextButton") and b.Active,"Selector is not a full clickable button")
     results.Selectors+=1
    end
   end
   get("ContractSelector").TestActivate:Invoke();assert(s.Overlay=="Contracts","Selector not clickable");s.Overlay=nil;controller:TestRender()
  end
  table.insert(results.Layouts,{Width=size[1],Height=size[2],Passed=true})
  controller:Destroy();controller=nil;host:Destroy()
 end
end)
if controller then controller:Destroy()end
gui:Destroy();shared:Destroy()
assert(ok,err);return game:GetService("HttpService"):JSONEncode(results)
