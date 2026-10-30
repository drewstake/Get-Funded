-- Run in Studio CLIENT context during Play. Isolated UI interaction fixture; no remote orders.
-- Call PlayerGui.AfterHoursUITest.Diagnostics:Invoke("Cleanup") before finishing.
assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsClient(),"Studio client only")
local playerGui=game.Players.LocalPlayer.PlayerGui
assert(not playerGui:FindFirstChild("AfterHoursUITest"),"Clean up the previous fixture first")
local live=playerGui.MarketReign
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="AfterHoursUITestShared";shared.Parent=game.ReplicatedStorage
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
  if action=="Place"then
   local c=Config.Contracts[req.Contract]
   if req.Type=="Limit"then
    table.insert(self.Orders,{Id=self.NextId,Contract=req.Contract,Kind="Limit",Quantity=req.Quantity,Price=req.Price,Status="Working"})
   else
    self.Positions[req.Contract]={Id=self.NextId,Contract=req.Contract,Direction=req.Direction,Quantity=req.Quantity,Entry=c.Last,Unrealized=25,
     Stop=req.StopTicks and c.Last-req.Direction*req.StopTicks*c.Tick,Target=req.TargetTicks and c.Last+req.Direction*req.TargetTicks*c.Tick}
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
local gui=Instance.new("ScreenGui");gui.Name="AfterHoursUITest";gui.DisplayOrder=100;gui.ResetOnSpawn=false;gui.Parent=playerGui
local controller=require(shared.TerminalUI).Mount(gui)
controller.Root.Size=UDim2.fromOffset(1440,900)
local market=require(shared.MarketClient)
local diagnostic=Instance.new("BindableFunction");diagnostic.Name="Diagnostics";diagnostic.Parent=gui
diagnostic.OnInvoke=function(command,a,b)
 if command=="Resize"then controller.Root.Size=UDim2.fromOffset(a,b);return true end
 if command=="Cleanup"then controller:Destroy();gui:Destroy();shared:Destroy();live.Enabled=true;return true end
 if command=="State"then
  return {UI=controller.State,Attributes=controller.Root:GetAttributes(),Requests=market.TestSession.TestLog,
   Positions=market.TestSession.Positions,Orders=market.TestSession.Orders,Summary=market.TestSession:Summary()}
 end
 if command=="Connectivity"then market.TestSession.CanTrade=a;market.TestSession.Changed:Fire();return true end
 if command=="Portfolio"then market.TestSession.Portfolio=market.FixturePortfolio(a);controller.State.Screen=b;market.TestSession.Changed:Fire();return true end
 if command=="Event"then market.TestSession.Events:Fire(a);return true end
 error("Unknown fixture command")
end
live.Enabled=false
return {Gui=gui:GetFullName(),Diagnostics=diagnostic:GetFullName(),Notice="Isolated fixture. No remote requests or saved-account mutations."}
