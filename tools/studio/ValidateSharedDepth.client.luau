-- Actual client-side observations of the disposable network fixture.
local Players=game:GetService("Players");local player=Players.LocalPlayer
local folder=game.ReplicatedStorage:WaitForChild("SharedDepthNetworkFixture",30);if not folder then return end
local command=folder:WaitForChild("Command");local update=folder:WaitForChild("Update")
local View=require(game.ReplicatedStorage.MarketReign.Level2View)
local gui=Instance.new("ScreenGui");gui.Name="SharedDepthClientVerification";gui.DisplayOrder=100;gui.Parent=player.PlayerGui
local panel=Instance.new("Frame");panel.Size=UDim2.fromOffset(340,430);panel.Position=UDim2.fromOffset(20,20);panel.Parent=gui
local caption=Instance.new("TextLabel");caption.Text="Isolated multiplayer verification";caption.Size=UDim2.fromOffset(340,40);caption.Parent=panel
local function button(p,name,text,x,y,w,h,fn,bg,fg,size,z)
 local b=Instance.new("TextButton");b.Name=name;b.Text=text;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.BackgroundColor3=bg;b.TextColor3=fg;b.TextSize=size;b.ZIndex=z or 1;b.Parent=p;b.Activated:Connect(fn);return b
end
local function gloss(b)local edge=Instance.new("UIStroke");edge.Name="Border";edge.Parent=b;return b end
local packet;local expanded=true
local view=View.new({button=button,gloss=gloss,number=function(v)return string.format("%.2f",v)end,quantity=tostring,
 expanded=function()return expanded end,toggle=function()expanded=not expanded end,openShop=function()end,
 data=function()return packet and packet.DepthAccess,packet and packet.Quotes.BX,packet~=nil end},panel,10,48,320)
local expected={empty=false,placed={Ask=5825,Qty=3},partial_fill={Ask=5825,Qty=2},foreign_cancel_rejected={Ask=5825,Qty=2},
 cancelled=false,reposted={Ask=5825.25,Qty=2},fully_filled=false,before_disconnect={Bid=5824,Qty=4},after_disconnect=false}
local original=view.Root;local height=view.Height;local bidY=view.Rows.Bids[1].Root.Position;local askY=view.Rows.Asks[1].Root.Position
update.OnClientEvent:Connect(function(message)
 if message.Action then
  if message.Action=="Leave"then game:GetService("StudioTestService"):LeaveTest()
  else command:FireServer(message.Action)end
  return
 end
 local report={Phase=message.Phase}
 local ok,err=xpcall(function()
  packet=message.Packet;view:Update()
  assert(view.Root==original and view.Height==height,"Depth panel moved or was rebuilt")
  assert(view.Rows.Bids[1].Root.Position==bidY and view.Rows.Asks[1].Root.Position==askY,"Row anchors moved")
  local role=player:GetAttribute("DepthTestRole");local depth=packet.Quotes.BX.Depth
  if role~=2 then
   assert(packet.DepthAccess.Allowed==false and depth==nil,"Premium depth leaked to an unauthorized client")
   assert(not view.Columns.Visible and not view.Rows.Asks[1].Root.Visible and not view.Rows.Bids[1].Root.Visible)
   report.Locked=true
  else
   assert(packet.DepthAccess.Allowed and type(depth)=="table","Verified fixture viewer did not receive depth")
   local target=expected[message.Phase]
   if target then
    local side=target.Ask and "Asks"or "Bids";local price=target.Ask or target.Bid
    assert(#depth[side]==1 and depth[side][1].Quantity==target.Qty and depth[side][1].Price==price,"Incorrect received depth")
    local row=view.Rows[side][1].Root
    assert(row.Visible and row:GetAttribute("Price")==price and row:GetAttribute("Quantity")==target.Qty,"Rendered depth differs from the packet")
    report.Price=price;report.Quantity=target.Qty
   else assert(#depth.Bids==0 and #depth.Asks==0,"Removed liquidity is still visible")end
  end
 end,debug.traceback)
 report.Ok=ok;report.Error=not ok and err or nil;command:FireServer("Ack",report)
end)
