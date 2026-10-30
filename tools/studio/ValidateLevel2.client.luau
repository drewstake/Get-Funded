-- Temporary client harness: real engine snapshots, isolated order requests, no purchases.
local H=game:GetService("HttpService");local Run=game:GetService("RunService")
local shared=game.ReplicatedStorage.MarketReign;local pg=game.Players.LocalPlayer:WaitForChild("PlayerGui")
local report={Checks={},Layouts={},TextIssues={}}
local gui=Instance.new("ScreenGui");gui.Name="Level2Verification";gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets;gui.DisplayOrder=90;gui.Parent=pg
local controller,session
local function check(name,value)assert(value,name);table.insert(report.Checks,name)end
local ok,err=xpcall(function()
 assert(shared:WaitForChild("Level2FixtureSnapshot",60),"Server fixture did not arrive")
 controller=require(shared.Level2FixtureUI).Mount(gui)
 local root=controller.Root;local state=controller.State;session=require(shared.Level2FixtureClient).TestSession
 state.Screen="Trade";state.CoachDismissed=true
 local function render()controller:TestRender();task.wait(.12)end
 local function ticket()return root.Canvas:FindFirstChild("OrderTicket")or root.Canvas:FindFirstChild("TradeDock")end
 local function depth()return ticket().Fields.Level2 end
 local function click(b)b.TestActivate:Invoke();task.wait(.08)end
 local function live()session.DepthAccess={Allowed=true,State="Owned"};session.DepthLive=true;session.DepthReceivedAt=os.clock();session.DepthContract=state.Contract;session.Quotes=session.TestSnapshots.First.Quotes end
 for _,size in ipairs({{320,568},{390,844},{874,402},{749,303},{667,317},{667,375},{1024,600},{1280,720},{1440,900},{1920,1080}})do
  root.Size=UDim2.fromOffset(size[1],size[2]);state.Level2Expanded=true;live();render()
  local t=ticket();local sc=t.Fields;local d=depth();local buy=t:FindFirstChild("BuyLong",true);local sell=t:FindFirstChild("SellShort",true)
  check("Trade panel contains L2 "..size[1],d.Parent==sc and sc:IsA("ScrollingFrame"))
  local target=sc:FindFirstChild("TargetCard");assert(target,"Take profit missing")
  check("L2 follows take profit "..size[1],d.AbsolutePosition.Y>=target.AbsolutePosition.Y+target.AbsoluteSize.Y)
  check("Pinned actions stay outside scrolling fields "..size[1],not buy:IsDescendantOf(sc)and not sell:IsDescendantOf(sc))
  for _,b in ipairs({buy,sell})do
   local p=b.AbsolutePosition-root.AbsolutePosition;local s=b.AbsoluteSize
   check("Reachable "..b.Name.." "..size[1],p.X>=0 and p.Y>=0 and p.X+s.X<=size[1]+1 and p.Y+s.Y<=size[2]+1 and s.Y>=44)
  end
  check("Fields scroll instead of scaling "..size[1],sc.Size.Y.Offset>0 and sc.CanvasSize.Y.Offset>=d.Position.Y.Offset+d.Size.Y.Offset)
  check("Removed helper text "..size[1],not t:FindFirstChild("Risk",true)and not t:FindFirstChild("NoPosition",true)and not root.Canvas:FindFirstChild("EmptyDetail",true))
  local activity=root.Canvas:FindFirstChild("Activity")
  if activity then check("Open position tab and count remain "..size[1],activity:FindFirstChild("TabPositions")~=nil and not activity:FindFirstChild("EmptyTitle"))end
  for _,label in ipairs(d:GetDescendants())do
   if label:IsA("TextLabel")and label.Visible and label.Text~=""and not label.TextFits then table.insert(report.TextIssues,size[1].."x"..size[2].." "..label.Name.." "..label.Text)end
  end
  local original=sc.Quantity.Value;local originalBuy=buy;local beforeHeight=d.Size.Y.Offset
  click(d.ToggleLevel2)
  check("Collapse preserves form and actions "..size[1],depth()==d and sc.Quantity.Value==original and buy==originalBuy and d.Size.Y.Offset==40)
  click(d.ToggleLevel2);check("Expand restores book "..size[1],d.Size.Y.Offset==beforeHeight)
  table.insert(report.Layouts,{Width=size[1],Height=size[2],FieldsHeight=sc.Size.Y.Offset,ContentHeight=sc.CanvasSize.Y.Offset,DepthHeight=d.Size.Y.Offset})
 end
 root.Size=UDim2.fromOffset(1440,900);state.Type="Limit";state.Qty=2;state.Limit=5800.25;state.StopDollars=123.45;state.TargetDollars=234.56;live();render()
 local sc=ticket().Fields;local d=depth();local field=sc.LimitPrice.Value;local firstRow=d.Body:FindFirstChild("Asks1")
 field:CaptureFocus();field.Text="5,812.75"
 session.Quotes=session.TestSnapshots.Second.Quotes;session.DepthReceivedAt=os.clock();controller:TestDepth();task.wait(.25)
 check("Depth updates preserve focused input and unfinished text",field:IsFocused()and field.Text=="5,812.75"and ticket().Fields.LimitPrice.Value==field)
 check("Depth updates reuse existing rows",firstRow==d.Body:FindFirstChild("Asks1"))
 field:ReleaseFocus();task.wait(.12)
 local q=session.Quotes.BX.Depth;local maximum=0;for _,side in ipairs({q.Asks,q.Bids})do for _,l in ipairs(side)do maximum=math.max(maximum,l.Quantity)end end
 local count=0
 for _,o in ipairs(d.Body:GetChildren())do
  if o:IsA("Frame")and o.Visible and o:GetAttribute("Price")then
   count+=1;local side=o.Name:find("Asks")and q.Asks or q.Bids;local found=false
   for _,l in ipairs(side)do if l.Price==o:GetAttribute("Price")and l.Quantity==o:GetAttribute("Quantity")then found=true end end
   check("Rendered level comes from engine "..o.Name,found)
   local scale=tonumber(d.ToggleLevel2.Scale.Text:match("%d+"))
   check("Bar is proportional on a stable labelled scale "..o.Name,scale>=maximum and math.abs(o.Liquidity.Size.X.Scale-o:GetAttribute("Quantity")/scale)<.0001)
  end
 end
 check("No padded price levels",count==#q.Asks+#q.Bids)
 local original=session.Quotes.BX.Depth
 local fixedHeight=d.Size.Y.Offset;local fixedSpread=d.Body.Spread.Position;local fixedBid=d.Body.Bids1.Position;local fixedAsk=d.Body.Asks1.Position
 local scale=d.ToggleLevel2.Scale.Text;sc.CanvasPosition=Vector2.new(0,100);local scroll=sc.CanvasPosition
 check("Source labels removed",not d.Body:FindFirstChild("LiquiditySource"))
 for _,item in ipairs({{Name="empty",Depth={Bids={},Asks={}}},{Name="missing ask",Depth={Bids=original.Bids}},
  {Name="empty bid",Depth={Asks=original.Asks,Bids={}}},{Name="missing depth"}})do
  session.Quotes.BX.Depth=item.Depth;controller:TestDepth()
  check("Data availability never changes height or row anchors "..item.Name,d.Size.Y.Offset==fixedHeight and d.Body.Spread.Position==fixedSpread and d.Body.Bids1.Position==fixedBid and d.Body.Asks1.Position==fixedAsk)
  check("Data changes preserve scroll "..item.Name,sc.CanvasPosition==scroll)
  check("Removing quantity never rescales other bars "..item.Name,d.ToggleLevel2.Scale.Text==scale)
  if item.Name=="empty"then check("Empty sides are explicit",d.Body.EmptyAsks.Text=="No resting asks"and d.Body.EmptyBids.Text=="No resting bids"and d.Body.Spread.Text=="Spread unavailable")
  elseif item.Name=="missing ask"then check("Missing side differs from empty",d.Body.EmptyAsks.Text=="Asks unavailable")
  elseif item.Name=="missing depth"then check("Missing book is explicit",d.Body.Status.Text=="Market depth unavailable")
  else check("One empty side has no fabricated spread",d.Body.EmptyBids.Text=="No resting bids"and d.Body.Spread.Text=="Spread unavailable")end
 end
 session.Quotes.BX.Depth=original;session.DepthContract="BT";controller:TestDepth();check("Contract switch clears old depth",d.Body.Status.Text=="Loading market depth…")
 session.DepthContract="BX";session.DepthReceivedAt=os.clock()-20;controller:TestDepth();check("Stale depth is cleared",d.Body.Status.Text=="Depth paused · reconnecting…")
 for _,side in ipairs({"Asks","Bids"})do for i=1,5 do check("Stale row is hidden "..side..i,not d.Body[side..i].Visible)end end
 session.DepthReceivedAt=os.clock();session.DepthAccess={Allowed=false,State="Checking"};controller:TestDepth();check("Checking access state",d.Body.Status.Text=="Checking L2 access…"and not d.Body.UnlockL2.Visible)
 session.DepthAccess={Allowed=false,State="Unconfigured"};controller:TestDepth()
 check("Locked transition keeps the expanded footprint",d.Size.Y.Offset==fixedHeight)
 check("Locked view hides book",d.Body.UnlockL2.Visible and not d.Body.Spread.Visible and not d.Body.Columns.Visible)
 local saved={Qty=state.Qty,Limit=state.Limit,Stop=state.StopDollars,Target=state.TargetDollars,Type=state.Type}
 click(d.Body.UnlockL2)
 check("Unlock opens existing Shop",root.Canvas:FindFirstChild("ShopDialog")~=nil)
 check("Shop preserves entered order values",state.Qty==saved.Qty and state.Limit==saved.Limit and state.StopDollars==saved.Stop and state.TargetDollars==saved.Target and state.Type==saved.Type)
 click(root.Canvas.ShopDialog.CloseShop)
 -- Own-order changes rebuild other panels while retaining the complete trade ticket.
 local t=ticket();local fields=t.Fields;local buy=t:FindFirstChild("BuyLong",true);local savedDepth=depth()
 assert(session:SetProtectionPreferences(state)) -- model the locally committed ticket preferences
 fields.CanvasPosition=Vector2.new(0,100);local savedScroll=fields.CanvasPosition
 session.Orders={{Id=991,Contract=state.Contract,Quantity=2,Kind="Limit Buy",Price=state.Limit,Status="Working",Direction=1}}
 session.Changed:Fire();task.wait(.25)
 check("Market structure changes preserve trade panel, fields, depth and Buy",ticket()==t and ticket().Fields==fields and depth()==savedDepth and ticket():FindFirstChild("BuyLong",true)==buy)
 check("Own-order updates preserve scrolling",fields.CanvasPosition==savedScroll)
 session.Orders={}
 state.PendingOrder=nil;state.Type="Limit";render();click(ticket().OrderActions.BuyLong)
 local req=session.TestRequests[#session.TestRequests]
 check("Buy retains order request values",req.Action=="Place"and req.Direction==1 and req.Quantity==saved.Qty and req.Price==saved.Limit and req.StopDollars==saved.Stop and req.TargetDollars==saved.Target)
 state.PendingOrder=nil;render();click(ticket().OrderActions.SellShort);req=session.TestRequests[#session.TestRequests]
 check("Sell retains order request values",req.Action=="Place"and req.Direction==-1 and req.Quantity==saved.Qty and req.Price==saved.Limit)
 -- Leave the isolated book available for screenshot review; the harness is removed afterwards.
 state.PendingOrder=nil;state.Type="Market";state.Tab="Positions";state.Qty=1;state.Level2Expanded=true;live();root.Size=UDim2.fromScale(1,1);render()
 -- Keep a static, explicitly isolated engine snapshot on screen during visual review.
 Run.Heartbeat:Connect(function()if gui.Parent then session.DepthReceivedAt=os.clock()end end)
 local preview=Instance.new("BindableFunction");preview.Name="Level2PreviewControl";preview.Parent=gui
 preview.OnInvoke=function(command)
  if command=="Locked"then session.DepthAccess={Allowed=false,State="Unconfigured"}
  elseif command=="Live"then live()
  elseif command=="Collapse"then state.Level2Expanded=false
  elseif command=="Expand"then state.Level2Expanded=true end
  render();local t=ticket();local sc=t.Fields;sc.CanvasPosition=Vector2.new(0,math.max(0,sc.CanvasSize.Y.Offset-sc.AbsoluteSize.Y));return true
 end
end,debug.traceback)
report.Ok=ok;report.Error=not ok and tostring(err)or nil
local result=Instance.new("StringValue");result.Name="Level2ClientResult";result.Value=H:JSONEncode(report);result.Parent=pg
print("LEVEL2_CLIENT "..result.Value)
