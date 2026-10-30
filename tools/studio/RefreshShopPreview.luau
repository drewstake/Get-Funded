-- Refresh the native Edit-mode shop preview from the same presentation code used in-game.
-- Generated from src/shared/ShopView.luau and TerminalUI's native drawing helpers.
local gui=game.StarterGui:FindFirstChild("MarketReign")
assert(gui,"Trading ScreenGui missing")
local root=gui:FindFirstChild("Workspace")
local canvas=root and root:FindFirstChild("Canvas")
assert(canvas,"Trading preview missing")
local w,h=canvas.Size.X.Offset,canvas.Size.Y.Offset
assert(w>0 and h>0,"Preview size must be established")
local painting -- Chart painting is synchronous; input handlers live on a separate, stable surface.
local fx -- Interaction feedback (tweens and sounds) for the mounted workspace; nil in Edit previews.
local C = {
 -- Colorful game terminal. Opaque plotting surfaces preserve hollow candle readability.
 Bg=Color3.fromRGB(2,17,49), Panel=Color3.fromRGB(5,39,111), Raised=Color3.fromRGB(50,40,147),
 Chart=Color3.fromRGB(3,25,65), Border=Color3.fromRGB(27,92,196), Grid=Color3.fromRGB(20,62,119),
 Text=Color3.fromRGB(245,249,255), Muted=Color3.fromRGB(159,210,248), Blue=Color3.fromRGB(190,132,255),
 Green=Color3.fromRGB(46,249,160), Red=Color3.fromRGB(255,81,127), Buy=Color3.fromRGB(0,211,135), Sell=Color3.fromRGB(249,58,116),
 Cyan=Color3.fromRGB(0,220,255),
}
-- All interface copy uses the same rounded family. Chart axes use a compact numeric font.
local F,M,B,N=Enum.Font.FredokaOne,Enum.Font.FredokaOne,Enum.Font.FredokaOne,Enum.Font.FredokaOne
local function clean(value)
 return (value:gsub("⌄","v"):gsub("⌃","^"):gsub("⋮","..."):gsub("☑","[x]"):gsub("☐","[ ]"))
end
local function make(class,name,parent,props,identity)
 if painting then local o=painting:Get(class,name,parent);painting:Props(o,props or{},identity);return o end
 local o=Instance.new(class);o.Name=name
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function frame(p,name,x,y,w,h,color,z,identity)
 return make("Frame",name,p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color or C.Panel,BorderSizePixel=0,ZIndex=z or p.ZIndex or 1},identity)
end
local function text(p,name,value,x,y,w,h,size,color,font,align,z)
 return make("TextLabel",name,p,{Text=clean(value),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,BorderSizePixel=0,
  TextColor3=color or C.Text,TextSize=size or 13,Font=font or F,
  TextStrokeColor3=Color3.fromRGB(1,15,49),TextStrokeTransparency=(font==Enum.Font.RobotoMono or name=="Watermark"or(color and math.max(color.R,color.G,color.B)<.35))and 1 or .55,
  TextXAlignment=align or Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,ZIndex=z or p.ZIndex})
end
local function stroke(p,color) return make("UIStroke","Border",p,{Color=color or C.Border,Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function round(p,r)make("UICorner","Corners",p,{CornerRadius=UDim.new(0,r or 8)})end
-- Keep outlined cards and centred hover growth inside each scrolling viewport.
local function insetScroll(sc)
 local inset=math.max(8,math.ceil(sc.Size.X.Offset*.01))
 make("UIPadding","ContentPadding",sc,{PaddingLeft=UDim.new(0,inset),PaddingTop=UDim.new(0,inset)})
 return sc.Size.X.Offset-inset*2-sc.ScrollBarThickness-4,inset
end
local function tint(p,top,bottom)
 -- CanvasGroup gradients tint the composited children too. Keep color on a background layer.
 if p:IsA("CanvasGroup")then
  local surface=frame(p,"GradientSurface",0,0,0,0,p.BackgroundColor3,p.ZIndex)
  surface.Size=UDim2.fromScale(1,1);surface.BackgroundTransparency=p.BackgroundTransparency
  local corners=p:FindFirstChildOfClass("UICorner");if corners then corners:Clone().Parent=surface end
  p.BackgroundTransparency=1;p=surface
 end
 return make("UIGradient","SurfaceLight",p,{Color=ColorSequence.new(top or Color3.new(1,1,1),bottom or Color3.fromRGB(213,213,229)),Rotation=90})
end
local function panel(p,accent)
 local gamePanel=p.Name=="Chart"or p.Name=="OrderTicket"or p.Name=="Activity"
 round(p,gamePanel and 17 or 14)
 local edge=stroke(p,gamePanel and Color3.fromRGB(0,112,255)or accent or C.Border);edge.Thickness=gamePanel and 4 or 1
 if p.Name=="OrderTicket"or p.Name=="Activity"then
  p.BackgroundColor3=Color3.new(1,1,1)
  tint(p,p.Name=="OrderTicket"and Color3.fromRGB(52,29,190)or Color3.fromRGB(5,46,129),Color3.fromRGB(3,29,79))
 elseif p.BackgroundColor3~=C.Chart then tint(p)end
end
-- Tabs, segments, toggles and pickers use the softer selection sound.
local SELECT_NAMES={Market=true,Limit=true,Toggle=true,Same=true,Proportional=true,ShowLevels=true,SoundToggle=true}
local function selectable(name)
 return SELECT_NAMES[name]or name:match("^Tab")or name:match("^Nav")or name:match("^Market%u")or name:match("^Time")
  or name:match("^Choose")or name:match("^Lead")or name:match("^Follow")or name:match("^Tool")or name:match("^Level")
end
local function button(p,name,value,x,y,w,h,fn,color,fg,size,z)
 local b=make("TextButton",name,p,{Text=clean(value),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color or C.Raised,
  BackgroundTransparency=color==false and 1 or 0,BorderSizePixel=0,TextColor3=fg or C.Text,TextSize=size or 13,Font=M,
  TextStrokeColor3=Color3.fromRGB(1,15,49),TextStrokeTransparency=.55,AutoButtonColor=false,ZIndex=z or p.ZIndex})
 if color~=false then round(b);stroke(b,fg==C.Blue and C.Blue or C.Border)end
 -- Buttons in a "StaticButtons" container (clipped lists) keep their geometry, so hover growth never clips.
 if name=="BuyLong"or name=="SellShort"or p:GetAttribute("StaticButtons")then b:SetAttribute("FixedGeometry",true)end
 -- One guarded activation path: repeat clicks are debounced, disabled controls ignored, and each
 -- control plays its sound (attribute "Sound": Click, Tick, Select, Open, None).
 b.Activated:Connect(function(...)
  local f=fx
  if f then
   if b.Active==false or f:Guard(b,b:GetAttribute("Debounce"))then return end
   local sound=b:GetAttribute("Sound")
   if sound~="None"then f:Play(sound or(selectable(name)and"Select"or"Click"))end
  end
  fn(...)
 end)
 if fx and name~="OverlayBackdrop"and name~="SheetBackdrop"then
  local area=w*h
  fx:Bind(b,area>18000 and{Lift=1.015,Press=.975}or area>6000 and{Lift=1.025,Press=.955}or{Lift=1.05,Press=.92})
 end
 return b
end
-- Glossy game controls. Every variant: vertical gradient, bright rim, shine strip and outlined label.
local GLOSS={
 Purple={Color3.fromRGB(152,80,255),Color3.fromRGB(80,28,214),Color3.fromRGB(196,140,255)},
 Navy={Color3.fromRGB(15,48,117),Color3.fromRGB(3,24,66),Color3.fromRGB(27,92,196)},
 Grey={Color3.fromRGB(100,108,124),Color3.fromRGB(55,62,77),Color3.fromRGB(145,154,173)},
 Cyan={Color3.fromRGB(0,192,255),Color3.fromRGB(0,94,228),Color3.fromRGB(80,232,255)},
 Green={Color3.fromRGB(34,253,158),Color3.fromRGB(0,173,112),Color3.fromRGB(129,255,202)},
 Pink={Color3.fromRGB(255,120,168),Color3.fromRGB(231,40,99),Color3.fromRGB(255,168,197)},
 Red={Color3.fromRGB(255,109,136),Color3.fromRGB(222,30,72),Color3.fromRGB(255,158,175)},
 Gold={Color3.fromRGB(255,222,40),Color3.fromRGB(255,158,0),Color3.fromRGB(255,244,120)},
}
local GLOSS_INK={Purple=Color3.fromRGB(40,10,120),Navy=Color3.fromRGB(1,15,49),Cyan=Color3.fromRGB(0,48,130),Green=Color3.fromRGB(0,112,72),
 Pink=Color3.fromRGB(160,20,70),Red=Color3.fromRGB(140,14,44),Gold=Color3.fromRGB(150,70,0),Grey=Color3.fromRGB(37,42,54)}
local function glossy(b,variant)
 variant=GLOSS[variant]and variant or"Navy"
 local g=GLOSS[variant]
 local gradient=b:FindFirstChild("ControlLight")
 if not gradient then
  b.BackgroundColor3=Color3.new(1,1,1);b.BackgroundTransparency=0;b:SetAttribute("RestingColor",Color3.new(1,1,1));b.Font=Enum.Font.FredokaOne
  gradient=make("UIGradient","ControlLight",b,{Rotation=90})
  local edge=b:FindFirstChild("Border")or stroke(b);edge.Thickness=2
  if not b:FindFirstChild("Corners")then round(b,9)end
  -- A gradient on a TextButton also tints its own text. A child label stays white.
  b.TextTransparency=1;b.TextStrokeTransparency=1
  local label=text(b,"ControlLabel",b.Text,4,0,b.Size.X.Offset-8,b.Size.Y.Offset,b.TextSize,C.Text,Enum.Font.FredokaOne,Enum.TextXAlignment.Center,b.ZIndex+2)
  label.TextStrokeTransparency=1
  label.TextScaled=true;make("UITextSizeConstraint","TextSize",label,{MinTextSize=8,MaxTextSize=math.max(8,b.TextSize)})
  make("UIStroke","TextOutline",label,{Color=GLOSS_INK[variant],Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual})
 end
 if b:GetAttribute("Gloss")~=variant then
  gradient.Color=ColorSequence.new(g[1],g[2]);b.Border.Color=g[3];b:SetAttribute("Gloss",variant)
  local label=b:FindFirstChild("ControlLabel");local outline=label and label:FindFirstChild("TextOutline")
  if outline then outline.Color=GLOSS_INK[variant]end
  local shine=b:FindFirstChild("Shine")
  if variant~="Navy"and not shine and b.Size.X.Offset>=30 and b.Size.Y.Offset>=24 then
   shine=make("Frame","Shine",b,{Position=UDim2.fromOffset(8,3),Size=UDim2.fromOffset(b.Size.X.Offset-16,3),BackgroundColor3=Color3.new(1,1,1),
    BackgroundTransparency=.5,BorderSizePixel=0,ZIndex=b.ZIndex+1});round(shine,2)
  elseif variant=="Navy"and shine then shine:Destroy()end
 end
 return b
end
-- Glossy selection controls share the interface typography.
local function gameControl(b,selected)
 glossy(b,selected and"Purple"or"Navy")
 if b:GetAttribute("ControlSelected")~=selected then
  b.Border.Color=selected and C.Blue or C.Border;b:SetAttribute("ControlSelected",selected)
  if fx then fx:Selected(b,selected)end
 end
 return b
end
local function gameHeading(label)
 label.Font=Enum.Font.FredokaOne;label.TextStrokeTransparency=1
 make("UIStroke","TextOutline",label,{Color=Color3.fromRGB(1,15,49),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual})
 return label
end
local function panelStars(p)
 local w,h=p.Size.X.Offset,p.Size.Y.Offset
 for i,xy in ipairs({{.93,.09,20},{.96,.92,24},{.035,.92,20}})do
  local size=xy[3]
  local star=frame(p,"Star"..i,xy[1]*w-size/2,xy[2]*h-size/2,size,size,C.Panel,p.ZIndex);star.BackgroundTransparency=1
  for ray=0,4 do
   local angle=math.rad(-90+ray*72)
   local arm=frame(star,"Ray",size/2,size/2,size*.46,size*.28,Color3.fromRGB(29,98,226),p.ZIndex)
   arm.AnchorPoint=Vector2.new(0,.5);arm.Rotation=math.deg(angle);arm.BackgroundTransparency=.65;round(arm,size*.1)
  end
 end
end
local function rule(p,x,y,w,color,z)return frame(p,"Rule",x,y,w,1,color or C.Border,z)end
local function line(p,name,x1,y1,x2,y2,color,width,z)
 local l=frame(p,name,(x1+x2)/2,(y1+y2)/2,Vector2.new(x2-x1,y2-y1).Magnitude,width or 1,color,z)
 l.AnchorPoint=Vector2.new(.5,.5);l.Rotation=math.deg(math.atan2(y2-y1,x2-x1));return l
end
-- Red glossy close button with a drawn cross (the reference popups' X).
local function dismissButton(p,x,y,size,fn,z)
 local d=button(p,"Dismiss","",x,y,size,size,fn,Color3.new(1,1,1),C.Text,20,z or p.ZIndex+2)
 d.Corners.CornerRadius=UDim.new(0,math.floor(size*.26));d.Border.Color=Color3.fromRGB(255,158,175);d.Border.Thickness=3
 tint(d,Color3.fromRGB(255,109,136),Color3.fromRGB(227,33,77))
 local pad=size*.3
 for _,pts in ipairs({{pad,pad,size-pad,size-pad},{pad,size-pad,size-pad,pad}})do
  local shadow=line(d,"CrossShadow",pts[1],pts[2]+1,pts[3],pts[4]+1,Color3.fromRGB(174,21,52),math.max(5,size*.16),d.ZIndex+1);round(shadow,4)
  local cross=line(d,"Cross",pts[1],pts[2],pts[3],pts[4],C.Text,math.max(3,size*.1),d.ZIndex+2);round(cross,3)
 end
 return d
end

local ShopView=(function()
-- Shop presentation only. Catalog items remain unavailable until real passes are configured.
-- ImageGen originals and prompts are kept in icons/shop. All copy and controls are native UI.
local TextService=game:GetService("TextService")
local View={}
local Art={Depth="rbxassetid://120468782574228",VIP="rbxassetid://131970148250145",Themes="rbxassetid://109496208973919",
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
 yy+=copy(hero,"Description","See the orders behind the market.",pad,yy,tw,narrow and 15 or 18,C.Muted)+10
 for i,value in ipairs({"Live buy & sell orders","Deeper market view","Easy-to-read liquidity bars"})do
  local dot=frame(hero,"BenefitMark"..i,pad,yy+9,7,7,45);dot.BackgroundColor3=i==3 and C.Purple or C.Cyan
  make("UICorner","Corners",dot,{CornerRadius=UDim.new(1,0)})
  yy+=copy(hero,"Benefit"..i,value,pad+18,yy,tw-18,narrow and 14 or 17,C.Text)+2
 end
 yy+=12
 unavailable(ctx,hero,"Availability",pad,yy,math.min(tw,326),46,true)
 yy+=52
 yy+=copy(hero,"PurchaseNote","One-time purchase · Permanent unlock",pad,yy,tw,12,C.Muted)+8
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
 return p
end
return View

end)()

local function close()
 for _,name in ipairs({"ShopDialog","OverlayBackdrop"})do
  local old=canvas:FindFirstChild(name);if old then old:Destroy()end
 end
 root:SetAttribute("PreviewOverlay",nil)
end
-- Draw off-screen first so a construction error leaves the current preview intact.
local stage=Instance.new("Frame");stage.Name="ShopPreviewStage";stage.Size=UDim2.fromOffset(w,h);stage.Visible=false;stage.Parent=root
local ok,result=pcall(function()
 local backdrop=button(stage,"OverlayBackdrop","",0,0,w,h,close,C.Bg,C.Text,12,40);backdrop.BackgroundTransparency=.28
 local dialog=ShopView.Draw({Canvas=stage,button=button,gloss=glossy,dismiss=dismissButton,close=close,
  shopIcon=function(p,x,y,size)
   return make("ImageLabel","IconShop",p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(size,size),
    BackgroundTransparency=1,Image="rbxassetid://133669386970310",ScaleType=Enum.ScaleType.Fit,ZIndex=p.ZIndex+1})
  end},w,h)
 assert(dialog and dialog.ShopCatalog,"Shop construction failed")
 local rail=canvas:FindFirstChild("Sidebar")
 if rail then
  local nav=rail:FindFirstChild("NavShop")
  local previous=rail:FindFirstChild("NavLeaderboard")
  if not nav then
   nav=assert(rail:FindFirstChild("NavStats"),"Preview navigation missing"):Clone()
   nav.Name="NavShop";nav.Label.Text="Shop";nav.Label.NavTextSize.MaxTextSize=21
   local icon=nav:FindFirstChild("IconStats");if icon then icon.Name="IconShop";icon.Image="rbxassetid://133669386970310"end
   nav.Parent=rail
  end
  if previous then
   nav.Position=UDim2.fromOffset(previous.Position.X.Offset,previous.Position.Y.Offset+previous.Size.Y.Offset+9)
   local caption=rail:FindFirstChild("Markets")
   if caption then
    local shift=nav.Position.Y.Offset+nav.Size.Y.Offset+19-caption.Position.Y.Offset
    for _,v in ipairs(rail:GetChildren())do
     if v:IsA("GuiObject")and(v.Name=="Markets"or v.Name:match("^Market%u"))then v.Position+=UDim2.fromOffset(0,shift)end
    end
   end
  end
 end
 close()
 for _,v in ipairs(stage:GetChildren())do v.Parent=canvas end
 root:SetAttribute("PreviewOverlay","Shop");root:SetAttribute("ShopPreviewUpdated","2026-10-02")
 gui.Enabled=true
 return {Width=w,Height=h,ShopVisible=canvas.ShopDialog.Visible,Products=4,ShopNavigation=rail and rail:FindFirstChild("NavShop")~=nil}
end)
stage:Destroy()
if not ok then error(result)end
return game:GetService("HttpService"):JSONEncode(result)
