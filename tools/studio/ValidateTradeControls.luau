-- Isolated Studio Edit validation. No remote orders or saved portfolio changes.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="TradeControlsValidation";shared.Parent=game.ReplicatedStorage
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
local gui=Instance.new("ScreenGui");gui.Name="TradeControlsValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local results={Interactions={},Layouts={}}
local controllers={}
local ok,err=pcall(function()
 local Market=require(shared.MarketClient);local UI=require(shared.TerminalUI)
 local host=Instance.new("Frame");host.Size=UDim2.fromOffset(1440,900);host.Parent=gui
 local controller=UI.Mount(host);table.insert(controllers,controller)
 local s=controller.State;local session=Market.TestSession;s.Screen="Trade"
 local function redraw()
  host.Size=UDim2.fromOffset(1436,900);task.wait(.06);host.Size=UDim2.fromOffset(1440,900);task.wait(.06)
  controller:TestRender();task.wait(.03)
 end
 redraw()
 local function get(path)
  local node=controller.Root.Canvas
  for part in path:gmatch("[^.]+")do node=assert(node:FindFirstChild(part),"Missing "..path)end
  return node
 end
 local function click(path)get(path).TestActivate:Invoke();task.wait(.07);controller:TestRender();task.wait(.03)end
 local function enter(path,value)
  local stepper=get(path);stepper.Value.Text=tostring(value)
  return stepper.TestCommit:Invoke()
 end
 local function check(name,condition)assert(condition,name);table.insert(results.Interactions,name)end
 click("OrderTicket.Fields.OrderType.Limit")
 check("Limit tab changes type and button label",s.Type=="Limit"and get("OrderTicket.OrderActions.BuyLong.ActionLabel").Text=="↑ LIMIT BUY")
 for _,key in ipairs(Market.ContractOrder)do
  s.Contract=key;s.Limit=Market.Contracts[key].Last;redraw()
  local before=s.Limit;click("OrderTicket.Fields.LimitPrice.Increase")
  check(key.." price increases one tick",math.abs(s.Limit-before-Market.Contracts[key].Tick)<.00001)
  click("OrderTicket.Fields.LimitPrice.Decrease")
  check(key.." price decreases one tick",math.abs(s.Limit-before)<.00001)
  session.Prices[key]=before+3*Market.Contracts[key].Tick
  session.Changed:Fire();task.wait(.07)
  check(key.." current quote updates",get("OrderTicket.Fields.CurrentPrice").Text=="Current "..Market.Number(session.Prices[key]))
  click("OrderTicket.Fields.UseCurrent")
  check(key.." use current snaps to tick",s.Limit==Market.Snap(session.Prices[key],key))
 end
 s.Contract="BX";redraw()
 check("Limit input accepts formatted price",enter("OrderTicket.Fields.LimitPrice","$5,812.38")and s.Limit==5812.5)
 check("Limit input rejects negative price",not enter("OrderTicket.Fields.LimitPrice","-4")and s.Limit==5812.5)
 check("Quantity rejects fractional input",not enter("OrderTicket.Fields.Quantity","2.5")and s.Qty==1)
 enter("OrderTicket.Fields.Quantity",5);click("OrderTicket.Fields.Quantity.Increase")
 check("Quantity upper bound",s.Qty==5)
 s.Overlay=nil;redraw()
 enter("OrderTicket.Fields.Quantity",1);click("OrderTicket.Fields.Quantity.Decrease")
 check("Quantity lower bound",s.Qty==1)
 enter("OrderTicket.Fields.Quantity",3);click("OrderTicket.Fields.Quantity.Increase")
 check("Quantity commits text before stepping",s.Qty==4)
 enter("OrderTicket.Fields.StopCard.Distance",500.01)
 check("Inline stop direct entry",math.abs(s.StopDollars-500.01)<.000001)
 enter("OrderTicket.Fields.TargetCard.Distance",1499.99)
 check("Inline target direct entry",math.abs(s.TargetDollars-1499.99)<.000001)
 check("Risk reflects quantity and stop",get("OrderTicket.OrderActions.Risk").Text=="Estimated total loss  $500.00")
 click("OrderTicket.Fields.StopCard.Toggle")
 check("Stop toggle disables its input",not s.StopOn and not get("OrderTicket.Fields.StopCard.Distance.Value").TextEditable)
 click("OrderTicket.Fields.StopCard.Toggle")
 click("OrderTicket.Fields.StopCard.Settings")
 enter("ProtectionDialog.Fields.StopProtection.Distance",s.ProtectionDraft.StopDollars+.01)
 click("ProtectionDialog.Fields.TargetProtection.Toggle")
 check("Popup edits remain draft",math.abs(s.StopDollars-500.01)<.000001 and s.TargetOn and math.abs(s.ProtectionDraft.StopDollars-500.02)<.000001 and not s.ProtectionDraft.TargetOn)
 click("ProtectionDialog.Dismiss")
 check("Closing applies draft",s.Overlay==nil and s.ProtectionDraft==nil and math.abs(s.StopDollars-500.02)<.000001 and not s.TargetOn)
 click("OrderTicket.Fields.StopCard.Settings")
 enter("ProtectionDialog.Fields.StopProtection.Distance",100000001)
 check("Protection rejects values above server cap",math.abs(s.ProtectionDraft.StopDollars-500.02)<.000001)
 enter("ProtectionDialog.Fields.StopProtection.Distance",48)
 click("OverlayBackdrop")
 check("Backdrop saves draft",s.ProtectionDraft==nil and s.StopDollars==48)
 enter("OrderTicket.Fields.Quantity",1)
 check("Dollar maximum tracks typed quantity decrease",not enter("OrderTicket.Fields.StopCard.Distance",200000))
 enter("OrderTicket.Fields.Quantity",4)
 check("Dollar maximum tracks typed quantity increase",enter("OrderTicket.Fields.StopCard.Distance",200000))
 enter("OrderTicket.Fields.StopCard.Distance",500.02)
 click("OrderTicket.OrderActions.BuyLong")
 local req=session.TestLog[#session.TestLog]
 check("Limit buy submits configured order",req.Action=="Place"and req.Direction==1 and req.Type=="Limit"and req.Price==5812.5 and req.Quantity==4 and math.abs(req.StopDollars-500.02)<.000001 and req.TargetDollars==nil)
 click("OrderTicket.OrderActions.SellShort")
 req=session.TestLog[#session.TestLog]
 check("Limit sell submits direction",req.Type=="Limit"and req.Direction==-1)
 click("OrderTicket.Fields.OrderType.Market")
 click("OrderTicket.OrderActions.BuyLong")
 req=session.TestLog[#session.TestLog]
 check("Market buy submits without limit",req.Type=="Market"and req.Price==nil and req.Direction==1)
 redraw()
 local position=session.Positions.BX;local stop=position.Stop;local requests=#session.TestLog
 click("OrderTicket.Fields.StopCard.Settings")
 enter("ProtectionDialog.Fields.StopProtection.Distance",s.ProtectionDraft.StopDollars+.01)
 click("ProtectionDialog.Dismiss")
 check("Saved defaults do not amend open positions",#session.TestLog==requests+1 and session.TestLog[#session.TestLog].Action=="ProtectionPreferences"and position.Stop==stop)
 click("OrderTicket.OrderActions.SellShort")
 req=session.TestLog[#session.TestLog]
 check("Market sell uses updated defaults",req.Type=="Market"and req.Direction==-1 and math.abs(req.StopDollars-500.03)<.000001)
 controller:Destroy();host:Destroy()
 for _,size in ipairs({{320,568},{390,844},{844,390},{1000,600},{1280,720},{1440,900},{1920,1080}})do
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  local ctl=UI.Mount(host);table.insert(controllers,ctl);ctl.State.Screen="Trade"
  local function layoutRefresh()
   host.Size=UDim2.fromOffset(size[1]-4,size[2]);task.wait(.06)
   host.Size=UDim2.fromOffset(size[1],size[2]);task.wait(.12);ctl:TestRender();task.wait(.08)
  end
  for _,mode in ipairs({"Market","MarketPosition","Limit","Protection"})do
   ctl.State.Type=(mode=="Market"or mode=="MarketPosition")and"Market"or"Limit"
   Market.TestSession.Positions=mode=="MarketPosition"and{BX={Id=1,Contract="BX",Direction=1,Quantity=100,Entry=Market.TestSession.Prices.BX}}or{}
   ctl.State.Sheet=size[1]<1000 or size[2]<600
   ctl.State.Overlay=mode=="Protection"and"Protection"or nil
   if mode=="Protection"then ctl.State.Sheet=false;ctl.State.ProtectionDraft={StopOn=true,TargetOn=true,StopDollars=10000,TargetDollars=10000}end
   layoutRefresh()
   local c=ctl.Root.Canvas
   local panel=mode=="Protection"and c:FindFirstChild("ProtectionDialog")or c:FindFirstChild("OrderTicket")or c:FindFirstChild("OptionsSheet")
   assert(panel,string.format("Missing panel %dx%d %s (screen %s, overlay %s, error %s)",size[1],size[2],mode,tostring(ctl.State.Screen),tostring(ctl.State.Overlay),tostring(ctl.Root:GetAttribute("RenderError"))))
   local issues={}
   local pos=panel.AbsolutePosition-host.AbsolutePosition
   -- The rounded sheet background deliberately overscans 20px below the viewport;
   -- its interactive scroll area must still end exactly inside the visible screen.
   local visibleHeight=panel.AbsoluteSize.Y-(panel.Name=="OptionsSheet" and 20 or 0)
   assert(pos.X>=0 and pos.Y>=0 and pos.X+panel.AbsoluteSize.X<=size[1]+1 and pos.Y+visibleHeight<=size[2]+1,string.format("Panel outside screen %dx%d %s: x %.2f y %.2f w %.2f h %.2f",size[1],size[2],mode,pos.X,pos.Y,panel.AbsoluteSize.X,panel.AbsoluteSize.Y))
   if panel.Name=="OptionsSheet" then assert(pos.Y+panel.Fields.Position.Y.Offset+panel.Fields.Size.Y.Offset<=size[2]+1,"Sheet controls outside screen") end
   for _,o in ipairs(panel:GetDescendants())do
    if o:IsA("TextLabel")and not o.TextFits and o.TextTruncate==Enum.TextTruncate.None then table.insert(issues,"Text overflow: "..o:GetFullName().." / "..o.Text)end
    if o:IsA("GuiObject")and(o.Size.X.Offset<0 or o.Size.Y.Offset<0)then table.insert(issues,"Negative bounds: "..o.Name)end
   end
   if mode=="Protection"then
    assert(not panel.Actions:FindFirstChild("SaveSettings")and not panel.Actions:FindFirstChild("Cancel"),"Popup still requires explicit save/cancel")
    assert(panel.Dismiss.Size.Y.Offset>=40,"Close target too small")
    assert(panel.Actions.Position.Y.Offset>=panel.Fields.Position.Y.Offset+panel.Fields.Size.Y.Offset,"Popup actions overlap fields")
    assert(panel.Actions.Position.Y.Offset+panel.Actions.Size.Y.Offset<=panel.Size.Y.Offset,"Popup actions clipped")
   elseif panel:FindFirstChild("OrderActions")then
    local actions=panel.OrderActions
    assert(actions.Size.Y.Offset==132,"Ticket reserves unused footer space")
    assert(actions.Position.Y.Offset>=panel.Fields.Position.Y.Offset+panel.Fields.Size.Y.Offset,"Ticket actions overlap fields")
    assert(not actions:FindFirstChild("Simulation"),"Disclaimer footer retained")
    if size[1]>=1920 and(mode=="Market"or mode=="MarketPosition")then
     assert(panel.Fields.CanvasSize.Y.Offset<=panel.Fields.AbsoluteSize.Y,"Desktop market ticket scrolls unnecessarily")
    end
    if actions:FindFirstChild("ClosePosition")then
     local details=actions:FindFirstChild("Position")
     assert(details.Position.X.Offset+details.Size.X.Offset<=actions.ClosePosition.Position.X.Offset,"Position details overlap Close")
     assert(actions.Pnl.Position.Y.Offset+actions.Pnl.Size.Y.Offset<=actions.Size.Y.Offset,"P&L overlaps footer")
    end
   end
   table.insert(results.Layouts,{Width=size[1],Height=size[2],Mode=mode,Issues=issues})
  end
  ctl:Destroy();host:Destroy()
 end
end)
for _,controller in ipairs(controllers)do if controller.Root.Parent then controller:Destroy()end end
gui:Destroy();shared:Destroy();assert(ok,err);return results
