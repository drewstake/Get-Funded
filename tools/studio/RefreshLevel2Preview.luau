-- Update the existing, static edit-time GUI without saving the place or changing its data.
-- The real client constructs the complete responsive UI from TerminalUI at runtime.
local root=game.StarterGui.MarketReign.Workspace
local canvas=root.Canvas;local ticket=canvas.OrderTicket;local sc=ticket.Fields
local previous=sc:FindFirstChild("Level2");if previous then previous:Destroy()end
for _,name in ipairs({"Risk","NoPosition"})do local o=ticket:FindFirstChild(name,true);if o then o:Destroy()end end
local activity=canvas:FindFirstChild("Activity")
if activity then for _,name in ipairs({"EmptyTitle","EmptyDetail","IconPositions"})do local o=activity:FindFirstChild(name);if o then o:Destroy()end end end
local actions=ticket.OrderActions;actions.Position=UDim2.fromOffset(0,ticket.Size.Y.Offset-108);actions.Size=UDim2.fromOffset(ticket.Size.X.Offset,108)
for _,o in ipairs(actions:GetChildren())do if o:IsA("Frame")and o.Name~="BuyLong"and o.Name~="SellShort"then o:Destroy()end end
sc.Size=UDim2.fromOffset(ticket.Size.X.Offset,ticket.Size.Y.Offset-86-108)
local template=sc.OrderType.Market
local function button(parent,name,value,x,y,w,h,fn,_,_,size,z)
 local b=template:Clone();b.Name=name;b.Parent=parent;b.Position=UDim2.fromOffset(x,y);b.Size=UDim2.fromOffset(w,h);b.ZIndex=z or parent.ZIndex+1
 b.AnchorPoint=Vector2.zero;b.Text=value;b.TextSize=size or 16
 for _,o in ipairs(b:GetChildren())do if not(o:IsA("UICorner")or o:IsA("UIStroke"))then o:Destroy()end end
 b.Activated:Connect(fn);return b
end
local function gloss(b,variant)
 b.TextTransparency=0;b.BackgroundColor3=Color3.new(1,1,1);b.Font=Enum.Font.FredokaOne;b.TextColor3=Color3.fromRGB(245,249,255)
 local g=Instance.new("UIGradient");g.Rotation=90;g.Color=variant=="Cyan"and ColorSequence.new(Color3.fromRGB(0,192,255),Color3.fromRGB(0,94,228))or ColorSequence.new(Color3.fromRGB(15,48,117),Color3.fromRGB(3,24,66));g.Parent=b
 return b
end
local expanded=true;local y=sc.TargetCard.Position.Y.Offset+sc.TargetCard.Size.Y.Offset+6
-- This presentation module has no module dependencies; run it with the caller's capabilities.
local view=assert(loadstring(game.ReplicatedStorage.MarketReign.Level2View.Source))()
view.new({button=button,gloss=gloss,number=function(v)return string.format("%.2f",v)end,quantity=tostring,
 expanded=function()return expanded end,toggle=function()expanded=not expanded end,
 data=function()return {Allowed=false,State="Locked",PassId=2006894567}end,openShop=function()end,
 resize=function(h)sc.CanvasSize=UDim2.fromOffset(0,y+h+10)end},sc,16,y,ticket.Size.X.Offset-32)
return {Level2=true,Locked=true,Preview=true,Saved=false}
