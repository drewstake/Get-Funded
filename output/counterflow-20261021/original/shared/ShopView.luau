-- Shop presentation. Purchase prompts never grant access; the server verifies ownership.
-- ImageGen originals and prompts are kept in icons/shop. All copy and controls are native UI.
local TextService=game:GetService("TextService")
local View={}
local Art={Depth="rbxassetid://90643097876584",VIP="rbxassetid://131970148250145",Themes="rbxassetid://109496208973919",
 Happy="rbxassetid://115617570278067",Sad="rbxassetid://128402867973425"}
local C={Navy=Color3.fromRGB(3,22,64),Blue=Color3.fromRGB(8,48,126),Cyan=Color3.fromRGB(0,220,255),
 Text=Color3.fromRGB(245,249,255),Muted=Color3.fromRGB(184,220,255),Purple=Color3.fromRGB(178,113,255)}
local F=Enum.Font.FredokaOne
local function make(class,name,parent,props)
 local o=Instance.new(class);o.Name=name
 for k,v in pairs(props)do o[k]=v end
 o.Parent=parent;return o
end
local function frame(p,name,x,y,w,h,z)
 return make("Frame",name,p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,ZIndex=z or p.ZIndex+1})
end
local function surface(p,edge,top,bottom,radius)
 make("UICorner","Corners",p,{CornerRadius=UDim.new(0,radius or 16)})
 make("UIStroke","Border",p,{Color=edge or C.Cyan,Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
 make("UIGradient","SurfaceLight",p,{Rotation=90,Color=ColorSequence.new(top or C.Blue,bottom or C.Navy)})
end
local function label(p,name,value,x,y,w,h,size,color,center)
 return make("TextLabel",name,p,{Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,BorderSizePixel=0,
  Font=F,TextSize=size,TextColor3=color or C.Text,TextStrokeColor3=Color3.fromRGB(1,15,49),TextStrokeTransparency=.55,
  TextXAlignment=center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,
  TextWrapped=true,ZIndex=p.ZIndex+2})
end
local function copy(p,name,value,x,y,w,size,color)
 local h=math.ceil(TextService:GetTextSize(value,size,F,Vector2.new(math.max(1,w-4),10000)).Y)+8
 label(p,name,value,x,y,w,h,size,color);return h
end
local function picture(p,name,id,x,y,w,h)
 return make("ImageLabel",name,p,{Image=id,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,
  BorderSizePixel=0,ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=p.ZIndex+1})
end
local function unavailable(ctx,p,name,x,y,w,h,featured)
 local b=ctx.gloss(ctx.button(p,name,"Coming soon",x,y,w,h,function()end,C.Blue,C.Text,featured and 20 or 17,p.ZIndex+3),featured and "Green"or"Navy")
 b:SetAttribute("Disabled",true);b:SetAttribute("PurchaseEnabled",false)
 b.Active=false;b.Interactable=false;b.Selectable=false
 b.Border.Color=featured and Color3.fromRGB(150,255,184)or Color3.fromRGB(73,141,230)
 return b
end
local function reactions(p,x,y,w,h)
 local size=math.min(h,w*.54)
 picture(p,"Happy",Art.Happy,x+w/2-size*.9,y+(h-size)/2,size,size)
 picture(p,"Sad",Art.Sad,x+w/2-size*.1,y+(h-size)/2,size,size)
end
function View.UpdateDepth(dialog,state)
 local catalog=dialog and dialog:FindFirstChild("ShopCatalog")
 local hero=catalog and catalog:FindFirstChild("MarketDepthPro")
 if not hero then return end
 local b=hero.Availability
 b.Text=state.Label;b.ControlLabel.Text=state.Label
 b:SetAttribute("Disabled",not state.Enabled);b:SetAttribute("PurchaseEnabled",state.Enabled)
 b.Active=state.Enabled;b.Interactable=state.Enabled;b.Selectable=state.Enabled
 hero.PurchaseNote.Text=state.Note
 if state.Icon then hero.Artwork.Image=state.Icon end
 dialog:SetAttribute("PurchaseEnabled",state.Enabled)
end
function View.Draw(ctx,w,h)
 local narrow=w<720
 local pw=math.min(1060,w-(narrow and 20 or 48))
 local ph=math.min(714,h-(narrow and 20 or 40))
 local header=narrow and 76 or 86
 local p=frame(ctx.Canvas,"ShopDialog",(w-pw)/2,(h-ph)/2,pw,ph,41)
 p.Active=true;p:SetAttribute("Modal",true);p:SetAttribute("PurchaseEnabled",false)
 surface(p,C.Cyan,Color3.fromRGB(6,37,104),Color3.fromRGB(2,19,57),22);p.Border.Thickness=3
 -- Keep the header and close target outside the scrolling catalog.
 local iconSize=narrow and 34 or 48
 ctx.shopIcon(p,18,(header-iconSize)/2,iconSize)
 label(p,"Title","Shop",narrow and 60 or 76,10,pw-(narrow and 128 or 400),header-20,narrow and 32 or 44)
 if pw>=650 then
  local badge=frame(p,"Permanent",pw-292,25,204,36,43)
  surface(badge,Color3.fromRGB(33,112,211),C.Navy,C.Navy,10)
  label(badge,"Label","Permanent unlocks",8,0,188,36,16,C.Muted,true)
 end
 local close=ctx.dismiss(p,pw-64,(header-46)/2,46,ctx.close,46)
 close.Name="CloseShop";close:SetAttribute("FixedGeometry",true)
 local scroll=make("ScrollingFrame","ShopCatalog",p,{Position=UDim2.fromOffset(10,header),Size=UDim2.fromOffset(pw-20,ph-header-12),
  CanvasSize=UDim2.new(),ScrollingDirection=Enum.ScrollingDirection.Y,ScrollBarThickness=4,ScrollBarImageColor3=C.Cyan,
  BackgroundTransparency=1,BorderSizePixel=0,Active=true,ZIndex=42,ClipsDescendants=true})
 local cw=pw-44;local pad=narrow and 16 or 22;local gap=14
 local hero=frame(scroll,"MarketDepthPro",8,4,cw,1,43)
 hero:SetAttribute("StaticButtons",true);surface(hero,C.Cyan,Color3.fromRGB(23,35,127),C.Navy,18)
 local artW=narrow and cw-pad*2 or math.floor(cw*.4)
 local tw=narrow and cw-pad*2 or cw-artW-pad*2
 local tag=frame(hero,"Featured",pad,16,110,26,44)
 surface(tag,C.Purple,Color3.fromRGB(162,66,255),Color3.fromRGB(99,29,220),7)
 label(tag,"Label","FEATURED",4,0,102,26,14,C.Text,true)
 local yy=50
 yy+=copy(hero,"Title","Market Depth Pro",pad,yy,tw,narrow and 25 or 33)+2
 yy+=copy(hero,"Description","See live bids, asks, and resting orders.",pad,yy,tw,narrow and 15 or 18,C.Muted)+10
 for i,value in ipairs({"Resting bids & asks by price","Best bid, best ask & spread","Easy-to-read liquidity bars"})do
  local dot=frame(hero,"BenefitMark"..i,pad,yy+9,7,7,45);dot.BackgroundColor3=i==3 and C.Purple or C.Cyan
  make("UICorner","Corners",dot,{CornerRadius=UDim.new(1,0)})
  yy+=copy(hero,"Benefit"..i,value,pad+18,yy,tw-18,narrow and 14 or 17,C.Text)+2
 end
 yy+=12
 local buy=ctx.gloss(ctx.button(hero,"Availability","Loading pass…",pad,yy,math.min(tw,326),46,
  function()if ctx.purchaseDepth then ctx.purchaseDepth()end end,C.Blue,C.Text,20,46),"Green")
 buy.ControlLabel.TextScaled=false;buy.ControlLabel.TextSize=20
 yy+=52
 label(hero,"PurchaseNote","One-time purchase · Permanent unlock",pad,yy,tw,36,12,C.Muted)
 yy+=44
 local heroH=math.max(narrow and 0 or 320,yy+8)
 if narrow then
  local artH=math.min(180,artW)
  picture(hero,"Artwork",Art.Depth,pad,yy,artW,artH)
  heroH=yy+artH+12
 else
  picture(hero,"Artwork",Art.Depth,cw-artW-pad,10,artW,heroH-20)
 end
 hero.Size=UDim2.fromOffset(cw,heroH)
 local cards={{Key="VIPTrader",Title="VIP Trader",Image=Art.VIP},{Key="TerminalThemes",Title="Terminal Themes",Image=Art.Themes},
  {Key="TradeReactions",Title="Trade Reactions"}}
 local y=heroH+4+gap
 if narrow then
  for _,item in ipairs(cards)do
   local tile=frame(scroll,item.Key,8,y,cw,132,43);tile:SetAttribute("StaticButtons",true)
   surface(tile,Color3.fromRGB(20,140,255),C.Blue,C.Navy,16)
   local size=math.min(104,cw*.35);local tx=size+18;local tileTextW=cw-tx-12
   if item.Image then picture(tile,"Artwork",item.Image,6,12,size,104)else reactions(tile,6,12,size,104)end
   label(tile,"Title",item.Title,tx,14,tileTextW,48,18)
   unavailable(ctx,tile,"Availability",tx,76,tileTextW,40,false)
   y+=146
  end
 else
  local tileW=(cw-gap*2)/3
  for i,item in ipairs(cards)do
   local tile=frame(scroll,item.Key,8+(i-1)*(tileW+gap),y,tileW,206,43);tile:SetAttribute("StaticButtons",true)
   surface(tile,Color3.fromRGB(20,140,255),C.Blue,C.Navy,16)
   if item.Image then picture(tile,"Artwork",item.Image,10,6,tileW-20,116)else reactions(tile,10,6,tileW-20,116)end
   label(tile,"Title",item.Title,10,124,tileW-20,28,tileW<250 and 19 or 22,C.Text,true)
   unavailable(ctx,tile,"Availability",12,160,tileW-24,34,false)
  end
  y+=220
 end
 scroll.CanvasSize=UDim2.fromOffset(0,y+6)
 View.UpdateDepth(p,ctx.depthState and ctx.depthState()or{Label="Coming soon",Enabled=false,Note="One-time purchase · Permanent unlock"})
 return p
end
return View
