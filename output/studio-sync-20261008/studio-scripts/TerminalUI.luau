-- Native Roblox GUI. All panels and chart marks are editable GuiObjects.
local Market = require(script.Parent.MarketClient)
local ChartView = require(script.Parent.ChartView)
local Feedback = require(script.Parent.UIFeedback)
local LeaderboardClient = require(script.Parent.LeaderboardClient)
local LeaderboardView = require(script.Parent.LeaderboardView)
local StatsView = require(script.Parent.StatsView)
local ProgressView = require(script.Parent.ProgressView)
local BadgeArt=require(script.Parent.BadgeArt)
local AwayView=require(script.Parent.AwayView)
local ShopView = require(script.Parent.ShopView)
local DepthPurchase = require(script.Parent.DepthPurchase)
local Level2View = require(script.Parent.Level2View)
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UI = {}
-- ImageGen artwork: icons/copy-trading/follower-checkmark.png (transparent RGBA).
local FOLLOWER_CHECKMARK = "rbxassetid://87249253289841"
-- ImageGen artwork in icons/trade-outcomes; the sign of the actual closing P&L selects the face.
local TRADE_OUTCOME_FACES={Profit="rbxassetid://115617570278067",Loss="rbxassetid://128402867973425"}
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
-- Small line icons are native GuiObjects, so no external image assets are required.
local function icon(p,kind,x,y,size,color)
 local box=frame(p,"Icon"..kind,x,y,size,size,C.Panel);box.BackgroundTransparency=1
 local function l(a,b,c,d)line(box,"Path",a*size,b*size,c*size,d*size,color or C.Blue,1.5)end
 if kind=="Trade"or kind=="Equity"then
  for i,hh in ipairs({.3,.55,.8})do
   local bar=frame(box,"Bar",(i-1)*size*.31,size*(1-hh),size*.17,size*hh,C.Panel);bar.BackgroundTransparency=1;stroke(bar,color or C.Blue)
  end
 elseif kind=="Positions"or kind=="Balance"then
  l(.08,.3,.92,.3);l(.92,.3,.92,.87);l(.92,.87,.08,.87);l(.08,.87,.08,.3)
  l(.31,.3,.31,.12);l(.31,.12,.67,.12);l(.67,.12,.67,.3);l(.08,.5,.92,.5)
 elseif kind=="Learn"then
  l(.5,.18,.5,.91);l(.08,.1,.5,.18);l(.5,.18,.92,.1);l(.08,.1,.08,.78);l(.92,.1,.92,.78);l(.08,.78,.5,.91);l(.5,.91,.92,.78)
 elseif kind=="Review"then
  l(.12,.15,.88,.15);l(.88,.15,.88,.9);l(.88,.9,.12,.9);l(.12,.9,.12,.15);l(.28,.38,.72,.38);l(.28,.57,.72,.57);l(.28,.76,.55,.76)
 elseif kind=="Accounts"or kind=="Trophy"then
  l(.24,.12,.76,.12);l(.24,.12,.31,.5);l(.76,.12,.69,.5);l(.31,.5,.69,.5);l(.5,.5,.5,.72);l(.34,.72,.66,.72)
  l(.34,.72,.28,.9);l(.66,.72,.72,.9);l(.28,.9,.72,.9);l(.24,.2,.08,.2);l(.08,.2,.16,.4);l(.76,.2,.92,.2);l(.92,.2,.84,.4)
 elseif kind=="Lock"then
  l(.2,.45,.8,.45);l(.8,.45,.8,.9);l(.8,.9,.2,.9);l(.2,.9,.2,.45);l(.34,.45,.34,.2);l(.34,.2,.66,.2);l(.66,.2,.66,.45);l(.5,.6,.5,.75)
 elseif kind=="Copy"then
  l(.1,.32,.62,.32);l(.62,.32,.62,.9);l(.62,.9,.1,.9);l(.1,.9,.1,.32);l(.38,.32,.38,.1);l(.38,.1,.9,.1);l(.9,.1,.9,.68);l(.9,.68,.62,.68)
 elseif kind=="Check"then
  l(.14,.55,.4,.8);l(.4,.8,.88,.22)
 else
  l(.5,.9,.5,.1);l(.5,.1,.18,.42);l(.5,.1,.82,.42)
 end
 return box
end
local function dash(p,x,y,w,color,d,z,t)
 if painting then return painting:Dash(p,x,y,w,color,d,z,t)end
 t=t or 1
 for off=0,w,d+5 do frame(p,"DashedLine",x+off,y-(t-1)//2,math.min(d,w-off),t,color,z)end
end
local RIGHT,CENTER=Enum.TextXAlignment.Right,Enum.TextXAlignment.Center
-- Colorful game summary: uploaded transparent artwork with native, live text.
local SC={Ink=Color3.fromRGB(3,18,55),Green=Color3.fromRGB(50,255,91),Red=Color3.fromRGB(255,143,166)}
local SF=Enum.Font.FredokaOne
local summaryThemes={
 Balance={Top=Color3.fromRGB(0,171,255),Bottom=Color3.fromRGB(0,91,230),Edge=Color3.fromRGB(17,211,255),Base=Color3.fromRGB(0,56,153),Image="rbxassetid://84096597834437"},
 Equity={Top=Color3.fromRGB(137,57,255),Bottom=Color3.fromRGB(78,31,220),Edge=Color3.fromRGB(183,105,255),Base=Color3.fromRGB(56,12,145),Image="rbxassetid://135864586704544"},
 Unrealized={Top=Color3.fromRGB(0,216,107),Bottom=Color3.fromRGB(0,145,100),Edge=Color3.fromRGB(10,245,134),Base=Color3.fromRGB(0,84,66),Image="rbxassetid://140314319475475"},
 Trophy={Top=Color3.fromRGB(255,224,33),Bottom=Color3.fromRGB(255,167,0),Edge=Color3.fromRGB(255,244,98),Base=Color3.fromRGB(166,77,0),Image="rbxassetid://80175474742009"},
 Blown={Top=Color3.fromRGB(255,96,150),Bottom=Color3.fromRGB(190,22,92),Edge=Color3.fromRGB(255,178,204),Base=Color3.fromRGB(104,8,54)},
}
local function summarySurface(tile,kind,compact)
 local theme=summaryThemes[kind]
 local w,h=tile.Size.X.Offset,tile.Size.Y.Offset
 local radius=compact and 10 or 20
 local depth=compact and 3 or 8
 local base=frame(tile.Parent,kind.."Depth",tile.Position.X.Offset,tile.Position.Y.Offset+depth,w,h,theme.Base,2)
 round(base,radius);local outline=stroke(base,SC.Ink);outline.Thickness=compact and 3 or 6
 tile.ZIndex=3;tile.BackgroundColor3=Color3.new(1,1,1)
 tile.Border.Color=theme.Edge;tile.Border.Thickness=compact and 2 or 4
 tile.Corners.CornerRadius=UDim.new(0,radius)
 tint(tile,theme.Top,theme.Bottom)
 local texture=frame(tile,"Texture",5,5,w-10,h-10,theme.Top,3);texture.BackgroundTransparency=1
 texture.ClipsDescendants=true;round(texture,radius-3)
 if not compact then
  for i,xy in ipairs({{.1,.18},{.88,.2},{.12,.78},{.84,.8},{.55,.12}})do
   local d=frame(texture,"Diamond"..i,xy[1]*(w-20),xy[2]*(h-20),12,12,Color3.new(1,1,1),3)
   d.Rotation=45;d.BackgroundTransparency=.93;round(d,2)
  end
  local shine=frame(texture,"Shine",w*.16,-h*.25,w*.13,h*1.6,Color3.new(1,1,1),3)
  shine.Rotation=38;shine.BackgroundTransparency=.94
 end
end
-- Shared by the chart header and order ticket at every viewport size.
local function instrumentSelector(p,value,x,y,w,h,fn,size)
 local b
 b=gameControl(button(p,"ContractSelector",value,x,y,w,h,function()fn(b)end,C.Chart,C.Text,size),false)
 local label=b.ControlLabel
 label.Position=UDim2.fromOffset(12,0);label.Size=UDim2.fromOffset(w-48,h);label.TextXAlignment=Enum.TextXAlignment.Left
 local chevron=frame(b,"Chevron",w-28,(h-14)/2,16,14,C.Chart,b.ZIndex+2);chevron.BackgroundTransparency=1;chevron.Active=false
 line(chevron,"Left",2,4,8,10,C.Text,3,chevron.ZIndex)
 line(chevron,"Right",8,10,14,4,C.Text,3,chevron.ZIndex)
 b.Border.Color=C.Cyan
 return b
end
local function summaryIcon(p,kind,x,y,size,negative)
 return make("ImageLabel","IconPanel",p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(size,size),
  BackgroundTransparency=1,Image=summaryThemes[kind].Image,ScaleType=Enum.ScaleType.Fit,ZIndex=5,
  Rotation=0,ImageColor3=negative and Color3.fromRGB(255,176,189)or Color3.new(1,1,1)})
end
local function summaryText(p,name,value,x,y,w,h,size,color,compact)
 local label=text(p,name,value,x,y,w,h,size,color or C.Text,SF,nil,6)
 label.TextStrokeTransparency=1
 label.TextScaled=true
 make("UITextSizeConstraint","TypeSize",label,{MinTextSize=compact and 8 or 10,MaxTextSize=size})
 make("UIStroke","TextOutline",label,{Color=SC.Ink,Thickness=compact and 1.5 or math.clamp(size*.09,2,4),ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual,LineJoinMode=Enum.LineJoinMode.Round})
 return label
end
-- Fixed-size text for labels on cards that lift on hover. TextScaled re-measures against the lifted (UIScale)
-- size and can re-wrap, so these take the largest size up to the label's constraint that fits its box once.
local function fixText(label)
 local constraint=label:FindFirstChild("TypeSize")
 local size=constraint and constraint.MaxTextSize or label.TextSize
 local floor=constraint and constraint.MinTextSize or 8
 local w,h=label.Size.X.Offset,label.Size.Y.Offset
 local function fits(n)
  for line in (label.Text.."\n"):gmatch("(.-)\n")do if TextService:GetTextSize(line,n,label.Font,Vector2.new(1e4,1e4)).X>w then return false end end
  return TextService:GetTextSize(label.Text,n,label.Font,Vector2.new(1e4,1e4)).Y<=h
 end
 while size>floor and not fits(size)do size-=1 end
 label.TextScaled=false;label.TextWrapped=false;label.TextSize=size
 return label
end
-- A goal name on two fixed lines: "$100K FUNDED ACCOUNT" -> "$100K FUNDED" / "ACCOUNT".
local function goalLines(value)
 local head,tail=tostring(value):match("^(.*%S)%s+(%S+)$")
 return head and(head.."\n"..tail)or tostring(value)
end
local SB={Navy=Color3.fromRGB(3,27,78),Blue=Color3.fromRGB(6,49,130),Cyan=Color3.fromRGB(0,189,255),Muted=Color3.fromRGB(144,208,255)}
local sidebarImages={
 Shop="rbxassetid://133669386970310",Leaderboard="rbxassetid://80175474742009",Stats="rbxassetid://140314319475475",
 Trade="rbxassetid://135864586704544",Accounts="rbxassetid://80175474742009",Positions="rbxassetid://133669386970310",
 Review="rbxassetid://77222088024812",Learn="rbxassetid://103790301090850",Settings="rbxassetid://101222726907418",Help="rbxassetid://135400245653127",
}
local function sidebarImage(p,kind,x,y,size)
 return make("ImageLabel","Icon"..kind,p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(size,size),
  BackgroundTransparency=1,Image=sidebarImages[kind],ScaleType=Enum.ScaleType.Fit,ZIndex=p.ZIndex+1})
end
local function sidebarText(p,name,value,x,y,w,h,size,color)
 local t=summaryText(p,name,value,x,y,w,h,size,color or C.Text,false)
 t.ZIndex=p.ZIndex+2;t.TextOutline.Thickness=math.clamp(size*.085,1,2.5)
 return t
end
local function sidebarSurface(b,selected,cyan)
 b.Corners.CornerRadius=UDim.new(0,12)
 b.Border.Color=selected and(cyan and Color3.fromRGB(34,232,255)or Color3.fromRGB(193,128,255))or Color3.fromRGB(24,65,143)
 b.Border.Thickness=selected and 3 or 2
 tint(b,selected and(cyan and Color3.fromRGB(0,184,255)or Color3.fromRGB(162,66,255))or Color3.fromRGB(5,37,103),
  selected and(cyan and Color3.fromRGB(0,99,235)or Color3.fromRGB(85,22,231))or Color3.fromRGB(3,23,68))
 if selected then
  local shine=frame(b,"Shine",7,5,b.Size.X.Offset-14,3,Color3.new(1,1,1),b.ZIndex+1)
  shine.BackgroundTransparency=.55;round(shine,2)
  local depth=frame(b,"LowerEdge",8,b.Size.Y.Offset-6,b.Size.X.Offset-16,3,SC.Ink,b.ZIndex+1)
  depth.BackgroundTransparency=.6;round(depth,2)
 end
end
-- Flat account rows (Accounts card and copy editor): one clean rim, no shine strip or lower edge.
local ROW_LOOK={
 Purple={Color3.fromRGB(156,72,255),Color3.fromRGB(92,30,228),Color3.fromRGB(171,102,255)},
 Cyan={Color3.fromRGB(0,176,255),Color3.fromRGB(0,100,230),Color3.fromRGB(64,222,255)},
 Navy={Color3.fromRGB(6,48,122),Color3.fromRGB(3,29,82),Color3.fromRGB(26,88,186)},
}
local function rowSurface(b,variant,radius,edge)
 local look=ROW_LOOK[variant]or ROW_LOOK.Navy
 b.Corners.CornerRadius=UDim.new(0,radius)
 b.Border.Color=look[3];b.Border.Thickness=edge or 2
 tint(b,look[1],look[2])
end
function UI.Mount(gui,options)
 options=options or {}
 local old=gui:FindFirstChild("Workspace");if old then old:Destroy()end
 local root=make("Frame","Workspace",gui,{Size=UDim2.fromScale(1,1),BackgroundColor3=C.Bg,BorderSizePixel=0,ClipsDescendants=true})
 local canvas=frame(root,"Canvas",0,0,1440,900,C.Bg)
 if fx then fx:Destroy()end
 fx=not options.Preview and Feedback.new(root,{})or nil
 local feedback=fx
 local s={Contract=Market.ContractOrder[1],Timeframe="1m",Type="Market",Qty=1,Limit=5820,Stop=5802.5,Target=5842.5,StopOn=true,TargetOn=true,
  Tab="Positions",Nav="Trade",Sheet=false,ProtectionDraft=nil,StopDollars=500,TargetDollars=1500,Overlay=nil,Guide=1,Tool="Pan",Drawings={},Levels=true,
  Screen=nil,Coach=nil,SoundOn=true,SoundLevel="Medium",PendingOrder=nil,PendingClose=nil,Level2Expanded=true}
 local Ladder=Market.Progression
 local session=Market.New(nil,options.Preview,options.PreviewData)
 local leaderboard=LeaderboardClient.new(options.Preview,options.LeaderboardData)
 if options.LeaderboardData then s.Screen="Leaderboard";s.Nav="Leaderboard" end
 -- Isolated layout fixtures (Studio validation / previews) can supply server-shaped portfolio and stats views.
 if options.PortfolioData then session.Portfolio=options.PortfolioData end
 if options.StatsData then session.Stats=options.StatsData;s.Screen="Stats";s.Nav="Stats";s.StatsScope=options.StatsScope;s.StatsPeriod=options.StatsPeriod end
 local function restoreProtectionPreferences()
  for key,value in pairs(session.ProtectionPreferences)do s[key]=value end
 end
 restoreProtectionPreferences()
 local render,dirty,alive=nil,false,true
 local connections={}
 local lastW,lastH=0,0
 local firstPoint,toastId=nil,0
 local views={}
 local depthViews={}
 local depthScales={}
 local depthPurchase
 local function updateShop()
  local dialog=canvas:FindFirstChild("ShopDialog")
  if dialog and depthPurchase then ShopView.UpdateDepth(dialog,depthPurchase:State())end
 end
 depthPurchase=DepthPurchase.new(session,options.Preview,updateShop)
 local repaintChart,chartView
 local fullRefreshPending=false
 local requestedPreserve=false
 local preservedTicket
 local function refresh(keepTicket)
  if dirty then if not keepTicket then requestedPreserve=false end;return end
  if not alive then return end
  if chartView and chartView:Busy()then fullRefreshPending=true;return end
  local focused=UIS:GetFocusedTextBox();if focused and focused:IsDescendantOf(root)then return end
  requestedPreserve=keepTicket==true
  dirty=true;task.defer(function()dirty=false;local keep=requestedPreserve;requestedPreserve=false;if alive and root.Parent then render(keep)end end)
 end
 -- kind: "error" (red, error sound), "success" (green) or "info" (cyan). Sounds for success come
 -- from server replies, never from the toast itself.
 local function toast(message,kind,pnl,followup)
  if not message or message==""then return end
  toastId+=1;local id=toastId;s.Toast=message;s.ToastKind=kind or(s.Error and"error"or"info");s.ToastPnl=pnl;s.ToastFollowup=followup;refresh()
  task.delay(pnl~=nil and 3 or s.ToastKind=="error"and 5 or 4,function()
   if alive and id==toastId then
    s.Toast=nil;s.ToastPnl=nil;s.ToastFollowup=nil
    if followup then toast(followup,"success")else refresh()end
   end
  end)
 end
 local function fail(message)
  s.Error=message;if fx then fx:Play("Error")end;toast(message,"error")
 end
 local shownToast
 local function toastView(w,h,mobile)
  local closed=type(s.ToastPnl)=="number"
  if closed then
   -- ImageGen-inspired card; text stays native so every fill shows its actual signed P&L.
   -- Centre inside the visible plot, clear of summary cards, axes and trading controls.
   local chart=canvas:FindFirstChild("Chart")
   local g=chart and chartView.Geometry
   local ax,ay,aw,ah=12,math.max(12,h/2-50),w-24,100
   if g then
    ax=chart.Position.X.Offset+g.Plot.Position.X.Offset+g.Left
    ay=chart.Position.Y.Offset+g.Plot.Position.Y.Offset+g.Top
    aw=g.Width;ah=math.max(1,math.min(g.Height,chart.Size.Y.Offset-g.Plot.Position.Y.Offset-g.Top-4))
   end
   local th=math.min(mobile and 60 or 64,math.max(20,ah-8));local small=th<54
   local outcome=s.ToastPnl>0 and "Profit"or s.ToastPnl<0 and "Loss"or nil
   local faceSize=small and math.max(12,th-6)or mobile and 34 or 40
   local pad=small and 8 or 12;local tx=outcome and pad+faceSize+8 or pad
   local titleSize=small and 11 or mobile and 13 or 14;local amountSize=small and 16 or mobile and 24 or 26
   local amountText=Market.Signed(s.ToastPnl)
   local titleWidth=TextService:GetTextSize("Trade closed",titleSize,F,Vector2.new(1000,100)).X
   local amountWidth=TextService:GetTextSize(amountText,amountSize,F,Vector2.new(1000,100)).X
   local contentWidth=small and titleWidth+amountWidth+12 or math.max(titleWidth,amountWidth)
   -- Fit the message rather than reserving an empty fixed-width right half.
   local tw=math.min(320,aw-12,math.max(outcome and 188 or 144,tx+contentWidth+pad+4))
   local p=frame(canvas,"Toast",ax+(aw-tw)/2,ay+(ah-th)/2,tw,th,Color3.new(1,1,1),60);round(p,small and 10 or 14)
   p.Active=false;p:SetAttribute("TradeClosed",true);p:SetAttribute("Pnl",s.ToastPnl)
   tint(p,Color3.fromRGB(9,57,133),Color3.fromRGB(3,22,59))
   stroke(p,C.Cyan).Thickness=2
   local inset=frame(p,"InnerRim",3,3,tw-6,th-6,C.Cyan,61);inset.BackgroundTransparency=1;round(inset,small and 8 or 11)
   local rim=stroke(inset,Color3.fromRGB(90,193,255));rim.Thickness=1;rim.Transparency=.65
   local shine=frame(p,"Shine",14,4,tw-28,2,Color3.fromRGB(113,211,255),62);shine.BackgroundTransparency=.55;round(shine,1)
   local amountColor=s.ToastPnl>0 and C.Green or s.ToastPnl<0 and C.Red or C.Text
   if outcome then
    local face=make("ImageLabel","OutcomeFace",p,{Position=UDim2.fromOffset(pad,(th-faceSize)/2),Size=UDim2.fromOffset(faceSize,faceSize),
     BackgroundTransparency=1,BorderSizePixel=0,Image=TRADE_OUTCOME_FACES[outcome],ScaleType=Enum.ScaleType.Fit,Active=false,ZIndex=63})
    face:SetAttribute("Outcome",outcome)
   end
   local textW=tw-tx-pad;local top=(th-48)/2
   local title=text(p,"Message","Trade closed",tx,small and 0 or top,small and textW*.5 or textW,small and th or 18,titleSize,C.Text,F,Enum.TextXAlignment.Left,63)
   local amount=text(p,"Pnl",amountText,small and tx+textW*.5 or tx,small and 0 or top+20,small and textW*.5 or textW,small and th or 28,amountSize,amountColor,F,small and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,63)
   title.TextScaled=true;make("UITextSizeConstraint","TypeSize",title,{MinTextSize=9,MaxTextSize=titleSize})
   amount.TextScaled=true;make("UITextSizeConstraint","TypeSize",amount,{MinTextSize=10,MaxTextSize=amountSize})
   if fx and shownToast~=toastId then
    shownToast=toastId
    local scale=make("UIScale","Arrival",p,{Scale=.94});Feedback.Centre(p)
    fx:Tween(scale,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1})
   end
   return
  end
  local kind=s.ToastKind or"info"
  local accent=kind=="error"and Color3.fromRGB(255,110,140)or kind=="success"and Color3.fromRGB(60,255,160)or C.Cyan
  local tw=math.min(500,w-24);local ty=mobile and 62 or 30
  local lines=TextService:GetTextSize(s.Toast,14,Enum.Font.FredokaOne,Vector2.new(tw-78,1000)).Y
  local th=math.clamp(lines+26,52,h-ty-20)
  local p=frame(canvas,"Toast",(w-tw)/2,ty,tw,th,Color3.new(1,1,1),60);round(p,16)
  local edge=stroke(p,accent);edge.Thickness=3
  tint(p,kind=="error"and Color3.fromRGB(92,20,74)or kind=="success"and Color3.fromRGB(4,88,84)or Color3.fromRGB(8,62,160),Color3.fromRGB(3,24,72))
  local badge=frame(p,"Badge",12,(th-32)/2,32,32,accent,61);round(badge,16);stroke(badge,SC.Ink).Thickness=2
  if kind=="error"then
   local bar=frame(badge,"Mark",14,6,4,13,SC.Ink,62);round(bar,2);local dot=frame(badge,"Dot",14,22,4,4,SC.Ink,62);round(dot,2)
  elseif kind=="success"then
   line(badge,"Tick",8,17,14,23,SC.Ink,4,62);line(badge,"Tick",13,23,24,10,SC.Ink,4,62)
  else
   local dot=frame(badge,"Dot",14,7,4,4,SC.Ink,62);round(dot,2);local bar=frame(badge,"Mark",14,13,4,12,SC.Ink,62);round(bar,2)
  end
  local label=summaryText(p,"Message",s.Toast,54,4,tw-68,th-8,14,C.Text,true)
  label.TextWrapped=true;label.TextXAlignment=Enum.TextXAlignment.Left;label.TextScaled=false;label.TextSize=14;label.ZIndex=61
  if fx and shownToast~=toastId then
   shownToast=toastId
   local target=p.Position;p.Position=target-UDim2.fromOffset(0,16)
   fx:Tween(p,TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Position=target})
  end
 end
 -- Effects queued by replies run after the rebuild they trigger, on the rebuilt controls.
 local queuedEffects={}
 local function locate(path)
  local node=canvas
  for part in path:gmatch("[^%.]+")do node=node and node:FindFirstChild(part)end
  return node
 end
 local function runEffects()
  if not fx or #queuedEffects==0 then return end
  local list=queuedEffects;queuedEffects={}
  for _,e in ipairs(list)do
   local target;for _,path in ipairs(e.Paths)do target=target or locate(path)end
   if target then
    if e.Kind=="Success"then fx:Pulse(target);fx:Ring(target,e.Color or C.Green,14)
    elseif e.Kind=="Error"then fx:Shake(target)
    elseif e.Kind=="Pulse"then fx:Pulse(target)end
   end
  end
 end
 local function effect(paths,kind,color)
  if not fx then return end
  table.insert(queuedEffects,{Paths=paths,Kind=kind,Color=color})
  task.delay(.08,runEffects) -- in case no rebuild follows
 end
 -- Funded portfolio helpers. The server sends the portfolio view; the client never computes unlocks.
 local function whole(value)return(Market.Money(value):gsub("%.00$",""))end
 local function net(value)return(value or 0)<0 and "−"..whole(-value)or whole(value or 0)end
 local function activeRow()
  local pf=session.Portfolio;if not pf or not pf.Active then return nil end
  for _,list in ipairs({pf.Accounts or{}})do for _,row in ipairs(list)do if row.Key==pf.Active then return row end end end
 end
 -- Player-facing account names never carry attempt numbers ("$10K FUNDED ACCOUNT"); keys keep accounts distinct.
 local function accountName()return "Trading account"end
 local function accountShort()return "Trading account"end
 local function tradeAccountName()return "Trading account"end
 local function goalAmount(n)
  if not n then return "All titles earned" end
  if n.Kind=="Trades" or n.Kind=="Wins" then return math.floor(n.Progress).." / "..n.Goal end
  return whole(n.Progress).." / "..whole(n.Goal)
 end
 local function objective()
  local pf=session.Portfolio;local n=pf and pf.Next
  if not n then return "NEXT GOAL",pf and "Every title earned" or "Close your first trade",pf and 1 or 0,pf and "Title collection complete" or "0 / 1","Build your record. Earn your rank." end
  return "NEXT GOAL",n.Name,math.clamp(n.Progress/n.Goal,0,1),goalAmount(n),n.Name
 end
 -- Phone account strip: "16 / 100 trades".
 local function stripGoal()
  local pf=session.Portfolio;local n=pf and pf.Next
  if not n then return pf and "All titles earned" or "0 / 1 trades" end
  local amount=goalAmount(n)
  if n.Kind=="Trades"then return amount.." trades"elseif n.Kind=="Wins"then return amount.." wins"end
  return amount
 end
 local function tierRow(key)
  local pf=session.Portfolio
  for _,row in ipairs(pf and pf.Accounts or{})do if row.Key==key then return row end end
 end
 local function alertBadge(p,x,y,size,z)
  local badge=frame(p,"AlertBadge",x,y,size,size,Color3.fromRGB(255,222,40),z);round(badge,math.floor(size/2))
  stroke(badge,SC.Ink).Thickness=math.max(2,math.floor(size*.07))
  local bw=math.max(3,math.floor(size*.14))
  local bar=frame(badge,"Mark",math.floor((size-bw)/2),math.floor(size*.2),bw,math.floor(size*.4),SC.Ink,z+1);round(bar,2)
  local dot=frame(badge,"Dot",math.floor((size-bw)/2),math.floor(size*.68),bw,bw,SC.Ink,z+1);round(dot,2)
  return badge
 end
 local function restartLabel(row,short)
  if s.PendingRestart and s.PendingRestart.Tier==row.Key then return "Restarting…",true end
  if row.Closing then return short and"Closing…"or"Closing positions…",true end
  if not row.CanRestart then return short and"Unavailable"or"Restart unavailable",true end
  return "Restart · "..whole((session.Portfolio or {}).StartingBalance or Ladder.StartingBalance),s.PendingRestart~=nil
 end
 -- One restart in flight at a time; the button shows "Restarting…" until the server replies (or 8 s pass).
 local function restartAccount(key)
  if s.PendingRestart then return end
  local row=tierRow(key)
  if not row or not row.Depleted or not row.CanRestart then fail("Restart with your earned starting balance after your account fails.");return end
  if row.Closing then fail("Closing your remaining positions. Restart when they have all closed.");return end
  local ok,message,_,requestId=session:Restart(key)
  if not ok then fail(message);return end
  local pending={Id=requestId,Tier=key};s.PendingRestart=pending;s.Error=nil
  if fx then fx:Play("Send")end
  toast("Restarting "..row.Name.."…","info")
  task.delay(8,function()
   if alive and s.PendingRestart==pending then s.PendingRestart=nil;fail("No confirmation from the exchange yet. Check the account before retrying.")end
  end)
 end

 local function restartButton(p,row,x,y,w,h,size,z,short,thick)
  local label,disabled=restartLabel(row,short)
  local b=glossy(button(p,"RestartAccount",label,x,y,w,h,function()restartAccount(row.Key)end,C.Raised,C.Text,size,z),disabled and"Navy"or"Pink")
  b.Corners.CornerRadius=UDim.new(0,14);if thick then b.Border.Thickness=3 end
  b:SetAttribute("Debounce",.6);b:SetAttribute("Sound","None")
  b:SetAttribute("RestartTier",row.Key);b:SetAttribute("RestartState",disabled and label or"Ready")
  if disabled then b.Active=false;b.Border.Color=Color3.fromRGB(255,168,197);local l=b:FindFirstChild("ControlLabel");if l then l.TextColor3=Color3.fromRGB(205,222,245)end end
  return b
 end
 -- The notice opens once per server depletion event; players can reopen it from the blown status.
 local blownQueue={}
 local function openBlown(key)
  local row=tierRow(key);if not row or not row.Depleted then return false end
  s.BlownTier=key;s.BlownEvent=row.DepletionEvent;s.Overlay="Blown";s.Sheet=false;refresh()
  return true
 end
 local function nextBlown()
  while #blownQueue>0 do
   local item=table.remove(blownQueue,1);local row=tierRow(item.Tier)
   if row and row.Depleted and row.DepletionEvent==item.Event and openBlown(item.Tier)then return true end
  end
  return false
 end
 local function selectContract(key)
  s.Contract=key;local c=Market.Contracts[key];local p=session.Positions[key]
  s.Limit=Market.Snap(session.Prices[key]-4*c.Scale,key)
  s.Stop=p and p.Stop or Market.Snap(session.Prices[key]-22.25*c.Scale,key)
  s.Target=p and p.Target or Market.Snap(session.Prices[key]+17.75*c.Scale,key)
  s.StopOn=true;s.TargetOn=true;s.Error=nil;s.Overlay=nil;chartView:CancelPlacement()
  if s.Coach==1 then s.Coach=2 end
  refresh()
 end
 local function close(key)s.CloseContract=key;s.Overlay="Close";refresh()end
 -- The ticker list opens as a dropdown anchored to the selector that was clicked (canvas coordinates).
 local function openContracts(anchor)
  if anchor and anchor.Parent and anchor.Parent:IsA("GuiObject") then
   -- Layout geometry, not AbsoluteSize: the click's press animation briefly scales the button.
   local parent=anchor.Parent
   local a=parent.AbsolutePosition+Vector2.new(anchor.Position.X.Offset,anchor.Position.Y.Offset)-canvas.AbsolutePosition
   if parent:IsA("ScrollingFrame") then a-=parent.CanvasPosition end
   s.ContractAnchor={X=a.X,Y=a.Y,W=anchor.Size.X.Offset,H=anchor.Size.Y.Offset}
  else s.ContractAnchor=nil end
  s.Overlay="Contracts";refresh()
 end
 local tradePaths={"OrderTicket.OrderActions.BuyLong","OrderTicket.Fields.BuyLong","TradeDock.BuyLong"}
 local sellPaths={"OrderTicket.OrderActions.SellShort","OrderTicket.Fields.SellShort","TradeDock.SellShort"}
 -- One order in flight at a time: BUY/SELL show "Sending" until the server replies (or 6 s pass).
 -- Success feedback only comes from that server reply.
 -- Every order (ticket BUY/SELL and the chart's right-click menu) goes through this one path: the same
 -- client checks, pending state, toasts and server reply handling. The server re-validates everything.
 local function submitOrder(dir,orderType,price,qty,label)
  if s.PendingOrder then toast("Waiting for the previous order's confirmation…","info");return false end
  local paths=dir>0 and tradePaths or sellPaths
  if type(qty)~="number" or qty~=qty or qty==math.huge or qty<1 or qty%1~=0 then fail("Enter a whole number of contracts, starting at 1.");effect(paths,"Error");return false end
  for _,field in ipairs({"Stop","Target"})do
   if s[field.."On"]then
    local resolved,err=Market.Protection(Market.Contracts[s.Contract],qty,s[field.."Dollars"])
    if not resolved then fail(err);effect(paths,"Error");return false end
   end
  end
  local max=session:MaxOrder(s.Contract,dir)
  if max and qty>max then
   fail("Order too large. Available now: "..max.." "..s.Contract.." contracts.");effect(paths,"Error");return false
  end
  local ok,msg,tab,requestId=session:Place(s.Contract,dir,qty,orderType,price,s.StopOn and s.StopDollars or nil,s.TargetOn and s.TargetDollars or nil,s.Execution or "Immediate")
  if ok then
   s.Error=nil;s.Tab=orderType=="Market"and tab or"Orders";s.Sheet=false
   local pending={Id=requestId,Direction=dir,At=os.clock()};s.PendingOrder=pending
   if fx then fx:Play("Send")end
   toast("Sending "..(label or(dir>0 and"buy"or"sell").." order").." to the exchange…","info")
   task.delay(6,function()
    if alive and s.PendingOrder==pending then s.PendingOrder=nil;fail("No confirmation from the exchange yet. Check Orders before retrying.")end
   end)
   return true
  else fail(msg);effect(paths,"Error")end
  return false
 end
 local function place(dir) submitOrder(dir,s.Type,s.Limit,s.Qty) end
 -- The neutral quantity control respects the account ceiling and the best available side.
 -- Direction-specific capacity (including working orders) is still rechecked on submission.
 local function quantityLimit()
  local row=activeRow()
  -- The displayed balance includes open P&L; sizing must keep using the server cap / settled balance.
  local limit=session.Limit or (row and row.Limit) or Market.ContractLimit(session:Summary().Balance)
  local buy,sell=session:MaxOrder(s.Contract,1),session:MaxOrder(s.Contract,-1)
  if buy~=nil and sell~=nil then limit=math.min(limit,math.max(buy,sell))end
  return math.max(0,math.floor(limit))
 end
 local limitPopupPending=false
 local function quantityLimitPopup(limit)
  s.QuantityLimit=limit;s.QuantitySymbol=s.Contract;s.QuantityAccount=accountName()
  if s.Overlay=="QuantityLimit"or limitPopupPending then return end
  limitPopupPending=true
  -- FocusLost and the clicked + button may both reach here in one input event.
  task.defer(function()
   limitPopupPending=false
   if not alive then return end
   s.Overlay="QuantityLimit";s.Sheet=false;s.Error=nil;refresh()
  end)
 end

 local function info(p,name,x,y,value)
  local b=button(p,name,"i",x,y,22,22,function()s.Overlay="Info";s.Info=value;refresh()end,false,C.Muted,12)
  b.MouseEnter:Connect(function()
   local oldTip=canvas:FindFirstChild("TermTooltip");if oldTip then oldTip:Destroy()end
   local width=math.min(292,root.AbsoluteSize.X-24)
   local pos=b.AbsolutePosition-root.AbsolutePosition
   local tip=frame(canvas,"TermTooltip",math.clamp(pos.X-width/2,12,root.AbsoluteSize.X-width-12),math.clamp(pos.Y+27,10,root.AbsoluteSize.Y-102),width,90,C.Raised,70)
   round(tip);stroke(tip,C.Blue)
   local t=text(tip,"Term",value,12,8,width-24,74,12,C.Text);t.TextWrapped=true
  end)
  b.MouseLeave:Connect(function()local tip=canvas:FindFirstChild("TermTooltip");if tip then tip:Destroy()end end)
  return b
 end
 local function input(p,name,value,x,y,w,h,fn,enabled)
  local o=make("TextBox",name,p,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=C.Bg,BorderSizePixel=0,
   Text=tostring(value),PlaceholderText="Price",TextColor3=enabled==false and C.Muted or C.Text,TextSize=15,Font=N,TextStrokeColor3=SC.Ink,TextStrokeTransparency=.55,ClearTextOnFocus=false,
   TextEditable=enabled~=false,TextXAlignment=Enum.TextXAlignment.Left,ZIndex=p.ZIndex})
  round(o);local edge=stroke(o);make("UIPadding","Padding",o,{PaddingLeft=UDim.new(0,10),PaddingRight=UDim.new(0,10)})
  o.Focused:Connect(function()edge.Color=C.Blue end)
  o.FocusLost:Connect(function()
   if not alive or not o.Parent then return end
   edge.Color=C.Border
   local n=tonumber((o.Text:gsub("[, $]","")))
   if n and n==n and math.abs(n)<1e8 then fn(n);s.Error=nil else s.Error="Enter a valid price."end
   task.delay(.12,refresh)
  end)
  return o
 end
 local function navigate(value,mobile)
  if value=="Shop"then
   -- Shop overlays the current screen; closing it preserves navigation and trading state.
   s.Sheet=false;s.ProtectionDraft=nil;s.Overlay="Shop";refresh();return
  end
  s.Overlay=nil;s.Sheet=false;s.Nav=value;s.Screen=value
  if value=="Review" then s.Screen="Trade";s.Nav="Trade";s.Tab="History";if mobile then s.Sheet="Activity" end end
  refresh()
 end
 local function nav(p,x,y,w,h,mobile)
  local items={"Trade","Progress","Stats","Leaderboard","Shop"}
  for i,value in ipairs(items)do
   local cell=mobile and w/#items or w
   local bx=mobile and x+(i-1)*cell+3 or x
   local by=mobile and y+2 or y+(i-1)*(h+9)
   local bw=mobile and cell-6 or w
   local bh=mobile and h-4 or h
   local selected=s.Nav==value
   local b=button(p,"Nav"..value,"",bx,by,bw,bh,function()navigate(value,mobile)end,Color3.new(1,1,1),C.Text,12,p.ZIndex+2)
   sidebarSurface(b,selected,false);if fx then fx:Selected(b,selected)end
   local iconSize=mobile and math.min(28,bh-22)or math.min(42,bh-8)
   sidebarImage(b,value=="Progress" and "Accounts" or value,mobile and(bw-iconSize)/2 or 11,mobile and 3 or(bh-iconSize)/2,iconSize)
   local label=sidebarText(b,"Label",value,mobile and 2 or iconSize+20,mobile and bh-20 or 0,mobile and bw-4 or bw-iconSize-28,mobile and 18 or bh,mobile and 10 or value=="Leaderboard"and 17 or 21)
   label.TextScaled=true;make("UITextSizeConstraint","NavTextSize",label,{MinTextSize=8,MaxTextSize=mobile and 10 or value=="Leaderboard"and 17 or 21})
   if mobile then label.TextXAlignment=CENTER end
   if selected and not mobile then
    local marker=frame(b,"Selected",3,10,3,bh-20,Color3.new(1,1,1),b.ZIndex+1);round(marker,2)
   end
  end
 end
 local function accountCards(x,y,w,h,mobile)
  local sum=session:Summary();local pf=session.Portfolio
  local panel=frame(canvas,"AccountSummary",x,y,w,h,C.Bg);panel.BackgroundTransparency=1
  local gap=mobile and 8 or 16;local cw=(w-gap*2)/3;local ch=h-8
  for i,d in ipairs({{"Balance","BALANCE",Market.Money(sum.Equity)},{"Unrealized","OPEN PROFIT",Market.Signed(sum.Unrealized)}}) do
   local tile=button(panel,d[1].."Card","",(i-1)*(cw+gap),0,cw,ch,function()s.Overlay="Help";refresh()end,Color3.new(1,1,1))
   summarySurface(tile,d[1],mobile)
   local labelH=mobile and 22 or 18;local valueH=mobile and 28 or 32
   local contentY=math.floor((ch-labelH-4-valueH)/2)
   summaryText(tile,"Label",d[2],8,contentY,cw-16,labelH,mobile and 10 or 15,C.Text,true).TextWrapped=true
   summaryText(tile,d[1].."Value",d[3],8,contentY+labelH+4,cw-16,valueH,mobile and 18 or 32,i==2 and (sum.Unrealized>=0 and SC.Green or SC.Red) or C.Text,true)
  end
  local label,title,progress,amount=objective();local failed=pf and pf.Failed
  local tile=button(panel,"ObjectiveCard","",2*(cw+gap),0,cw,ch,function()if failed then openBlown(pf.Active) else navigate("Progress") end end,Color3.new(1,1,1))
  summarySurface(tile,failed and "Blown" or "Trophy",mobile)
  summaryText(tile,"Label",failed and "ACCOUNT FAILED" or label,8,mobile and 8 or 6,cw-16,mobile and 17 or 16,mobile and 10 or 15,C.Text,true)
  local t=summaryText(tile,"Title",failed and ("Restart · "..whole(pf.StartingBalance or Ladder.StartingBalance)) or title,10,mobile and 25 or 23,cw-20,mobile and 30 or 24,mobile and 13 or 22,C.Text,true);t.TextWrapped=true
  summaryText(tile,"Amount",failed and "Equity fell to $0 or below" or amount,8,ch-(mobile and 28 or 23),cw-16,mobile and 20 or 14,mobile and 9 or 12,C.Text,true)
  local track=frame(tile,"Track",12,ch-7,cw-24,3,SC.Ink,4)
  local fill=frame(track,"Fill",0,0,(cw-24)*progress,3,C.Green,5);fill.Visible=progress>0
 end
 -- The candlestick chart, its navigation and drawing tools live in ChartView (presentation only).
 chartView=ChartView.new({C=C,F=F,M=M,B=B,N=Enum.Font.RobotoMono,Market=Market,Session=session,State=s,Options=options,Root=root,Canvas=canvas,
  frame=frame,text=text,button=button,stroke=stroke,round=round,line=line,dash=dash,rule=rule,panel=panel,
  control=gameControl,gloss=glossy,selector=instrumentSelector,heading=gameHeading,caption=sidebarText,tint=tint,stars=panelStars,
  setPainting=function(pool)painting=pool end,refresh=refresh,toast=toast,openContracts=function(b)openContracts(b)end,
  submitOrder=function(dir,orderType,price,qty,label)return submitOrder(dir,orderType,price,qty,label)end,
  maxOrder=function(key,dir)return session:MaxOrder(key,dir)end,
  onIdle=function(chrome)
   if fullRefreshPending or chrome then fullRefreshPending=false;refresh()else repaintChart()end
  end})
 -- A paint error must never leave the pooled painter installed (every later GUI object would be
 -- routed into the chart pool) or stop later frames. Errors are reported once and the chart recovers.
 local chartFault,faultAt=nil,0
 local function chart(x,y,w,h,mobile,compact,short,updating)
  local ok,err=xpcall(chartView.Paint,debug.traceback,chartView,x,y,w,h,mobile,compact,updating)
  if ok then
   if chartFault then chartFault=nil;root:SetAttribute("ChartError",nil)end
   -- Phones: a slimmer rim leaves more of the screen to candles.
   local p=mobile and not updating and canvas:FindFirstChild("Chart")
   if p and p:FindFirstChild("Border")then p.Border.Thickness=2;p.Corners.CornerRadius=UDim.new(0,14)end
   return
  end
  painting=nil;chartView:Reset()
  local message=tostring(err)
  if message~=chartFault or os.clock()-faultAt>10 then warn("[Get Funded!] Chart paint failed; recovering: "..message)end
  chartFault=message;faultAt=os.clock();root:SetAttribute("ChartError",message:sub(1,200))
  -- Rebuild the chart panel on the next frame (at most once a second while the fault repeats).
  task.delay(updating and 1 or 0,function()if alive then fullRefreshPending=false;refresh()end end)
 end
 repaintChart=function()
  -- The chart keeps updating behind popups; its input surface is blocked while one is open.
  if not alive or not root.Parent then return end
  local p=canvas:FindFirstChild("Chart");if not p then return end
  local w,h=root.AbsoluteSize.X,root.AbsoluteSize.Y
  local mobile=w<1000 or h<600
  chart(p.Position.X.Offset,p.Position.Y.Offset,p.Size.X.Offset,p.Size.Y.Offset,mobile,mobile and(w>h or h<650),false,true)
 end
 local function activity(x,y,w,h,mobile,compact,z)
  local p=frame(canvas,"Activity",x,y,w,h,C.Panel,z);panel(p);panelStars(p);p.ClipsDescendants=true
  local sum=session:Summary();local working=session:Working()
  local tabs={{"Positions","Open positions · "..sum.Count},{"Orders","Orders · "..#working},{"History","Trade history"}}
  local top=compact and 0 or 43
  if not compact then
   local tw=math.min((w-20)/3,186)
   for i,item in ipairs(tabs)do
    local bx=10+(i-1)*tw
    gameControl(button(p,"Tab"..item[1],item[2],bx,5,tw-6,36,function()s.Tab=item[1];refresh()end,C.Panel,C.Text,mobile and 11 or 14),s.Tab==item[1])
    if s.Tab==item[1]then rule(p,bx+8,41,tw-16,C.Blue)end
   end
   rule(p,0,42,w)
  end
  local data={}
  if s.Tab=="Positions"or compact then for _,key in ipairs(Market.PositionOrder)do if session.Positions[key]then table.insert(data,session.Positions[key])end end
  elseif s.Tab=="Orders"then data=working else data=session.History end
  if #data==0 then
   if s.Tab=="Positions"or compact then return end
   local showIcon=not compact and h-top>=108
   local iconSize=showIcon and math.clamp(h-top-69,34,55)or 0
   local titleY=showIcon and top+iconSize+12 or top+10
   -- While the guided-tour card covers the left of the panel, centre the empty state on the right.
   local ex,ew=12,w-24
   if s.Coach and not mobile and not compact then ex=math.floor(w*.58);ew=w-ex-12 end
   if showIcon then sidebarImage(p,s.Tab=="History"and"Review"or"Positions",ex+(ew-iconSize)/2,top+8,iconSize)end
   gameHeading(text(p,"EmptyTitle",s.Tab=="Orders"and"No working orders"or"No closed trades yet",ex,titleY,ew,24,showIcon and 18 or 13,C.Text,B,CENTER))
   return
  end
  local function scroller(name,yy,hh,ch)
   return make("ScrollingFrame",name,p,{Position=UDim2.fromOffset(0,yy),Size=UDim2.fromOffset(w,hh),CanvasSize=UDim2.fromOffset(0,ch),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Muted,ZIndex=p.ZIndex})
  end
  if mobile then
   local rowH=(s.Tab=="Positions"or compact)and 46 or 79
   local list=scroller("Rows",top,h-top,#data*rowH)
   for i,d in ipairs(data)do
    local row=frame(list,"Row"..i,0,(i-1)*rowH,w,rowH,C.Panel)
    if s.Tab=="Positions"or compact then
     text(row,"Symbol",d.Contract,10,3,47,40,11,C.Text,B)
     text(row,"Direction",(d.Direction>0 and"BUY "or"SELL ")..d.Quantity,58,3,64,40,10,d.Direction>0 and C.Green or C.Red,M)
     text(row,"Pnl",Market.Signed(session:Pnl(d)),123,3,w-200,40,11,session:Pnl(d)>=0 and C.Green or C.Red,N,RIGHT)
     glossy(button(row,"Close"..d.Contract,"CLOSE",w-67,3,59,40,function()close(d.Contract)end,C.Raised,C.Text,12),"Pink"):SetAttribute("Sound","Open")
    elseif s.Tab=="Orders"then
     text(row,"Description",d.Contract.." · "..d.Kind,14,7,w-108,24,13,C.Text,M)
     text(row,"Price",(d.Queued and "Executing"or d.Type=="Market"and"Market"or Market.Number(d.Price)).." · "..d.Quantity.." remaining",14,35,w-112,27,12,C.Muted,N)
     local cancel=glossy(button(row,"Cancel"..d.Id..(d.Protection or""),d.Closing and "Closing"or "Cancel",w-96,18,82,44,function()if d.Closing then return end local ok,message=session:Cancel(d.Id,d.Protection);if ok then toast("Cancelling order…","info")else fail(message)end end,C.Raised,C.Text,13),"Navy");cancel.Border.Color=C.Cyan
     if d.Closing then cancel:SetAttribute("Disabled",true);cancel.Active=false;cancel.Selectable=false end
    else
     text(row,"Description",d.Contract.." · "..d.Quantity.." contracts",14,9,w-124,24,13,C.Text,M)
     text(row,"Pnl",Market.Signed(d.Pnl),w-119,9,105,24,14,d.Pnl>=0 and C.Green or C.Red,N,RIGHT)
     text(row,"Details",Market.Number(d.Entry).." → "..Market.Number(d.Exit).." · "..d.Time,14,37,w-28,25,11,C.Muted,N)
    end
    rule(row,8,rowH-1,w-16)
   end
  else
   local cols=s.Tab=="Positions"and{"Market","Side","Qty","Entry","Open profit","Action"}or s.Tab=="Orders"and{"Market","Order","Qty","Price","Status","Action"}or{"Market","Qty","Entry","Exit","Realized profit","Closed"}
   local heading=frame(p,"TableHeader",8,top+2,w-16,28,Color3.new(1,1,1));round(heading,8)
   tint(heading,Color3.fromRGB(96,48,230),Color3.fromRGB(58,26,170));stroke(heading,Color3.fromRGB(150,100,255))
   local fractions={0,.17,.34,.44,.62,.85}
   for i,title in ipairs(cols)do text(p,"Column"..i,title,14+fractions[i]*(w-28),top+3,(w-28)*(i==5 and .23 or .17)-7,25,11,Color3.fromRGB(236,226,255),Enum.Font.FredokaOne)end
   local list=scroller("Rows",top+30,h-top-30,#data*39)
   for i,d in ipairs(data)do
    local row=frame(list,"Row"..i,0,(i-1)*39,w,39,C.Panel);rule(row,0,0,w,C.Grid)
    local vals,positive
    if s.Tab=="Positions"then positive=session:Pnl(d)>=0;vals={d.Contract,d.Direction>0 and"BUY"or"SELL",tostring(d.Quantity),Market.Number(d.Entry),Market.Signed(session:Pnl(d))}
    elseif s.Tab=="Orders"then vals={d.Contract.."Z26",d.Kind,tostring(d.Quantity),d.Type=="Market"and"Market"or Market.Number(d.Price),d.Status or "Working"}
    else positive=d.Pnl>=0;vals={d.Contract.."Z26",tostring(d.Quantity),Market.Number(d.Entry),Market.Number(d.Exit),Market.Signed(d.Pnl),d.Time}end
    for j,value in ipairs(vals)do text(row,"Cell"..j,value,14+fractions[j]*(w-28),2,(w-28)*(j==5 and .23 or .17)-7,35,11,j==5 and positive~=nil and(positive and C.Green or C.Red)or C.Text,j>=3 and N or M)end
    if s.Tab~="History"then
     local positions=s.Tab=="Positions"
    local b=glossy(button(row,"Action"..i,positions and"CLOSE"or d.Closing and"Closing"or"Cancel",14+.85*(w-28),5,(w-28)*.15-10,29,function()
     if not positions and d.Closing then return end
      if positions then close(d.Contract)else local ok,message=session:Cancel(d.Id,d.Protection);if ok then toast("Cancelling order…","info")else fail(message)end end
     end,C.Raised,C.Text,12),positions and"Pink"or"Navy")
     if positions then b:SetAttribute("Sound","Open")else b.Border.Color=C.Cyan end
     if not positions and d.Closing then b:SetAttribute("Disabled",true);b.Active=false;b.Selectable=false end
    end
   end
  end
 end
 local function tradeButtons(p,x,y,w,bh,stacked)
  bh=bh or 48
  -- Equal actions: side by side, or stacked in the phone landscape column.
  local bw=stacked and w or(w-10)/2
  local pending=s.PendingOrder
  for i,d in ipairs({{1,"BuyLong",s.Type=="Limit"and"↑ LIMIT BUY"or"↑ BUY",C.Buy},{-1,"SellShort",s.Type=="Limit"and"↓ LIMIT SELL"or"↓ SELL",C.Sell}})do
   local enabled=options.Preview or session.CanTrade
   if pending then d[3]=pending.Direction==d[1]and"SENDING…"or d[3]end
   local ox,oy=stacked and 0 or(i-1)*(bw+10),stacked and(i-1)*(bh+8)or 0
   local b=button(p,d[2],d[3],x+ox,y+oy,bw,bh,function()if enabled then place(d[1])end end,enabled and d[4]or C.Raised,enabled and C.Text or C.Muted,16)
   b.Active=enabled;b.Selectable=enabled;b.Font=B;b.TextSize=20;b.Corners.CornerRadius=UDim.new(0,11)
   if enabled then
    b.BackgroundColor3=Color3.new(1,1,1);b:SetAttribute("RestingColor",Color3.new(1,1,1))
    tint(b,d[1]>0 and Color3.fromRGB(34,253,158)or Color3.fromRGB(255,120,168),d[1]>0 and Color3.fromRGB(0,173,112)or Color3.fromRGB(231,40,99))
    local shine=frame(b,"Shine",8,4,bw-16,3,Color3.new(1,1,1),b.ZIndex);shine.BackgroundTransparency=.35;round(shine,2)
   else tint(b)end
   b.TextTransparency=1;b.TextStrokeTransparency=1
   local label=text(b,"ActionLabel",d[3],5,0,bw-10,bh,bh>=50 and 22 or 20,enabled and C.Text or C.Muted,B,CENTER,b.ZIndex+1)
   label.TextStrokeTransparency=1
   label.TextScaled=true;make("UITextSizeConstraint","TextSize",label,{MinTextSize=10,MaxTextSize=bh>=50 and 22 or 20})
   make("UIStroke","TextOutline",label,{Color=d[1]>0 and Color3.fromRGB(0,132,84)or Color3.fromRGB(174,24,75),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual})
   b.Border.Thickness=3;b.Border.Color=enabled and(d[1]>0 and Color3.fromRGB(129,255,202)or Color3.fromRGB(255,168,197))or C.Border
   b:SetAttribute("Direction",d[1]);b:SetAttribute("Sound","None");b:SetAttribute("Debounce",.3)
   if pending then
    -- Waiting for the exchange: both sides are locked so a double click can never send twice.
    b:SetAttribute("Disabled",true)
    if pending.Direction~=d[1]then label.TextTransparency=.45 end
    if fx then
     local shine=b:FindFirstChild("Shine")
     if shine then fx:Loop(TweenService:Create(shine,TweenInfo.new(.45,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{BackgroundTransparency=.05}))end
    end
   end
  end
 end
 -- Dollar intentions persist when quantity/instrument changes; only the derived ticks/prices change.
 local function protectionValue(field,draft)
  local source=draft or s
  return Market.Protection(Market.Contracts[s.Contract],s.Qty,source[field.."Dollars"])
 end
 local function protectionMaximum()
  local c=Market.Contracts[s.Contract]
  return c.Tick*c.Multiplier*s.Qty*10000
 end
 local function effective(field,draft)
  local v=protectionValue(field,draft)
  return v and Market.Money(v.Dollars)or"Invalid amount"
 end
 local function updateProtectionReadout()
  local entry=s.Type=="Market"and session.Prices[s.Contract]or s.Limit
  for _,key in ipairs({"Stop","Target"})do
   for _,dir in ipairs({1,-1})do
    local p=s[key.."On"]and Market.Protection(Market.Contracts[s.Contract],s.Qty,s[key.."Dollars"],entry,dir,key)
    root:SetAttribute(key..(dir==1 and"BuyPrice"or"SellPrice"),p and p.Price or nil)
    root:SetAttribute(key.."EffectiveDollars",p and p.Dollars or nil)
   end
  end
 end
 local protectionCommits={}
 local function openProtection()
  protectionCommits={}
  s.ProtectionDraft={StopOn=s.StopOn,TargetOn=s.TargetOn,StopDollars=s.StopDollars,TargetDollars=s.TargetDollars}
  s.Sheet=false;s.Overlay="Protection";s.Error=nil;refresh()
 end
 local function saveProtectionPreferences(value)
  local ok,message=session:SetProtectionPreferences(value or s)
  if not ok then fail(message)end
  return ok
 end
 local function closeProtection()
  local draft=s.ProtectionDraft
  if draft then
   for _,commit in ipairs(protectionCommits)do if not commit()then return end end
   if not saveProtectionPreferences(draft)then return end
   for _,key in ipairs({"StopOn","TargetOn","StopDollars","TargetDollars"})do s[key]=draft[key]end
  end
  protectionCommits={};s.ProtectionDraft=nil;s.Overlay=nil;s.Error=nil;refresh()
 end
 local function numericStepper(p,name,x,y,w,value,step,minimum,maximum,setter,formatter,enabled,direct,onExceeded)
  local height=direct and 52 or 44;local bw=direct and 0 or math.min(44,math.floor((w-32)/2))
  local shell=frame(p,name,x,y,w,height,C.Bg,p.ZIndex);round(shell,10);stroke(shell,Color3.fromRGB(26,99,212)).Thickness=2
  local current=value
  local function upperBound()return type(maximum)=="function"and maximum()or maximum end
  local field=make("TextBox","Value",shell,{Position=UDim2.fromOffset(bw,0),Size=UDim2.fromOffset(w-bw*2,height),BackgroundTransparency=1,
   Text=formatter and formatter(value)or tostring(value),TextColor3=enabled==false and C.Muted or C.Text,Font=B,TextSize=24,TextScaled=true,TextStrokeColor3=SC.Ink,TextStrokeTransparency=.55,
   ClearTextOnFocus=false,TextEditable=enabled~=false,BorderSizePixel=0,ZIndex=shell.ZIndex+1})
  make("UITextSizeConstraint","TextSize",field,{MinTextSize=10,MaxTextSize=24})
  local function display(n)return formatter and formatter(n)or tostring(n)end
  local function commit()
   if enabled==false then return true end
   local maximum=upperBound()
   local lower=math.min(minimum,maximum)
   local n=tonumber((field.Text:gsub("[, $]","")))
   if onExceeded and n and n==n and math.abs(n)<math.huge and n>maximum then
    current=maximum;field.Text=display(current);setter(current);s.Error=nil;onExceeded(maximum);return false
   end
   if not n or n~=n or math.abs(n)==math.huge or n<lower or n>maximum or(step==1 and n%1~=0)then
    s.Error=step==1 and(maximum<minimum and "No contracts available for this order."or "Enter a whole number from "..minimum.." to "..maximum..".")or"Enter an amount greater than $0."
    field.Text=display(current);fail(s.Error);if fx then fx:Shake(shell)end;return false
   end
   n=math.clamp(math.round(n/step)*step,lower,maximum)
   current=n;field.Text=display(n);setter(n);s.Error=nil;return true
  end
  field.FocusLost:Connect(function()
   if not commit()then return end
   -- Keep the clicked control alive when an input loses focus to a button.
   updateProtectionReadout()
  end)
  for _,d in ipairs(direct and {} or {{"Decrease","−",-1,0},{"Increase","+",1,w-bw}})do
   local control=gameControl(button(shell,d[1],d[2],d[4],0,bw,height,function()
    if enabled==false or not commit()then return end
    local maximum=upperBound()
    local requested=math.round((current+d[3]*step)/step)*step
    current=math.clamp(requested,math.min(minimum,maximum),maximum)
    if onExceeded and requested>maximum then
     field.Text=display(current);setter(current);s.Error=nil;onExceeded(maximum);return
    end
    field.Text=display(current);setter(current);s.Error=nil;refresh()
   end,C.Raised,C.Text,23,shell.ZIndex+1),true)
   control.Active=enabled~=false;control.Selectable=enabled~=false
   control:SetAttribute("Sound","Tick");control:SetAttribute("Debounce",.05)
   if enabled==false then control.ControlLabel.TextColor3=C.Muted end
  end
  if fx then fx:Bump(field,field.Text)end
  return shell,commit
 end
 local function quantity(p,x,y,w)
  local maximum=quantityLimit()
  s.Qty=math.clamp(s.Qty,math.min(1,maximum),maximum)
  numericStepper(p,"Quantity",x,y,w,s.Qty,1,1,quantityLimit,function(n)s.Qty=n;if s.Coach==2 then s.Coach=3 end end,nil,true,false,quantityLimitPopup)
 end
 local function protectionIcon(p,key,x,y,size)
  local color=key=="Stop"and C.Red or C.Green
  local box=frame(p,"Icon"..key,x,y,size,size,C.Bg,p.ZIndex+1);box.BackgroundTransparency=1
  if key=="Target"then
   local ring=frame(box,"Ring",2,2,size-4,size-4,C.Bg,box.ZIndex);ring.BackgroundTransparency=1;round(ring,size);stroke(ring,color).Thickness=3
   local dot=frame(box,"Bullseye",size*.37,size*.37,size*.26,size*.26,color,box.ZIndex);round(dot,size)
   line(box,"Arrow",size*.65,size*.35,size*.94,size*.06,color,3,box.ZIndex)
  else
   local tip=frame(box,"ShieldTip",size*.2,size*.3,size*.6,size*.6,color,box.ZIndex);tip.Rotation=45;round(tip,3)
   local top=frame(box,"Shield",size*.1,size*.12,size*.8,size*.58,color,box.ZIndex);round(top,4)
   local gleam=frame(top,"Gleam",size*.1,size*.05,size*.22,size*.4,Color3.fromRGB(255,157,177),box.ZIndex+1);round(gleam,2)
  end
 end
 local function protectionSwitch(p,key,x,y,w,h,on,fn,z)
  local b=button(p,"Toggle","",x,y,w,h,fn,false,C.Text,12,z)
  local trackH=math.min(32,h-8)
  local track=frame(b,"Track",0,(h-trackH)/2,w,trackH,Color3.new(1,1,1),b.ZIndex)
  local accent=key=="Stop"and C.Red or C.Green
  round(track,trackH/2);stroke(track,on and accent or C.Border).Thickness=2
  local colors=on and(key=="Stop"and GLOSS.Red or GLOSS.Green)or GLOSS.Navy;tint(track,colors[1],colors[2])
  local diameter=trackH-6
  local knob=frame(track,"Knob",on and w-diameter-3 or 3,3,diameter,diameter,on and C.Text or C.Muted,b.ZIndex+1)
  round(knob,diameter/2)
  b:SetAttribute("On",on)
  return b
 end
 local function protectionCards(p,x,y,w)
  local stacked=w<400 local gap=10
  local cw=stacked and w or(w-gap)/2 local ch=98
  for i,d in ipairs({{"Stop","Stop loss ($)",C.Red},{"Target","Take profit ($)",C.Green}})do
   local key=d[1];local enabled=s[key.."On"]
   local cx=stacked and x or x+(i-1)*(cw+gap) local cy=stacked and y+(i-1)*(ch+gap)or y
   local card=frame(p,key.."Card",cx,cy,cw,ch,C.Bg,p.ZIndex);round(card,12);stroke(card,d[3]).Thickness=3
   local header=button(card,"Settings","",6,4,cw-64,30,openProtection,false,C.Text,12,card.ZIndex+1)
   protectionIcon(header,key,3,5,20)
   local label=sidebarText(header,"Label",d[2],29,0,cw-95,30,16);label.TextScaled=true
   make("UITextSizeConstraint","TextSize",label,{MinTextSize=12,MaxTextSize=16})
   local function toggleProtection()s[key.."On"]=not s[key.."On"];saveProtectionPreferences();refresh()end
   protectionSwitch(card,key,cw-54,3,44,34,enabled,toggleProtection,card.ZIndex+1)
   numericStepper(card,"Distance",8,38,cw-16,s[key.."Dollars"],.01,.01,protectionMaximum,function(n)s[key.."Dollars"]=n;saveProtectionPreferences();updateProtectionReadout()end,Market.Money,enabled,true)
  end
  return stacked and ch*2+gap or ch
 end

 local function orderOptions(p,w,startY,withQuantity)
  local pad=16;local iw=w-32;local yy=startY or 12
  local narrow=iw<260
  local function heading(name,value,y,width) return gameHeading(text(p,name,value,pad,y,width or iw,22,narrow and 15 or 16,C.Text,B)) end
  heading("OrderTypeLabel","Order type",yy);yy+=26
  local seg=frame(p,"OrderType",pad,yy,iw,42,C.Bg,p.ZIndex);seg.BackgroundTransparency=1
  for i,kind in ipairs({"Market","Limit"})do
   gameControl(button(seg,kind,kind,(i-1)*(iw+8)/2,0,(iw-8)/2,42,function()s.Type=kind;s.Error=nil;refresh()end,C.Panel,C.Text,17,seg.ZIndex),s.Type==kind)
  end
  yy+=46
  local hint=sidebarText(p,"OrderExplanation",s.Type=="Market"and"Trades now at available prices"or"Trades at your price or better",pad,yy,iw,20,narrow and 12 or 13,C.Muted);hint.TextXAlignment=CENTER
  hint.TextWrapped=true;yy+=30
  heading("ExecutionLabel","Execution",yy);yy+=26
  local modes=frame(p,"ExecutionMode",pad,yy,iw,38,C.Bg,p.ZIndex);modes.BackgroundTransparency=1
  for i,mode in ipairs({{"Immediate","Standard"},{"Sliced","In slices"}})do
   gameControl(button(modes,mode[1],mode[2],(i-1)*(iw+8)/2,0,(iw-8)/2,38,function()s.Execution=mode[1];s.Error=nil;refresh()end,C.Panel,C.Text,15,modes.ZIndex),(s.Execution or "Immediate")==mode[1])
  end
  yy+=42
  local detail=s.Execution=="Sliced"and "Fills gradually. Cancel the remainder in Orders."or s.Type=="Market"and "Fills now within execution limits; unfilled quantity is cancelled."or "Matches now when possible; eligible remainder rests at your limit."
  local executionHint=sidebarText(p,"ExecutionExplanation",detail,pad,yy,iw,40,12,C.Muted);executionHint.TextWrapped=true;yy+=46
  if s.Type=="Limit"then
   heading("LimitLabel","Limit price",yy);yy+=28
   local tick=Market.Contracts[s.Contract].Tick
   numericStepper(p,"LimitPrice",pad,yy,iw,s.Limit,tick,tick,99999999,function(n)s.Limit=Market.Snap(n,s.Contract)end,Market.Number);yy+=52
   local current=text(p,"CurrentPrice","Current "..Market.Number(session.Prices[s.Contract]),pad,yy,iw-114,30,12,C.Muted,N)
   current.TextScaled=true;make("UITextSizeConstraint","TextSize",current,{MinTextSize=9,MaxTextSize=12})
   local use=gameControl(button(p,"UseCurrent","Use current",w-pad-106,yy,106,30,function()s.Limit=Market.Snap(session.Prices[s.Contract],s.Contract);s.Error=nil;refresh()end,C.Panel,C.Text,12),false)
   use.Border.Color=C.Cyan;yy+=46
  end
  if withQuantity then
   heading("QtyLabel","Quantity",yy,iw)
   yy+=28
   quantity(p,pad,yy,iw);yy+=56
  end
  heading("ProtectionLabel","Trade protection",yy+4,iw)
  yy+=38;yy+=protectionCards(p,pad,yy,iw)+6
  -- Errors use the readable overlay toast; they never insert height above order actions.
  return yy
 end
 local function level2(parent,x,y,w,resize)
  local view=Level2View.new({button=button,gloss=glossy,number=Market.Number,levels=Market.DepthLevels,
   scale=function(value)if value then depthScales[s.Contract]=value end;return depthScales[s.Contract]or 16 end,
   quantity=function(n)return Market.Number(n):gsub("%.00$","")end,
   expanded=function()return s.Level2Expanded end,
   toggle=function()s.Level2Expanded=not s.Level2Expanded end,
   data=function()
    local fresh=session.DepthReceivedAt and os.clock()-session.DepthReceivedAt<8 and session.DepthLive==true
    local quote=session.DepthContract==s.Contract and session.Quotes[s.Contract]or nil
    return session.DepthAccess or {Allowed=false,State=options.Preview and "Unconfigured"or "Checking"},quote,fresh
   end,
   openShop=function()s.Sheet=false;s.ProtectionDraft=nil;s.Overlay="Shop";refresh()end,
   resize=resize},parent,x,y,w)
  table.insert(depthViews,view);return view
 end
 local function updateLevel2()for _,view in ipairs(depthViews)do view:Update()end end
 local function updateTicketPosition(p,w)
  local actionParent=p.OrderActions;local iw=w-32;local yy=68
  for _,name in ipairs({"Position","Pnl","ClosePosition"})do local old=actionParent:FindFirstChild(name);if old then old:Destroy()end end
  local held=session.Positions[s.Contract]
  if held then
   local closeW=math.min(124,math.floor(iw*.44));local infoW=iw-closeW-10
   text(actionParent,"Position",(held.Direction>0 and"Long "or"Short ")..held.Quantity.." "..held.Contract,16,yy,infoW,17,12,held.Direction>0 and C.Green or C.Red,B)
   local pnl=text(actionParent,"Pnl",Market.Signed(session:Pnl(held)),16,yy+17,infoW,19,17,session:Pnl(held)>=0 and C.Green or C.Red,N)
   pnl.TextScaled=true;make("UITextSizeConstraint","TextSize",pnl,{MinTextSize=10,MaxTextSize=17})
   local closing=s.PendingClose and s.PendingClose.Contract==held.Contract
   local cb=glossy(button(actionParent,"ClosePosition",closing and"Closing…"or"Close position",w-16-closeW,yy,closeW,36,function()if not s.PendingClose then close(held.Contract)end end,C.Raised,C.Text,12),"Pink")
   cb:SetAttribute("Sound","Open");if closing then cb:SetAttribute("Disabled",true)end
  end
 end
 local function retainedQuantity(p)
  local quantity=p:FindFirstChild("Quantity",true)
  if quantity and not quantity.Value:IsFocused()then quantity.Value.Text=tostring(s.Qty)end
 end
 local function ticket(x,y,w,h)
  if preservedTicket and preservedTicket.Name=="OrderTicket"then
   updateTicketPosition(preservedTicket,w);retainedQuantity(preservedTicket);return
  end
  local p=frame(canvas,"OrderTicket",x,y,w,h,C.Panel);panel(p,C.Blue);panelStars(p);p.ClipsDescendants=true
  p:SetAttribute("TradingEnabled",options.Preview or session.CanTrade)
  local held=session.Positions[s.Contract];local iw=w-32
  gameHeading(text(p,"Title","Place a trade",18,12,iw,34,w<300 and 24 or 27,C.Text,B))
  sidebarText(p,"Subtitle",tradeAccountName(),18,46,iw,20,13,C.Muted)
  -- Keep order actions reachable while the longer Limit form scrolls.
  local fixed=true
  local footerH=108 -- compact, stable actions: fills/closures do not move BUY/SELL
  local sc=make("ScrollingFrame","Fields",p,{Position=UDim2.fromOffset(0,78),Size=UDim2.fromOffset(w,fixed and h-86-footerH or h-86),
   CanvasSize=UDim2.new(),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Blue,ZIndex=p.ZIndex})
  local selector=instrumentSelector(sc,s.Contract.."  ·  "..Market.Contracts[s.Contract].Short,16,2,iw,46,function(b)openContracts(b)end,15)
  selector.ControlLabel.TextTruncate=Enum.TextTruncate.AtEnd
  local yy=orderOptions(sc,w,60,true)
  local depthY=yy
  local depth=level2(sc,16,depthY,iw,function(height)sc.CanvasSize=UDim2.fromOffset(0,depthY+height+10)end)
  yy=depthY+depth.Height+10
  local actionParent=sc
  if fixed then
   sc.CanvasSize=UDim2.fromOffset(0,yy+6)
   actionParent=frame(p,"OrderActions",0,h-footerH,w,footerH,C.Panel,p.ZIndex+1);actionParent.BackgroundTransparency=1;yy=0
  end
  tradeButtons(actionParent,16,yy+4,iw,52);yy+=60
  yy+=8
  updateTicketPosition(p,w)
  yy+=40
  if not fixed then sc.CanvasSize=UDim2.fromOffset(0,yy)end
 end
 -- Phone trade controls ("Arcade Clean"). Compact summaries of the existing settings; every control
 -- uses the same handlers as the desktop ticket.
 local function riskSummary()
  local function part(tag,key)return tag.." "..(s[key.."On"]and whole(s[key.."Dollars"])or"off")end
  return part("SL","Stop").." · "..part("TP","Target")
 end
 local function quantityCaption()
  return (s.Type=="Limit"and("Qty · Limit "..Market.Number(s.Limit))or"Quantity")..(s.Execution=="Sliced"and " · Sliced"or "")
 end
 -- Retained dock refreshes are only safe while everything the dock displays is unchanged.
 local function dockKey()
  local held=session.Positions[s.Contract]
  return table.concat({held and(tostring(held.Id)..":"..held.Direction..":"..held.Quantity)or"flat",tostring(s.PendingClose and s.PendingClose.Contract),
   tostring(s.PendingOrder and s.PendingOrder.Direction),s.Type,s.Execution or "Immediate",tostring(s.Limit),riskSummary()},"|")
 end
 -- Shown only while the selected market has an open position: side, quantity, live P&L and Close.
 local function positionBar(p,x,y,w,h)
  local held=session.Positions[s.Contract];if not held then return end
  local long=held.Direction>0
  local bar=frame(p,"PositionBar",x,y,w,h,Color3.new(1,1,1),p.ZIndex+1);round(bar,12)
  stroke(bar,long and Color3.fromRGB(46,214,150)or Color3.fromRGB(240,80,130)).Thickness=1.5
  tint(bar,Color3.fromRGB(6,46,120),Color3.fromRGB(3,28,80))
  local closeW=math.clamp(math.floor(w*.32),84,112)
  -- The summary opens Activity (all positions, working orders and history); Close asks to confirm.
  local info=button(bar,"OpenActivity","",0,0,w-closeW-4,h,function()s.Sheet="Activity";s.Tab="Positions";refresh()end,false,C.Text,12,bar.ZIndex+1)
  info:SetAttribute("Sound","Open")
  local iw=w-closeW-18
  local side=text(info,"Position",(long and"LONG "or"SHORT ")..held.Quantity..(w>=300 and" "..held.Contract or""),10,0,math.floor(iw*.52),h,14,long and C.Green or C.Red,B,nil,info.ZIndex+1)
  side.TextScaled=true;make("UITextSizeConstraint","TextSize",side,{MinTextSize=9,MaxTextSize=14})
  local value=session:Pnl(held)
  local pnl=text(info,"Pnl",Market.Signed(value),10+math.floor(iw*.52),0,math.ceil(iw*.48),h,16,value>=0 and C.Green or C.Red,N,RIGHT,info.ZIndex+1)
  pnl.TextScaled=true;make("UITextSizeConstraint","TextSize",pnl,{MinTextSize=9,MaxTextSize=16})
  local closing=s.PendingClose and s.PendingClose.Contract==held.Contract
  local cb=glossy(button(bar,"ClosePosition",closing and"Closing…"or"Close",w-closeW,0,closeW,h,function()if not s.PendingClose then close(held.Contract)end end,C.Raised,C.Text,15,bar.ZIndex+1),"Pink")
  cb.Corners.CornerRadius=UDim.new(0,12)
  cb:SetAttribute("Sound","Open");if closing then cb:SetAttribute("Disabled",true)end
 end
 -- Stop loss / take profit defaults are saved when the popup closes.
 local function riskControls(p,x,y,w,h)
  local b=button(p,"RiskControls","",x,y,w,h,openProtection,Color3.new(1,1,1),C.Text,12,p.ZIndex+1)
  b.Corners.CornerRadius=UDim.new(0,12);b.Border.Color=Color3.fromRGB(38,104,206);b.Border.Thickness=1.5
  tint(b,Color3.fromRGB(8,52,134),Color3.fromRGB(4,30,86))
  b:SetAttribute("Sound","Open")
  local iconSize=math.clamp(h-30,18,26)
  protectionIcon(b,"Stop",9,math.floor((h-iconSize)/2),iconSize)
  local tx=iconSize+17;local tw=w-tx-22
  local title=sidebarText(b,"Label","Risk controls",tx,math.floor(h/2)-17,tw,18,14);title.ZIndex=b.ZIndex+2
  local detail=text(b,"RiskSummary",riskSummary(),tx,math.floor(h/2)+2,tw,15,11,SB.Muted,F,nil,b.ZIndex+2)
  detail.TextScaled=true;make("UITextSizeConstraint","TextSize",detail,{MinTextSize=8,MaxTextSize=11})
  local chevron=frame(b,"Chevron",w-18,math.floor(h/2)-7,10,14,C.Bg,b.ZIndex+2);chevron.BackgroundTransparency=1
  line(chevron,"Upper",2,2,8,7,C.Text,2.5,chevron.ZIndex);line(chevron,"Lower",8,7,2,12,C.Text,2.5,chevron.ZIndex)
  return b
 end
 local function mobileDock(x,y,w,h,wide,dims)
  if preservedTicket and preservedTicket.Name=="TradeDock"then retainedQuantity(preservedTicket);return end
  local shell=frame(canvas,"TradeDock",x,y,w,h,Color3.new(1,1,1),10);shell.BackgroundTransparency=1
  shell:SetAttribute("TradingEnabled",options.Preview or session.CanTrade);shell:SetAttribute("DockKey",dockKey())
  local held=session.Positions[s.Contract]
  local gap=8
  if wide then
   -- Landscape column: BUY/SELL stay pinned at the bottom; position, quantity and risk scroll if needed.
   shell.BackgroundTransparency=0;round(shell,14);stroke(shell,Color3.fromRGB(26,88,186)).Thickness=1.5
   tint(shell,Color3.fromRGB(6,46,120),Color3.fromRGB(3,28,80));shell.ClipsDescendants=true
   local pad=6;local iw=w-pad*2
   -- A caption row above the stepper only when there is height to spare; otherwise "Qty" sits beside it.
   local captionAbove=h>=262
   local fixed=(held and 44+gap or 0)+(captionAbove and 18 or 0)+44+6+44
   -- Stacked BUY/SELL as approved; very short screens keep them side by side so nothing scrolls away.
   local stacked=h>=pad*2+fixed+gap+44*2+gap
   local bh=stacked and math.clamp(math.floor((h-pad*2-fixed-gap*2)/2),44,52)or 46
   local actionsH=stacked and bh*2+gap or bh
   local fields=make("ScrollingFrame","Fields",shell,{Position=UDim2.fromOffset(0,pad),Size=UDim2.fromOffset(w,h-pad*2-actionsH-gap),
    CanvasSize=UDim2.new(),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Cyan,ZIndex=11})
   local yy=0
   if held then positionBar(fields,pad,yy,iw,44);yy+=44+gap end
   if captionAbove then
    local caption=sidebarText(fields,"QtyLabel",quantityCaption(),pad+2,yy,iw-4,18,13);caption.ZIndex=12;yy+=18
    quantity(fields,pad,yy,iw)
   else
    local caption=sidebarText(fields,"QtyLabel","Qty",pad+2,yy,34,44,13);caption.ZIndex=12
    quantity(fields,pad+38,yy,iw-38)
   end
   yy+=44+6
   riskControls(fields,pad,yy,iw,44);yy+=44
   fields.CanvasSize=UDim2.fromOffset(0,yy)
   tradeButtons(shell,pad,h-pad-actionsH,iw,bh,stacked)
  else
   -- Portrait: optional live position row, then Quantity beside Risk controls, then BUY and SELL.
   local yy=0
   if held then positionBar(shell,0,0,w,44);yy=50 end
   local rowH,bh=dims.Row,dims.Button
   local half=math.floor((w-gap)/2)
   local card=frame(shell,"QuantityCard",0,yy,half,rowH,Color3.new(1,1,1),11);round(card,12);stroke(card,Color3.fromRGB(26,88,186)).Thickness=1.5
   tint(card,Color3.fromRGB(6,46,120),Color3.fromRGB(3,28,80))
   local caption=sidebarText(card,"QtyLabel",quantityCaption(),9,3,half-18,rowH-50,rowH>=64 and 13 or 12);caption.ZIndex=12
   quantity(card,5,rowH-46,half-10)
   riskControls(shell,half+gap,yy,w-half-gap,rowH)
   tradeButtons(shell,0,h-bh,w,bh)
  end
 end

 local function protectionPopup(w,h)
  local draft=s.ProtectionDraft
  if not draft then closeProtection();return end
  local pw=math.min(530,w-28);local ph=math.min(404,h-28);local narrow=pw<390;local short=ph<400
  local shell=frame(canvas,"ProtectionDialog",(w-pw)/2,(h-ph)/2,pw,ph,Color3.new(1,1,1),41)
  round(shell,20);stroke(shell,C.Cyan).Thickness=4;tint(shell,Color3.fromRGB(43,30,184),Color3.fromRGB(3,43,110));panelStars(shell)
  local headerH=short and 66 or narrow and 90 or 103
  sidebarImage(shell,"Settings",14,short and 8 or 17,short and 32 or narrow and 39 or 52)
  sidebarText(shell,"Title","Trade protection",short and 54 or narrow and 61 or 78,short and 6 or 18,pw-(short and 112 or narrow and 117 or 140),34,short and 24 or narrow and 24 or 32)
  local sub=text(shell,"Subtitle","Total amounts for this order",16,headerH-(short and 26 or 34),pw-32,24,narrow and 12 or 15,C.Text);sub.TextXAlignment=CENTER
  dismissButton(shell,pw-56,14,42,closeProtection,43)
  local footerH=32
  local fields=make("ScrollingFrame","Fields",shell,{Position=UDim2.fromOffset(12,headerH),Size=UDim2.fromOffset(pw-24,ph-headerH-footerH),
   CanvasSize=UDim2.fromOffset(0,256),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Cyan,ZIndex=42})
  protectionCommits={}
  local cw=pw-36
  for i,d in ipairs({{"Stop","Stop loss ($)","",C.Red},{"Target","Take profit ($)","",C.Green}})do
   local key=d[1];local on=draft[key.."On"]
   local card=frame(fields,key.."Protection",5,(i-1)*128+4,cw,114,C.Bg,42);round(card,14);stroke(card,d[4]).Thickness=3
   protectionIcon(card,key,12,13,27)
   sidebarText(card,"Title",d[2],48,7,cw-136,38,narrow and 14 or 22)
   local function toggleProtection()draft[key.."On"]=not draft[key.."On"];refresh()end
   protectionSwitch(card,key,cw-78,4,65,44,on,toggleProtection,43)
   local _,commit=numericStepper(card,"Distance",16,52,cw-32,draft[key.."Dollars"],.01,.01,protectionMaximum,function(n)draft[key.."Dollars"]=n;updateProtectionReadout()end,Market.Money,on,true)
   table.insert(protectionCommits,commit)

  end
  local footer=frame(shell,"Actions",14,ph-footerH,pw-28,footerH-6,C.Panel,43);footer.BackgroundTransparency=1
  text(footer,"Scope",narrow and"Next order · fills may vary"or"Next order · prices round to ticks · fills may vary",0,0,pw-28,23,13,C.Text,F,CENTER)
 end
 -- Shared popup chrome (reference popups): cyan-rimmed gradient shell, purple header band with a
 -- colorful icon and outlined title, and a red close button. Content scrolls when the screen is short.
 -- opts.Plain: concentric corners, no decorative stars and an evenly inset close button.
 local function popupShell(w,h,pw,contentH,title,iconKind,subtitle,opts)
  local plain=opts and opts.Plain
  local narrow=pw<380
  local headH=subtitle and(narrow and 76 or 84)or(narrow and 60 or 66)
  local top=headH+20
  local ph=top+contentH+10
  local viewH=math.min(ph,h-24)
  local shell=frame(canvas,"Dialog",(w-pw)/2,(h-viewH)/2,pw,viewH,Color3.new(1,1,1),41)
  round(shell,22);stroke(shell,Color3.fromRGB(4,221,255)).Thickness=4
  tint(shell,Color3.fromRGB(6,56,147),Color3.fromRGB(3,30,83))
  local rim=frame(shell,"InnerRim",5,5,pw-10,viewH-10,Color3.new(1,1,1),41);rim.BackgroundTransparency=1
  round(rim,plain and 17 or 18);stroke(rim,Color3.fromRGB(31,125,255)).Thickness=2
  local hero=frame(shell,"Header",9,9,pw-18,headH,Color3.new(1,1,1),42)
  round(hero,plain and 14 or 16);stroke(hero,Color3.fromRGB(168,100,255)).Thickness=3
  tint(hero,Color3.fromRGB(150,70,255),Color3.fromRGB(84,32,232));if not plain then panelStars(hero)end
  local iconSize=plain and(narrow and 38 or 48)or math.min(52,headH-16);local tx=16
  if iconKind=="Alert"then alertBadge(hero,14,math.floor((headH-iconSize*.8)/2),math.floor(iconSize*.8),45);tx=iconSize+14
  elseif iconKind then sidebarImage(hero,iconKind,plain and 12 or 10,(headH-iconSize)/2,iconSize);tx=iconSize+(plain and 24 or 20)end
  local closeSize=narrow and 38 or 42
  local closeInset=plain and math.floor((headH-closeSize)/2)or 10
  local tw=pw-18-tx-closeSize-closeInset-12
  local t=sidebarText(hero,"Title",title,tx,subtitle and 8 or 0,tw,subtitle and 40 or headH,narrow and 22 or 27)
  t.ZIndex=45
  if subtitle then local sub=sidebarText(hero,"Subtitle",subtitle,tx,headH-34,tw,24,narrow and 11 or 13,Color3.fromRGB(236,227,255));sub.ZIndex=45 end
  dismissButton(hero,pw-18-closeSize-closeInset,(headH-closeSize)/2,closeSize,function()s.ProtectionDraft=nil;s.Overlay=nil;refresh()end,46)
  local content=make("ScrollingFrame","Content",shell,{Position=UDim2.fromOffset(0,top),Size=UDim2.fromOffset(pw,viewH-top-6),
   CanvasSize=UDim2.fromOffset(pw,contentH),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=C.Cyan,ZIndex=43})
  return shell,content
 end
 -- A selectable row: purple (or cyan) glossy when selected, deep navy otherwise.
 local function option(p,name,x,y,ow,oh,selected,fn,cyan)
  local b=button(p,name,"",x,y,ow,oh,fn,Color3.new(1,1,1),C.Text,14,44)
  sidebarSurface(b,selected,cyan);if fx then fx:Selected(b,selected)end
  return b
 end
 local function optionLabel(b,name,value,x,y,ow,oh,size,color)
  local t=sidebarText(b,name,value,x,y,ow,oh,size,color);t.ZIndex=b.ZIndex+3;return t
 end
 -- ON/OFF pill switch with a sliding knob.
 local function switch(p,name,x,y,on,fn)
  local b=glossy(button(p,name,on and"ON   "or"   OFF",x,y,86,36,fn,C.Raised,C.Text,15,45),on and"Purple"or"Navy")
  b.Corners.CornerRadius=UDim.new(0,18);b.Border.Color=on and C.Cyan or C.Border
  local knob=frame(b,"Knob",on and 56 or 6,6,24,24,on and Color3.fromRGB(220,250,255)or Color3.fromRGB(120,150,200),b.ZIndex+3);round(knob,12)
  stroke(knob,on and C.Cyan or C.Border).Thickness=2
  b:SetAttribute("On",on)
  return b
 end
 local function popupButton(p,name,value,x,y,bw,bh,fn,variant,size)
  local b=glossy(button(p,name,value,x,y,bw,bh,fn,C.Raised,C.Text,size or 18,45),variant)
  b.Corners.CornerRadius=UDim.new(0,14);b.Border.Thickness=3
  return b
 end
 local function body(p,name,value,x,y,bw,bh,size,color)
  local t=text(p,name,value,x,y,bw,bh,size or 14,color or Color3.fromRGB(214,234,255),M,nil,44)
  t.TextWrapped=true;t.TextYAlignment=Enum.TextYAlignment.Top;return t
 end
 local function overlay(w,h)
  if s.Overlay~="ResetAccount"then s.ResetAccountToken=nil end
  if not s.Overlay then return end
  if s.Overlay=="Away" then
   local away=session.Portfolio and session.Portfolio.AwaySummary
   if not AwayView.ShouldShow(away)or s.AwaySeen==away.Id then s.Overlay=nil;return end
   button(canvas,"AwayBackdrop","",0,0,w,h,function()end,C.Bg,C.Text,12,40).BackgroundTransparency=.25
   AwayView.Draw({Canvas=canvas,C=C,frame=frame,text=text,round=round,stroke=stroke,tint=tint,button=button,gloss=glossy,signed=Market.Signed},w,h,away,function()
    local ok,message=session:AcknowledgeAway(away.Id)
    if not ok then fail(message);return end
    s.AwaySeen=away.Id;s.Overlay=nil;refresh()
   end)
   return
  end
  if s.Overlay=="Blown"then
   -- The notice belongs to one depletion event; it closes itself once that attempt is restarted.
   local row=tierRow(s.BlownTier);if not(row and row.Depleted and row.DepletionEvent==s.BlownEvent)then s.Overlay=nil;return end
  end
  local dropdown=s.Overlay=="Contracts"and s.ContractAnchor~=nil
  button(canvas,"OverlayBackdrop","",0,0,w,h,function()
   if s.Overlay=="Protection"then closeProtection();return end
   s.ProtectionDraft=nil;s.Overlay=nil;refresh()
  end,C.Bg,C.Text,12,40).BackgroundTransparency=dropdown and .72 or .28
  if s.Overlay=="Account"then s.Overlay="Help" end
  if s.Overlay=="Protection"then protectionPopup(w,h);return end
  if s.Overlay=="Shop"then
   depthPurchase:Refresh()
   ShopView.Draw({Canvas=canvas,button=button,gloss=glossy,dismiss=dismissButton,
    depthState=function()return depthPurchase:State()end,purchaseDepth=function()depthPurchase:Prompt()end,
    shopIcon=function(p,x,y,size)return sidebarImage(p,"Shop",x,y,size)end,
    close=function()s.Overlay=nil;refresh()end},w,h)
   return
  end
  local pf=session.Portfolio
  local pw=math.min(w-28,s.Overlay=="Tools" and 470 or 460)
  local narrow=pw<380
  local pad=narrow and 16 or 22;local iw=pw-pad*2
  local function close()s.Overlay=nil;refresh()end
  if s.Overlay=="ResetAccount"then
   -- Freeze this confirmation's run token so a lost reply/retry cannot reset the new run.
   s.ResetAccountToken=s.ResetAccountToken or session.AccountToken
   local balance=pf and pf.StartingBalance or Ladder.StartingBalance
   local _,p=popupShell(w,h,pw,326,"Reset Account?","Accounts","Keep your permanent progress")
   optionLabel(p,"StartingBalance","Start with "..whole(balance),pad,0,iw,40,narrow and 22 or 28,C.Green)
   body(p,"ResetEffects","Your current balance is replaced. Open positions and pending orders are cleared without counting as completed trades. Current account statistics start over.",pad,52,iw,105,15)
   body(p,"Preserved","Lifetime statistics, milestones, permanent starting-balance bonuses and rank progression stay yours.",pad,164,iw,78,15)
   local bw=(iw-10)/2
   popupButton(p,"CancelReset","Cancel",pad,260,bw,48,close,"Navy",18)
   local confirm=popupButton(p,"ConfirmReset",s.PendingReset and "Resetting…"or "Reset Account",pad+bw+10,260,bw,48,function()
    if s.PendingReset then return end
    local ok,message,_,id=session:ResetAccount(s.ResetAccountToken)
    if not ok then fail(message);return end
    s.PendingReset=id;refresh()
    task.delay(10,function()if alive and s.PendingReset==id then s.PendingReset=nil;fail("Reset confirmation has not arrived. Check the account before retrying.")end end)
   end,"Pink",narrow and 15 or 18)
   confirm.Active=not s.PendingReset
  elseif s.Overlay=="QuantityLimit"then
   local _,p=popupShell(w,h,pw,190,"Quantity limit","Accounts")
   local message="Available now: "..tostring(s.QuantityLimit).." "..s.QuantitySymbol.." contracts. Limits use settled balance, excluding open P&L. Positions and pending orders use this limit."
   body(p,"LimitMessage",message,pad,4,iw,112,narrow and 17 or 19,C.Text)
   popupButton(p,"GotIt","Got it",pad,130,iw,48,close,"Purple",20)
  elseif s.Overlay=="Close"then
   local held=session.Positions[s.CloseContract]
   local _,p=popupShell(w,h,pw,204,"Close position?","Positions")
   optionLabel(p,"Position",held and(held.Contract.." · "..(held.Direction>0 and"LONG"or"SHORT").." · "..held.Quantity.." contract"..(held.Quantity==1 and""or"s"))or"This position has already closed.",pad,0,iw,30,narrow and 17 or 20)
   local pnl=held and session:Pnl(held)or 0
   if held then
    local box=frame(p,"ResultBox",pad,38,iw,58,Color3.fromRGB(3,24,70),44);round(box,14);stroke(box,pnl>=0 and SC.Green or SC.Red).Thickness=2
    optionLabel(box,"ResultLabel","Open profit",14,0,iw*.5,58,narrow and 15 or 17,Color3.fromRGB(214,234,255))
    local r=summaryText(box,"Result",Market.Signed(pnl),iw*.45,6,iw*.55-14,46,28,pnl>=0 and SC.Green or SC.Red,false);r.TextXAlignment=RIGHT;r.ZIndex=46
   end
   local bw=(iw-12)/2
   popupButton(p,"KeepOpen","Keep open",pad,112,bw,54,close,"Navy",narrow and 17 or 20).Border.Color=C.Cyan
   local confirm=popupButton(p,"ConfirmClose","Close",pad+bw+12,112,bw,54,function()
    local key=s.CloseContract;s.Overlay=nil
    if session.Positions[key]and not s.PendingClose then
     local ok,msg,_,requestId=session:Close(key);s.Error=nil
     if ok then
      local pending={Id=requestId,Contract=key};s.PendingClose=pending
      if fx then fx:Play("Send")end;toast("Closing "..key.."…","info")
      task.delay(6,function()if alive and s.PendingClose==pending then s.PendingClose=nil;refresh()end end)
     else fail(msg)end
    else refresh()end
   end,"Pink",narrow and 17 or 20)
   confirm:SetAttribute("Sound","None");confirm:SetAttribute("Debounce",.4)
   text(p,"Note","Closing locks in the filled trade's profit or loss. The final amount may differ.",pad,172,iw,30,11,C.Muted,F,CENTER,44).TextWrapped=true

  elseif s.Overlay=="Contracts"then
   local _,p=popupShell(w,h,pw,#Market.ContractOrder*66,"Choose a market","Trade","Blox futures")
   for i,key in ipairs(Market.ContractOrder)do
    local c=Market.Contracts[key];local selected=key==s.Contract
    local b=option(p,"Choose"..key,pad,(i-1)*66,iw,58,selected,function()s.Overlay=nil;selectContract(key)end)
    optionLabel(b,"Symbol",key,14,4,120,28,narrow and 18 or 21)
    local n=text(b,"Name",c.Short,14,31,iw-170,20,12,Color3.fromRGB(214,234,255),M,nil,b.ZIndex+3);n.TextTruncate=Enum.TextTruncate.AtEnd
    text(b,"Price",Market.Number(session.Prices[key]),iw-168,0,selected and 126 or 154,58,16,C.Text,N,RIGHT,b.ZIndex+3)
    if selected then local dot=frame(b,"Dot",iw-30,23,12,12,Color3.fromRGB(93,255,83),b.ZIndex+3);round(dot,6);stroke(dot,SC.Ink).Thickness=3 end
   end
  elseif s.Overlay=="Timeframes"then
   local list={"1m","5m","15m","1h","1D"}
   local _,p=popupShell(w,h,pw,#list*56,"Timeframe","Trade","Candle interval")
   for i,tf in ipairs(list)do
    local b=option(p,"Choose"..tf,pad,(i-1)*56,iw,48,s.Timeframe==tf,function()s.Timeframe=tf;s.Overlay=nil;chartView:CancelPlacement();refresh()end)
    local t=optionLabel(b,"Label",tf,0,0,iw,48,20);t.TextXAlignment=CENTER
   end
  elseif s.Overlay=="Tools"then
   -- Two columns of touch-size buttons; the active tool and magnet are highlighted.
   local items={{"Pan","Select & pan"},{"Crosshair","Crosshair"},{"Trend","Trend line"},{"Line","Horizontal line"},{"Rect","Rectangle"},
    {"Magnet",s.Magnet and"Magnet: on"or"Magnet: off"},{"Delete","Delete selected"},{"Clear","Clear drawings"},
    {"AutoFit","Auto"}}
   local colW=(iw-10)/2
   local _,p=popupShell(w,h,pw,math.ceil(#items/2)*54,"Chart tools","Settings","Draw, navigate and fit the chart")
   for i,t in ipairs(items)do
    local col=(i-1)%2;local row=(i-1)//2
    local active=s.Tool==t[1]or t[1]=="Magnet"and s.Magnet
    local b=option(p,"Tool"..t[1],pad+col*(colW+10),row*54,colW,46,active,function()
     s.Overlay=nil
     if t[1]=="Delete"then chartView:DeleteSelected()
     elseif t[1]=="AutoFit"then chartView:AutoFit()
     else chartView:Command(t[1])end
     refresh()
    end)
    local icon=ChartView.AddToolIcon(b,t[1],36)
    if icon then icon.Position=UDim2.new(0,23,.5,0)end
    local labelX=icon and 44 or 8
    local l=optionLabel(b,"Label",t[2],labelX,0,colW-labelX-8,46,narrow and 12 or 15)
    l.TextXAlignment=icon and Enum.TextXAlignment.Left or CENTER
   end
  elseif s.Overlay=="Menu"then
   -- Phone "More": the destinations and actions that no longer have their own nav button.
   local items={{"Leaderboard","Leaderboard","Leaderboard"},{"Shop","Shop","Shop"},{"Activity","Positions & orders","Positions"},
    {"OrderSettings","Order type & Level 2","Trade"},{"History","Trade history","Review"},{"Help","How to play","Help"},
    {"Settings","Settings","Settings"}}
   local _,p=popupShell(w,h,pw,#items*58,"Get Funded!","Help","More")
   for i,t in ipairs(items) do
    local b=option(p,t[1],pad,(i-1)*58,iw,50,false,function()
     if t[1]=="Leaderboard"or t[1]=="Shop"then navigate(t[1],true);return
     elseif t[1]=="Activity"then s.Screen="Trade";s.Nav="Trade";s.Sheet="Activity";s.Tab="Positions";s.Overlay=nil
     elseif t[1]=="OrderSettings"then s.Screen="Trade";s.Nav="Trade";s.Sheet=true;s.Overlay=nil
     elseif t[1]=="History" then s.Screen="Trade";s.Nav="Trade";s.Sheet="Activity";s.Tab="History";s.Overlay=nil
     else s.Overlay=t[1] end;refresh()
    end)
    sidebarImage(b,t[3],10,7,36).ZIndex=b.ZIndex+3;optionLabel(b,"Label",t[2],56,0,iw-70,50,narrow and 16 or 18)
   end
  elseif s.Overlay=="Blown"then
   local row=tierRow(s.BlownTier)
   local _,p=popupShell(w,h,pw,330,"Account failed","Alert")
   body(p,"Intro","Your balance fell to $0 or below, including losses on open positions.",pad,0,iw,70,15,C.Text)
   body(p,"Result","Realized profit this account: "..Market.Signed(row.Realized or 0),pad,82,iw,48,16)
   body(p,"Recovery","Restart with "..whole((pf or {}).StartingBalance or Ladder.StartingBalance).." in-game money. Keep ranks, milestones, permanent bonuses and lifetime totals.",pad,138,iw,106,15)
   restartButton(p,row,pad,260,iw,48,17,45,false,true)

  elseif s.Overlay=="Settings"then
   local _,p=popupShell(w,h,pw,278,"Settings","Settings","Chart, sound and account")
   local rows={
    {"ShowLevels","Chart levels","Entry, stop loss and take profit",s.Levels,function()s.Levels=not s.Levels;refresh()end},
    {"SoundToggle","Sound effects","Clicks, confirmations and alerts",s.SoundOn~=false,function()
     s.SoundOn=s.SoundOn==false;if fx then fx:SetSound(s.SoundOn~=false);if s.SoundOn~=false then fx:Play("Select")end end;refresh()end},
   }
   for i,r in ipairs(rows)do
    local y=(i-1)*80
    local card=frame(p,r[1].."Row",pad,y,iw,72,Color3.fromRGB(3,24,70),44);round(card,14);stroke(card,C.Border).Thickness=2
    optionLabel(card,"Label",r[2],14,4,iw-120,26,narrow and 16 or 18)
    text(card,"Detail",r[3],14,30,iw-120,36,11,C.Muted,M,nil,46).TextWrapped=true
    local sw=switch(card,r[1],iw-98,18,r[4],r[5]);sw:SetAttribute("Sound",r[1]=="SoundToggle"and"None"or nil)
   end
   local vy=2*80
   optionLabel(p,"VolumeLabel","Volume",pad,vy,110,40,narrow and 16 or 18)
   local levels={"Low","Medium","High"};local segW=(iw-110-8*2)/3
   for i,level in ipairs(levels)do
    local on=(s.SoundLevel or"Medium")==level
    local b=gameControl(button(p,"Level"..level,level,pad+110+(i-1)*(segW+8),vy,segW,40,function()
     s.SoundLevel=level;if fx then fx:SetSound(nil,level)end;refresh()
    end,C.Panel,C.Text,narrow and 13 or 15,45),on)
    if s.SoundOn==false then b.ControlLabel.TextTransparency=.45 end
   end
   popupButton(p,"ResetAccount","Reset Account",pad,vy+60,iw,48,function()
    s.Overlay="ResetAccount";refresh()
   end,"Pink",18)
  else
   local info=s.Overlay=="Info"
   local sections=info and {{"Trading terms",s.Info}}or{
    {"Make your first trade","Start with "..whole(Ladder.StartingBalance).." in-game money. Choose a market and set quantity to 1. BUY to profit from a price rise; SELL to profit from a fall."},
    {"Know your numbers","Balance: live account value including open profit or loss, also called equity.\nOpen profit: profit or loss on open positions; it changes with prices.\nSettled balance: account value after closed trades. This sets your contract limit; open profits do not add contracts.\nRealized profit: net profit or loss from this account's closed trades.\nLifetime net profit: realized profit across all your accounts, including losses before restarts. Starting money never counts as profit."},
    {"Trade protection","Stop loss helps limit a loss. Take profit closes at your target. Switch each on to attach it to new orders. Dollar amounts cover your selected quantity and round to price ticks. Final fills can differ. Saving these settings does not change existing positions."},
    {"Build your record","Close trades, earn wins and reach lifetime net profit goals for titles. Meet all three goals for a rank. Each closing fill counts as one trade, including partial closes. Earned ranks and titles stay yours."},
    {"Restart after a loss","At $0 equity or below, your account fails and its positions close. Then restart free with "..whole((session.Portfolio or {}).StartingBalance or Ladder.StartingBalance)..". Current account stats start over; ranks, titles and lifetime totals stay. Losses still count. Repeated restarts may need a cooldown."},
    {"The market keeps moving","Open positions and orders stay active when you leave. Close positions and cancel pending orders if you want to stop trading."},
   }
   local size=narrow and 14 or 15;local contentH=0
   for _,section in ipairs(sections)do
    section[3]=TextService:GetTextSize(section[2],size,M,Vector2.new(iw-2,10000)).Y+8
    contentH+=28+section[3]+16
   end
   local _,p=popupShell(w,h,pw,contentH+62,info and "Trading terms"or "How to play","Help")
   local yy=0
   for i,section in ipairs(sections)do
    optionLabel(p,"Heading"..i,section[1],pad,yy,iw,24,18,C.Cyan)
    body(p,"Body"..i,section[2],pad,yy+28,iw,section[3],size,C.Text)
    yy+=28+section[3]+16
   end
   popupButton(p,"ReplayTutorial","Start guided trade",pad,contentH,iw,48,function()s.Screen="Trade";s.Nav="Trade";s.Overlay=nil;s.Sheet=false;s.Coach=1;s.CoachBase=nil;s.CoachDismissed=nil;refresh()end,"Cyan",18)

  end
 end
 -- ── Funded journey: welcome, dashboard, guided first trade and celebrations ──────────────────
 local AtEnd,Top=Enum.TextTruncate.AtEnd,Enum.TextYAlignment.Top
 local function chip(p,name,value,x,y,color,w)
  local width=w or(#value*7+22)
  local c=frame(p,name,x,y,width,22,color:Lerp(SC.Ink,.62));round(c,11);stroke(c,color).Thickness=2
  local t=text(c,"Label",value,0,0,width,22,11,color:Lerp(Color3.new(1,1,1),.35),Enum.Font.FredokaOne,CENTER);t.ZIndex=c.ZIndex+1
  return c
 end
 -- Game progress track: ink rim, dark well and a glossy gold (or green) fill.
 local function progressBar(p,name,x,y,w,h,progress,color)
  h=math.max(h,8)
  local track=frame(p,name,x,y,w,h+4,SC.Ink);round(track,math.floor((h+4)/2))
  local well=frame(track,"Well",2,2,w-4,h,Color3.fromRGB(8,31,84));round(well,math.floor(h/2));stroke(well,Color3.fromRGB(38,77,161))
  do
   local fill=frame(track,"Fill",2,2,math.max(h,(w-4)*math.clamp(progress,0,1)),h,Color3.new(1,1,1));round(fill,math.floor(h/2))
   fill.Visible=progress>0
   if color==C.Green then tint(fill,Color3.fromRGB(120,255,170),Color3.fromRGB(0,190,110))else tint(fill,Color3.fromRGB(255,248,137),Color3.fromRGB(255,176,16))end
  end
  return track
 end
 -- Colourful card surface shared by dashboard cards: gradient body, bright rim, optional stars.
 local function card(p,name,x,y,w,h,top,bottom,edge,stars)
  local c=frame(p,name,x,y,w,h,Color3.new(1,1,1));round(c,18)
  local e=stroke(c,edge);e.Thickness=3
  tint(c,top,bottom);if stars then panelStars(c)end
  return c
 end
 local function goTrade()s.Screen="Trade";s.Nav="Trade";s.Overlay=nil;refresh()end

 local function loading(w,h)
  local bg=frame(canvas,"Loading",0,0,w,h,C.Bg)
  local mark=sidebarText(bg,"Wordmark",'Get <font color="#FFD336">Funded!</font>',0,h/2-78,w,56,w<500 and 36 or 48);mark.RichText=true;mark.TextXAlignment=CENTER
  local status=sidebarText(bg,"Status","Connecting to your trading account…",0,h/2-12,w,26,w<500 and 14 or 17,SB.Muted);status.TextXAlignment=CENTER
  text(bg,"Exchange",session.ConnectionStatus or"CONNECTING",0,h/2+20,w,20,11,C.Cyan,N,CENTER)
  for i=1,3 do
   local dot=frame(bg,"Dot"..i,w/2-36+(i-1)*28,h/2+56,16,16,i==2 and C.Blue or C.Cyan);round(dot,8);stroke(dot,SC.Ink).Thickness=2
   if fx then fx:Loop(TweenService:Create(dot,TweenInfo.new(.42,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true,(i-1)*.14),{Position=dot.Position-UDim2.fromOffset(0,10)}))end
  end
 end
 local function updateUnlockReadout()
  local _,title,ratio,amount=objective();local pf=session.Portfolio
  local panel=canvas:FindFirstChild("AccountSummary");local tile=panel and panel:FindFirstChild("ObjectiveCard")
  if tile and not (pf and pf.Failed) then
   if tile:GetAttribute("Strip")then
    tile.Amount.Text=stripGoal()
    local track=tile:FindFirstChild("Track");if track then track.Fill.Size=UDim2.fromScale(ratio,1);track.Fill.Visible=ratio>0 end
   else tile.Title.Text=title;tile.Amount.Text=amount;tile.Track.Fill.Size=UDim2.fromScale(ratio,1)end
  end
  root:SetAttribute("GoalProgress",pf and pf.Next and pf.Next.Progress)
 end
 local KPI_LOOK={Net={C.Blue,C.Panel,C.Cyan},Open={C.Blue,C.Panel,C.Cyan},Capital={C.Blue,C.Panel,C.Cyan},Copy={C.Blue,C.Panel,C.Cyan}}
 local function progressScreen(x,y,w,h,mobile)
  s.ProgressViewState=s.ProgressViewState or {}
  return ProgressView.Build(canvas,session.Portfolio or {},x,y,w,h,{
   Signed=Market.Signed,Whole=whole,StartingBalance=(session.Portfolio or {}).StartingBalance or Ladder.StartingBalance,State=s.ProgressViewState,
   Restart=function(parent,bx,by,bw,bh)restartButton(parent,activeRow(),bx,by,bw,bh,18,4)end,
  })
 end
 local coachSteps={
  {"Choose your market","Open the market list. Choose BX for the Blox 500, BT for tech or BG for gold.",
   {Desktop={"OrderTicket.Fields.ContractSelector"},Mobile={"Chart.Header.ContractSelector"}}},
  {"Set your quantity","Start with 1 contract. More contracts mean bigger gains and losses for the same price move.",
   {Desktop={"OrderTicket.Fields.Quantity"},Mobile={"TradeDock.QuantityCard.Quantity","TradeDock.Fields.Quantity"}}},
  {"Place a trade","BUY to profit from a rise. SELL to profit from a fall. Stop loss and take profit attach when switched on.",
   {Desktop={"OrderTicket.OrderActions.BuyLong","OrderTicket.OrderActions.SellShort","OrderTicket.Fields.BuyLong","OrderTicket.Fields.SellShort"},Mobile={"TradeDock.BuyLong","TradeDock.SellShort"}}},
  {"Close your position","Close to lock in your profit or loss. The filled result updates your balance and counts toward your goals.",
   {Desktop={"OrderTicket.OrderActions.ClosePosition","OrderTicket.Fields.ClosePosition"},Mobile={"Activity.Rows.Row1","TopNavigation.TradeActivity"}}},
  {"First trade complete","",{Desktop={},Mobile={}}},
 }
 local function findPath(path)
  local node=canvas
  for part in path:gmatch("[^%.]+")do node=node and node:FindFirstChild(part)end
  return node
 end
 local function highlight(target)
  local ring=make("Frame","CoachHighlight",target,{Size=UDim2.new(1,6,1,6),Position=UDim2.fromOffset(-3,-3),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=target.ZIndex+3})
  round(ring,10);local edge=stroke(ring,C.Blue);edge.Thickness=2
  local pulse=TweenService:Create(edge,TweenInfo.new(.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true),{Transparency=.65})
  if fx then fx:Loop(pulse)else pulse:Play()end
 end
 local function finishCoach(skipped)
  s.Coach=nil;s.CoachBase=nil;s.CoachDismissed=true
  session:Flag(skipped and"TutorialSkipped"or"TutorialDone");refresh()
 end
 local function coachProgress()
  if not s.Coach then return false end
  local fill,hist=session.Fills[1],session.History[1]
  local base=s.CoachBase
  if not base or base.Account~=session.AccountKey then
   s.CoachBase={Account=session.AccountKey,Fill=fill and fill.TradeId,History=hist and hist.TradeId};return false
  end
  local before=s.Coach
  if s.Coach<=3 and fill and fill.TradeId~=base.Fill then s.Coach=4;base.Fill=fill.TradeId end
  if s.Coach==4 and hist and hist.TradeId~=base.History then s.Coach=5 end
  return s.Coach~=before
 end
 local function coach(w,h,mobile,layout)
  if not s.Coach or options.Preview then return end
  local pf=session.Portfolio;if not pf or pf.New then return end
  local step=coachSteps[s.Coach];local title,body=step[1],step[2]

  if s.Coach==1 then body="Your $10,000 starting balance is in-game money. Open the market list and choose where to trade." end
  if s.Coach==5 then
   local last=session.History[1];title="First trade complete"
   body=(last and "Realized profit: "..Market.Signed(last.Pnl)..". " or "").."It now counts toward your goals. "..(pf.Next and "Next: "..pf.Next.Name.."." or "Every title is yours.")
  end
  local hasButton=s.Coach<=2 or s.Coach==5
  local x,y,cw,ch
  if mobile then
   -- Top of the screen, except step 1 whose target (the chart's contract selector) sits there.
   x=12;cw=layout.CoachW or w-24;ch=s.Coach==5 and 142 or 116
   y=s.Coach==1 and (layout.Compact and h-ch-10 or math.max(layout.Head,(layout.TradeTop or h-layout.NavH)-ch-8))or layout.Head
  else
   -- Compact and bottom-aligned so the activity tabs, table header and first row stay readable.
   local a=layout.Activity;cw=math.min(640,a[3]*.56)
   local textH=TextService:GetTextSize(body,12,F,Vector2.new(cw-(hasButton and 138 or 28),1000)).Y
   ch=math.clamp(60+textH,86,math.max(86,a[4]-8));x=a[1]+12;y=a[2]+a[4]-ch-8
  end
  local card=frame(canvas,"Coach",x,y,cw,ch,Color3.new(1,1,1),38);round(card,16);stroke(card,C.Cyan).Thickness=3
  tint(card,Color3.fromRGB(122,56,245),Color3.fromRGB(58,22,176))
  sidebarText(card,"Step","FIRST TRADE · "..s.Coach.." OF "..#coachSteps,14,6,cw-124,18,11,Color3.fromRGB(236,227,255))
  local skip=glossy(button(card,"SkipTour",s.Coach==5 and"Close"or"Skip tour",cw-98,6,88,26,function()finishCoach(s.Coach~=5)end,C.Raised,C.Text,12,39),"Navy")
  skip.Border.Color=C.Cyan
  sidebarText(card,"Title",title,14,24,cw-28,26,mobile and 16 or 19).TextTruncate=AtEnd
  local t=text(card,"Body",body,14,52,cw-(hasButton and 138 or 28),ch-58,mobile and 11 or 12,Color3.fromRGB(236,232,255),M);t.TextWrapped=true;t.TextYAlignment=Top
  if s.Coach<=2 then glossy(button(card,"CoachNext","Next  →",cw-104,ch-44,92,36,function()s.Coach+=1;refresh()end,C.Raised,C.Text,15,39),"Cyan")end
  if s.Coach==5 then glossy(button(card,"FinishTour","Keep trading",cw-130,ch-46,118,38,function()finishCoach(false)end,C.Raised,C.Text,15,39),"Green")end
  local targets=step[3][mobile and"Mobile"or"Desktop"]
  if s.Coach==4 and mobile then
   local key;for _,k in ipairs(Market.PositionOrder)do if session.Positions[k]then key=k break end end
   local close=key and findPath("Activity.Rows.Row1.Close"..key)
   local dock=findPath("TradeDock.PositionBar.ClosePosition")and"TradeDock.PositionBar.ClosePosition"
    or findPath("TradeDock.Fields.PositionBar.ClosePosition")and"TradeDock.Fields.PositionBar.ClosePosition"
   targets=dock and{dock}or close and{"Activity.Rows.Row1.Close"..key}or{"TopNavigation.TradeActivity"}
  end
  for _,path in ipairs(targets)do local target=findPath(path);if target then highlight(target)end end
 end
 local function celebrate(event)
  toast("Title earned: "..event.Title.." · "..event.Name,"success")
 end
 local function mobileBadge()
  if options.Preview then return "Studio preview"end
  if not session.CanTrade then return session.Ready and "Trading paused"or "Connecting to the exchange…"end
  local row=activeRow();if row and row.Depleted then return row.Closing and"Account failed · closing positions…"or"Account failed · tap the goal card"end
  local _,_,_,_,summary=objective()
  return session.PersistenceMode=="Local"and("Not saved · "..summary)or summary
 end
 local function leaderboardScreen(x,y,w,h,mobile)
  LeaderboardView.Draw({Canvas=canvas,C=C,frame=frame,text=text,round=round,stroke=stroke,tint=tint,heading=sidebarText,
   button=button,gloss=glossy,insetScroll=insetScroll,icon=function(p,kind,xx,yy,size)summaryIcon(p,kind,xx,yy,size)end,money=Market.Money},x,y,w,h,mobile,leaderboard)
 end
 -- Stats page: one shared scope for six realized metrics, computed by the server.
 local function statsContext()
  return {Canvas=canvas,C=C,SC=SC,Muted=SB.Muted,make=make,frame=frame,text=text,round=round,stroke=stroke,tint=tint,
   heading=sidebarText,value=summaryText,button=button,gloss=glossy,control=gameControl,card=card,insetScroll=insetScroll,
   icon=function(p,kind,xx,yy,size)return summaryIcon(p,kind,xx,yy,size)end,
   money=Market.Money,signed=Market.Signed,State=s,Data=session.Stats,Portfolio=session.Portfolio,
   Status=session.ConnectionStatus,CanTrade=session.CanTrade or options.Preview,
   looks={Net=KPI_LOOK.Open,Open=KPI_LOOK.Capital,Total=KPI_LOOK.Copy,
    Blown={summaryThemes.Blown.Top,summaryThemes.Blown.Bottom,summaryThemes.Blown.Edge}},
   refresh=refresh,
   retry=function()local ok,message=session:RefreshStats();if not ok then fail(message)else toast("Refreshing stats…","info")end end,
   start=function()navigate("Trade")end}
 end
 local function statsScreen(x,y,w,h,mobile)
  -- Stats normally arrive with the first full update; if none is held yet, ask the server once.
  if not session.Stats and not options.Preview and not s.StatsRequested then s.StatsRequested=true;session:RefreshStats()end
  StatsView.Draw(statsContext(),x,y,w,h,mobile)
 end
 local function tradeStatus()
  -- Header status for exceptional states only; the account strip carries the goal.
  if options.Preview then return "Studio preview"end
  if not session.CanTrade then return session.Ready and "Trading paused"or "Connecting…"end
  local row=activeRow();if row and row.Depleted then return row.Closing and"Closing positions…"or"Account failed"end
  return session.PersistenceMode=="Local"and"Not saved"or""
 end
 -- One shallow account strip: live balance, open P&L and next goal (names match the desktop cards,
 -- so the in-place market updates and goal readout reach it without a rebuild).
 local function accountStrip(x,y,w,h,inline)
  local sum=session:Summary();local pf=session.Portfolio;local failed=pf and pf.Failed
  local panel=frame(canvas,"AccountSummary",x,y,w,h,Color3.new(1,1,1),3)
  round(panel,inline and 10 or 12);stroke(panel,Color3.fromRGB(26,88,186)).Thickness=1.5
  tint(panel,Color3.fromRGB(6,46,120),Color3.fromRGB(3,28,80))
  local _,_,progress=objective()
  local help=function()s.Overlay="Help";refresh()end
  local cells={
   {"Balance","Balance",Market.Money(sum.Equity),C.Text,help},
   {"Unrealized","Open P&L",Market.Signed(sum.Unrealized),sum.Unrealized>=0 and SC.Green or SC.Red,help},
   {"Objective",failed and"Account failed"or"Next goal",failed and"Tap to restart"or stripGoal(),failed and SC.Red or C.Text,
    function()if failed then openBlown(pf.Active)else navigate("Progress")end end},
  }
  local row=inline and w>=420
  local small=h<44
  local shares={.3,.3}
  local cx=0
  for i,d in ipairs(cells)do
   local goal=i==3
   local cw=goal and w-cx or math.floor(w*shares[i])
   if i>1 then local div=frame(panel,"Divider",cx,math.floor(h*.2),1,math.ceil(h*.6),Color3.fromRGB(44,104,200),4);div.BackgroundTransparency=.2 end
   local cell=button(panel,d[1].."Card","",cx,0,cw,h,d[5],false,C.Text,12,4)
   if goal then cell:SetAttribute("Strip",true)end
   local valueName=goal and"Amount"or d[1].."Value"
   local tx,ty,tw
   if row then
    local lw=math.ceil(TextService:GetTextSize(d[2],12,SF,Vector2.new(400,40)).X)+8
    text(cell,"Label",d[2],10,0,lw,h,12,SB.Muted,SF,nil,5)
    -- The goal keeps its full "16 / 100 trades" on one line; the progress bar takes what is left.
    local need=math.ceil(TextService:GetTextSize(d[3],13,SF,Vector2.new(600,40)).X)+6
    local vw=goal and math.max(40,math.min(need,cw-lw-46))or cw-lw-16
    local v=summaryText(cell,valueName,d[3],10+lw,0,vw,h,goal and 13 or 16,d[4],true);v.TextXAlignment=Enum.TextXAlignment.Left
    tx,ty,tw=10+lw+vw+6,math.floor(h/2)-3,cw-(10+lw+vw+6)-10
   else
    text(cell,"Label",d[2],9,small and 2 or 6,cw-14,small and 12 or 15,small and 10 or 12,SB.Muted,SF,nil,5)
    local vy=small and 14 or 22
    local vh=goal and(small and 11 or 16)or h-vy-(small and 2 or 6)
    local v=summaryText(cell,valueName,d[3],9,vy,cw-16,vh,goal and(small and 11 or 13)or(small and 15 or 19),d[4],true);v.TextXAlignment=Enum.TextXAlignment.Left
    tx,ty,tw=9,h-(small and 7 or 13),cw-20
   end
   if goal and not failed and tw>=20 then
    local track=frame(cell,"Track",tx,ty,tw,small and 4 or 6,SC.Ink,5);round(track,3)
    local fill=frame(track,"Fill",0,0,0,0,Color3.new(1,1,1),6);fill.Size=UDim2.fromScale(math.clamp(progress,0,1),1);round(fill,3)
    tint(fill,Color3.fromRGB(255,236,92),Color3.fromRGB(255,176,16));fill.Visible=progress>0
   end
   cx+=cw
  end
 end
 -- Phones: four destinations. More opens the menu with Leaderboard, Shop and the remaining actions.
 local function phoneNav(p,w,h,wide)
  local items={"Trade","Progress","Stats","More"}
  local cell=w/#items
  for i,value in ipairs(items)do
   local selected=value=="More"and(s.Nav=="Leaderboard"or s.Overlay=="Menu"or s.Overlay=="Shop")or value~="More"and s.Nav==value and s.Overlay~="Menu"and s.Overlay~="Shop"
   local bx=math.floor((i-1)*cell)+4;local bw=math.floor(cell)-8;local by=4;local bh=h-7
   local b=button(p,"Nav"..value,"",bx,by,bw,bh,function()
    if value=="More"then s.Sheet=false;s.ProtectionDraft=nil;s.Overlay="Menu";refresh()else navigate(value,true)end
   end,Color3.new(1,1,1),C.Text,12,p.ZIndex+2)
   sidebarSurface(b,selected,false);if fx then fx:Selected(b,selected)end
   if not selected then b.Border.Thickness=1 end
   if value=="More"then b:SetAttribute("Sound","Open")end
   local iconSize=wide and math.min(26,bh-12)or math.min(26,bh-22)
   local labelSize=wide and 14 or 11
   local lw=wide and math.ceil(TextService:GetTextSize(value,labelSize,SF,Vector2.new(300,40)).X)+6 or bw-4
   local ix=wide and math.max(4,math.floor((bw-iconSize-6-lw)/2))or math.floor((bw-iconSize)/2)
   local iy=wide and math.floor((bh-iconSize)/2)or 4
   if value=="More"then
    local dots=frame(b,"IconMore",ix,iy,iconSize,iconSize,C.Bg,b.ZIndex+1);dots.BackgroundTransparency=1
    local d=math.max(4,math.floor(iconSize*.22))
    for k=-1,1 do local dot=frame(dots,"Dot",math.floor(iconSize/2-d/2+k*iconSize*.33),math.floor((iconSize-d)/2),d,d,C.Text,b.ZIndex+2);round(dot,d)end
   else sidebarImage(b,value=="Progress"and"Accounts"or value,ix,iy,iconSize)end
   local label=sidebarText(b,"Label",value,wide and ix+iconSize+6 or 2,wide and 0 or bh-17,wide and lw or bw-4,wide and bh or 15,labelSize)
   label.TextXAlignment=wide and Enum.TextXAlignment.Left or CENTER
  end
 end
 -- Phone Trade screen ("Arcade Clean"): compact header and account strip; the chart takes all the
 -- remaining height above quantity/risk and BUY/SELL. Landscape moves the controls to a right column.
 local function phoneTrade(w,h,sum,layout)
  local wide=w>h;local pad=10;local gap=8
  local dense=not wide and h<640;local tight=wide and h<300
  -- No game title on phones: the header row exists only for the Activity pill or a status notice
  -- (portrait); in landscape it holds the account strip.
  local status=tradeStatus()
  local working=#session:Working();local pillW=0
  -- Landscape only: in portrait, positions/orders are reached from the position row and More.
  local pillLabel=wide and sum.Count+working>0 and(sum.Count>0 and(sum.Count.." open")or(working..(working==1 and" order"or" orders")))or nil
  if pillLabel then pillW=math.ceil(TextService:GetTextSize(pillLabel,14,SF,Vector2.new(400,40)).X)+50 end
  local statusW=status~=""and math.ceil(TextService:GetTextSize(status,11,F,Vector2.new(400,40)).X)+8 or 0
  local head=wide and(tight and 36 or 40)or(pillW>0 or statusW>0)and(dense and 36 or 40)or 0
  local stripTop=wide and 0 or head>0 and head or 6
  layout.Head=head;layout.Compact=wide
  local navH=layout.NavH
  local top=frame(canvas,"TopNavigation",0,0,w,math.max(head,1),C.Bg);top.BackgroundTransparency=1
  -- Holds the status notice; market updates refresh TopNavigation.Account.Brand in place.
  local acc=frame(top,"Account",0,0,w,math.max(head,1),C.Bg);acc.BackgroundTransparency=1
  -- Activity entry point only while something is open or working; otherwise it lives in More.
  if pillLabel then
   local label=pillLabel
   local ph=math.min(36,head-6)
   local pill=glossy(button(top,"TradeActivity","",w-pad-pillW,math.floor((head-ph)/2),pillW,ph,function()
    s.Sheet="Activity";s.Tab=sum.Count>0 and"Positions"or"Orders";refresh()end,C.Raised,C.Text,14),"Cyan")
   pill:SetAttribute("Sound","Open")
   sidebarImage(pill,"Positions",6,math.floor((ph-26)/2),26)
   local count=sidebarText(pill,"Count",label,36,0,pillW-42,ph,14);count.ZIndex=pill.ZIndex+3
  end
  local brand
  if wide then brand=text(acc,"Brand",status,w-pad-(pillW>0 and pillW+gap or 0)-statusW,0,statusW,head,11,C.Muted,F,RIGHT)
  else brand=text(acc,"Brand",status,pad,0,math.max(0,w-pad*2-(pillW>0 and pillW+6 or 0)),math.max(head,1),11,C.Muted,F)end
  brand.TextTruncate=AtEnd
  if not wide then
   local stripH=dense and 46 or 56
   accountStrip(pad,stripTop,w-pad*2,stripH,false)
   local dims={Row=dense and 62 or 66,Button=dense and 48 or 52}
   local dockH=(session.Positions[s.Contract]and 50 or 0)+dims.Row+gap+dims.Button
   local cy=stripTop+stripH+gap;local dockY=h-navH-gap-dockH
   -- No placeholder rows: every remaining pixel goes to the chart's plot.
   chartView.Inline=false
   chart(pad,cy,w-pad*2,dockY-gap-cy,true,h<650,false)
   layout.TradeTop=dockY
   mobileDock(pad,dockY,w-pad*2,dockH,false,dims)
  else
   local stripX=pad;local stripW=w-stripX-pad-(pillW>0 and pillW+gap or 0)-(statusW>0 and statusW+gap or 0)
   local stripH=tight and 30 or 34
   accountStrip(stripX,math.floor((head-stripH)/2),stripW,stripH,true)
   local colW=math.clamp(math.floor(w*.3),188,260)
   local cy=head+4;local ch=h-cy-navH-gap;local cw=w-pad*2-colW-gap
   chartView.Inline=true
   chart(pad,cy,cw,ch,true,true,true)
   layout.CoachW=cw
   mobileDock(pad+cw+gap,cy,colW,ch,true)
  end
 end
 local function mobileScreen(w,h,sum,screen)
  local compact=w>h;local dense=h<650 and not compact
  local head=dense and 48 or 60;local navH=compact and(h<300 and 40 or 44)or dense and 48 or 56
  if screen=="Progress"or screen=="Stats"or(compact and screen=="Leaderboard")then head=0 end
  local layout={Head=head,NavH=navH,Compact=compact}
  if screen=="Trade"then phoneTrade(w,h,sum,layout)
  else
   -- Progress and Stats start at the top; More remains in the bottom navigation.
   if head>0 then
   local top=frame(canvas,"TopNavigation",0,0,w,head,C.Bg)
   local acc=button(top,"Account","",12,0,w-70,head,function()s.Overlay="Account";refresh()end,false)
   local title=sidebarText(acc,"Name",'Get <font color="#FFD336">Funded!</font>',0,dense and 0 or 3,w-70,dense and 26 or 30,dense and 20 or 22)
   title.RichText=true;title.TextXAlignment=Enum.TextXAlignment.Left
   local brand=text(acc,"Brand",screen=="Stats"and "Current account results"or screen=="Leaderboard"and "Account balance standings"or "Ranks and title collection",0,dense and 27 or 34,w-70,dense and 17 or 20,9,C.Muted);brand.TextTruncate=AtEnd
   if compact and screen=="Leaderboard"then brand.Visible=false end
   local more=glossy(button(top,"More","···",w-54,6,44,40,function()s.Overlay="Menu";refresh()end,C.Raised,C.Text,20),"Navy")
   more.Border.Color=C.Cyan;more:SetAttribute("Sound","None")
   end
   if screen=="Leaderboard"then
    leaderboardScreen(12,head+6,w-24,h-head-navH-12,true)
   elseif screen=="Stats"then
    statsScreen(12,head+6,w-24,h-head-navH-12,true)
   else
    progressScreen(12,head+6,w-24,h-head-navH-12,true)
   end
  end
  local navigation=frame(canvas,"MobileNavigation",0,h-navH,w,navH,SB.Navy,25)
  phoneNav(navigation,w,navH,compact)
  if s.Sheet then
   local sw=compact and math.min(390,w-30)or w
   local sh=math.min(h-54,s.Sheet=="Activity"and 350 or s.Type=="Limit"and 540 or 475)
   local sx=w-sw;local sy=h-sh
   button(canvas,"SheetBackdrop","",0,0,w,h,function()s.Sheet=false;refresh()end,C.Bg,C.Text,12,30).BackgroundTransparency=.3
   local sheet=frame(canvas,"OptionsSheet",sx,sy,sw,sh+20,Color3.new(1,1,1),31);round(sheet,20)
   stroke(sheet,Color3.fromRGB(4,221,255)).Thickness=3;tint(sheet,Color3.fromRGB(8,60,156),Color3.fromRGB(3,28,80))
   local grip=frame(sheet,"Grip",sw/2-22,6,44,5,Color3.fromRGB(120,190,255),32);grip.BackgroundTransparency=.3;round(grip,3)
   sidebarText(sheet,"Title",s.Sheet=="Activity"and"Activity"or"Order settings",16,4,sw-100,44,19).ZIndex=33
   local done=glossy(button(sheet,"Done","Done",sw-86,7,74,36,function()s.Sheet=false;refresh()end,C.Raised,C.Text,15,33),"Purple")
   done.Corners.CornerRadius=UDim.new(0,12);rule(sheet,0,48,sw,C.Cyan)
   if s.Sheet=="Activity"then activity(sx,sy+49,sw,sh-49,true,false,32)
   else
    -- Market/Limit, quantity, protection and Level 2 (with its entitlement and loading states).
    local fields=make("ScrollingFrame","Fields",sheet,{Position=UDim2.fromOffset(0,49),Size=UDim2.fromOffset(sw,sh-49),CanvasSize=UDim2.new(),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.Muted,ZIndex=32})
    local fy=orderOptions(fields,sw,12,true)
    local depth=level2(fields,16,fy,sw-32,function(height)fields.CanvasSize=UDim2.fromOffset(0,fy+height+16)end)
    fields.CanvasSize=UDim2.fromOffset(0,fy+depth.Height+16)
   end
  end
  return layout
 end
 -- Welcome for first-time players, dashboard for returning players, trading workspace on demand.
 local function currentScreen()
  if not options.Preview and not session.Portfolio then return "Loading" end
  return s.Screen or "Trade"
 end
 local lastPopup
 local popupParts={"OverlayBackdrop","Dialog","ProtectionDialog","ShopDialog","SheetBackdrop","OptionsSheet"}
 local function popupKey()
  if s.Overlay then return"O:"..s.Overlay..(s.Overlay=="Info"and tostring(s.Info)or"")end
  if s.Sheet then return"S:"..tostring(s.Sheet)end
 end
 local function renderNow(keepTicket)
  if not alive or not root.Parent then return end
  if chartView:Busy()then fullRefreshPending=true;return end
  local size=root.AbsoluteSize;local w=size.X>0 and size.X or 1440;local h=size.Y>0 and size.Y or 900
  preservedTicket=nil
  if keepTicket and w==lastW and h==lastH and currentScreen()=="Trade"and root:GetAttribute("Screen")=="Trade"and root:GetAttribute("SelectedContract")==s.Contract then
   local panel=canvas:FindFirstChild("OrderTicket")or canvas:FindFirstChild("TradeDock")
   if panel and panel:GetAttribute("TradingEnabled")== (options.Preview or session.CanTrade)and(panel.Name~="TradeDock"or panel:GetAttribute("DockKey")==dockKey())then preservedTicket=panel end
  end
  lastW=w;lastH=h
  local scroll={}
  for _,v in ipairs(canvas:GetDescendants())do if v:IsA("ScrollingFrame")then scroll[v:GetFullName()]=v.CanvasPosition end end
  -- A popup that just closed (or was replaced) fades out from a separate layer instead of vanishing.
  local key=popupKey()
  if fx then
   fx:StopLoops()
   if lastPopup and key~=lastPopup then
    local items={}
    for _,name in ipairs(popupParts)do local o=canvas:FindFirstChild(name);if o then table.insert(items,o)end end
    fx:Ghost(items)
   end
  end
  for i=#depthViews,1,-1 do local view=depthViews[i]
   if not preservedTicket or not view.Root:IsDescendantOf(preservedTicket)then view:Destroy();table.remove(depthViews,i)end
  end
  for _,child in ipairs(canvas:GetChildren())do if child~=preservedTicket then child:Destroy()end end
  canvas.Size=UDim2.fromOffset(w,h)
  chartView:Reset();chartView.Inline=false
  if session.Contract~=s.Contract or session.Timeframe~=s.Timeframe then session:Subscribe(s.Contract,s.Timeframe)end
  task.defer(function()if alive then for _,v in ipairs(canvas:GetDescendants())do if v:IsA("ScrollingFrame") and scroll[v:GetFullName()]then v.CanvasPosition=scroll[v:GetFullName()]end end end end)
  local mobile=w<1000 or h<600;local sum=session:Summary()
  local screen=currentScreen();local layout
  if screen=="Trade"then
   local pf=session.Portfolio
   if pf and pf.Tutorial=="Pending"and s.Coach==nil and not s.CoachDismissed and not options.Preview then s.Coach=1;s.CoachBase=nil end
   s.Nav="Trade"
  elseif screen=="Leaderboard"then s.Nav="Leaderboard"
  elseif screen=="Stats"then s.Nav="Stats"
  else s.Nav="Progress"end
  leaderboard:SetVisible(screen=="Leaderboard")
  if screen=="Loading"then loading(w,h)
  elseif mobile then layout=mobileScreen(w,h,sum,screen)
  else
   local railW=w<1150 and 180 or w<1550 and 220 or 256;local gap=16
   local cx=railW+gap;local usable=w-cx-20;local tw=w<1150 and 264 or w<1550 and 310 or 360;local cw=usable-tw-gap
   local rw,rh=railW-14,h-28
   local rail=frame(canvas,"Sidebar",10,14,rw,rh,Color3.new(1,1,1),1)
   round(rail,18);stroke(rail,Color3.fromRGB(0,140,255)).Thickness=4
   tint(rail,Color3.fromRGB(5,49,134),Color3.fromRGB(2,25,75))
   local pattern=frame(rail,"Pattern",5,5,rw-10,rh-10,SB.Navy,1);pattern.BackgroundTransparency=1;pattern.ClipsDescendants=true;round(pattern,15)
   for i,pos in ipairs({{.78,.1},{.66,.67},{.2,.77},{.82,.87}})do
    local diamond=frame(pattern,"Diamond"..i,pos[1]*(rw-42),pos[2]*(rh-42),30,30,Color3.fromRGB(0,100,255),1)
    diamond.Rotation=45;diamond.BackgroundTransparency=.84;round(diamond,5)
   end
   local wordmark=sidebarText(rail,"Wordmark",'Get <font color="#FFD336">Funded!</font>',12,18,rw-24,38,rw<185 and 25 or 31)
   wordmark.RichText=true
   local navH=h>=860 and 56 or h>=710 and 44 or 36
   nav(rail,12,74,rw-24,navH,false)
   local marketY=74+5*(navH+9)+10
   local marketH=h>=900 and 42 or 34
   local stacked=marketY+29+#Market.ContractOrder*(marketH+8)+58<rh-116
   local rankY=marketY
   if screen=="Trade"then
    sidebarText(rail,"Markets","YOUR MARKETS",14,marketY,rw-28,22,14,SB.Muted)
    local count=#Market.ContractOrder;local cell=(rw-24-(count-1)*4)/count
    for i,key in ipairs(Market.ContractOrder)do
     local selected=key==s.Contract
     local bx=stacked and 12 or 12+(i-1)*(cell+4)
     local by=marketY+29+(stacked and (i-1)*(marketH+8)or 0)
     local bw=stacked and rw-24 or cell
     local b=button(rail,"Market"..key,"",bx,by,bw,marketH,function()selectContract(key)end,Color3.new(1,1,1),C.Text,12,3)
     sidebarSurface(b,selected,true);if fx then fx:Selected(b,selected)end
     sidebarText(b,"Symbol",key,stacked and 16 or 4,0,bw-8,marketH,stacked and 21 or 16)
    end
    rankY=marketY+29+(stacked and count*(marketH+8)or marketH+8)
   end
   BadgeArt.Create(rail,"SidebarRankBadge",session.Portfolio and session.Portfolio.RankBadge or 1,12,rankY+4,36)
   local rank=sidebarText(rail,"Rank",session.Portfolio and session.Portfolio.Rank or "Market Rookie",54,rankY,rw-66,48,rw<180 and 14 or 17,Color3.fromRGB(255,225,80));rank.TextWrapped=true
   local settings=button(rail,"Settings","",12,rh-57,rw-76,42,function()s.Overlay="Settings";refresh()end,false,C.Text,12,3)
   sidebarImage(settings,"Settings",0,3,36)
   sidebarText(settings,"Label","Settings",40,0,rw-116,42,18)
   local help=button(rail,"Help","",rw-56,rh-58,44,44,function()s.Overlay="Help";refresh()end,Color3.new(1,1,1),C.Text,12,3)
   sidebarSurface(help,true,false);sidebarImage(help,"Help",5,4,34)
   if screen=="Leaderboard"then
    leaderboardScreen(cx,22,usable,h-34,false)
   elseif screen=="Stats"then
    statsScreen(cx,22,usable,h-34,false)
   elseif screen=="Progress"then
    progressScreen(cx,22,usable,h-34,false)
   else
    -- Compact summary cards reserve fixed text rows; the chart gets the freed height.
    local summaryH=80
    accountCards(cx,22,usable,summaryH,false)
    local contentY=22+summaryH+16
    local ay=h-math.clamp(h*.2,152,206)-12
    chart(cx,contentY,cw,ay-contentY-16,false,false,false)
    ticket(cx+cw+gap,contentY,tw,h-contentY-12)
    activity(cx,ay,cw,h-ay-12,false,false)
    layout={Activity={cx,ay,cw,h-ay-12}}
   end
  end
  if screen=="Trade"and layout then coach(w,h,mobile,layout)end
  local away=session.Portfolio and session.Portfolio.AwaySummary
  if AwayView.ShouldShow(away)and s.AwaySeen~=away.Id then s.Overlay="Away"end
  overlay(w,h)
  if fx and key and key~=lastPopup then
   local dialog;for _,name in ipairs({"Dialog","ProtectionDialog","ShopDialog","OptionsSheet"})do dialog=dialog or canvas:FindFirstChild(name)end
   fx:Open(dialog,canvas:FindFirstChild("OverlayBackdrop")or canvas:FindFirstChild("SheetBackdrop"),dialog and dialog.Name=="OptionsSheet"and not(w>h))
   fx:Accent("Open")
  end
  lastPopup=key
  if s.Toast then toastView(w,h,mobile)end
  root:SetAttribute("Layout",mobile and"Mobile"or"Desktop");root:SetAttribute("SelectedContract",s.Contract)
  local pf=session.Portfolio
  root:SetAttribute("Screen",screen);root:SetAttribute("CoachStep",s.Coach);root:SetAttribute("ActiveAccount",pf and pf.Active)
  local blownKeys={};for _,r in ipairs(pf and pf.Accounts or{})do if r.Depleted then table.insert(blownKeys,r.Key..(r.Closing and":closing"or":ready"))end end
  root:SetAttribute("BlownAccounts",table.concat(blownKeys,","));root:SetAttribute("BlownNotice",s.Overlay=="Blown"and s.BlownTier or nil)
  root:SetAttribute("NetRealized",pf and pf.Earned)
  root:SetAttribute("Theme","Colorful Game")
  updateUnlockReadout()
  root:SetAttribute("Balance",sum.Equity);root:SetAttribute("SettledBalance",sum.Balance);root:SetAttribute("Equity",sum.Equity);root:SetAttribute("UnrealizedPnL",sum.Unrealized)
  root:SetAttribute("PositionCount",sum.Count);root:SetAttribute("WorkingOrderCount",#session:Working());root:SetAttribute("Simulated",true);root:SetAttribute("SessionSeed",nil);root:SetAttribute("MarketStep",session.Step or 0)
  root:SetAttribute("ExchangeStatus",session.ConnectionStatus or "EDIT PREVIEW")
  root:SetAttribute("EditPreview",options.Preview==true)
  runEffects()
 end
 render=function(keepTicket)
  local ok,err=xpcall(function()renderNow(keepTicket)end,debug.traceback)
  if not ok then
   -- Keep the workspace usable: the next refresh rebuilds everything from state.
   painting=nil;warn("[Get Funded!] Workspace render failed; it will rebuild on the next update: "..tostring(err))
   root:SetAttribute("RenderError",tostring(err):sub(1,200))
  end
 end
 table.insert(connections,root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
  if math.abs(root.AbsoluteSize.X-lastW)>1 or math.abs(root.AbsoluteSize.Y-lastH)>1 then s.ContractAnchor=nil;refresh()end
 end))
 if not options.Preview then
  table.insert(connections,UIS.InputBegan:Connect(function(ev,processed)
   if ev.UserInputType==Enum.UserInputType.Keyboard then
    -- Chart keys (Esc, Delete/Backspace, Ctrl+Z/Y, Ctrl for magnet) are ignored while typing.
    if chartView:KeyBegan(ev)then return end
    if not processed and ev.KeyCode==Enum.KeyCode.Escape then
     if s.Overlay=="Protection"then closeProtection();return end
     s.ProtectionDraft=nil;s.Overlay=nil;s.Sheet=false;refresh()
    end
   end
  end))
  table.insert(connections,UIS.InputEnded:Connect(function(ev)
   if ev.UserInputType==Enum.UserInputType.Keyboard then chartView:KeyEnded(ev)else chartView:Ended(ev)end
  end))
  table.insert(connections,UIS.InputChanged:Connect(function(ev)chartView:Changed(ev)end))
  table.insert(connections,UIS.WindowFocusReleased:Connect(function()chartView:FocusLost()end))
  -- Esc opens the Roblox menu in-game (games never receive it); treat that as cancel too.
  table.insert(connections,game:GetService("GuiService").MenuOpened:Connect(function()chartView:FocusLost()end))
  local paintElapsed=0;local depthElapsed=0
  table.insert(connections,RunService.RenderStepped:Connect(function(dt)
   paintElapsed+=dt
   depthElapsed+=dt;if depthElapsed>=1 then depthElapsed=0;updateLevel2();if s.Overlay=="Shop"then depthPurchase:Refresh();updateShop()end end
   leaderboard:Step()
   chartView:Step(dt)
   -- Input, easing and network batches share one paint per display frame.
   if chartView.Dirty or chartView.HoverDirty then repaintChart()end
   if RunService:IsStudio()and paintElapsed>=1 then
    paintElapsed=0;root:SetAttribute("ChartPaintCount",chartView.PaintCount)
    root:SetAttribute("ChartPaintMeanMs",chartView.PaintTotal/math.max(1,chartView.PaintCount));root:SetAttribute("ChartPaintMaxMs",chartView.PaintMax)
    root:SetAttribute("ChartPaintLastMs",chartView.LastCost)
    root:SetAttribute("ChartOverlayPaintCount",chartView.OverlayPaintCount or 0)
    root:SetAttribute("ChartOverlayMeanMs",(chartView.OverlayPaintTotal or 0)/math.max(1,chartView.OverlayPaintCount or 0))
   end
  end))
  local lastStructure=""
  local function portfolioSignature()
   local pf=session.Portfolio;if not pf then return"none"end
   local parts={tostring(pf.New),tostring(pf.Revision),tostring(pf.Active),string.format("%.2f",pf.Earned or 0),tostring(pf.Progress),pf.Next and tostring(pf.Next.Goal)..":"..tostring(pf.Next.Progress)or"complete",tostring(pf.ActiveCount)}
   for _,list in ipairs({pf.Accounts or{}})do
    for _,r in ipairs(list)do table.insert(parts,r.Key..(r.State or"L")..tostring(r.Usable)..tostring(r.Retired)..tostring(r.Locked)..tostring(r.Inactive)..tostring(r.Breached)..tostring(r.Closing)..tostring(r.CanRestart)..tostring(r.CanReset)..tostring(r.DepletionEvent)..tostring(r.OpenContracts)..string.format("%.2f",r.Balance or 0)..":"..tostring(r.Positions)..":"..tostring(r.Orders))end
   end
   return table.concat(parts,"|")
  end
  local triggersSeen={}
  local function marketUpdate()
   if not alive then return end
   updateLevel2()
   updateShop()
   restoreProtectionPreferences()
   local maximum=quantityLimit()
   s.Qty=math.clamp(s.Qty,math.min(1,maximum),maximum)
   local away=session.Portfolio and session.Portfolio.AwaySummary
   local showAway=AwayView.ShouldShow(away)and s.AwaySeen~=away.Id
   if showAway and s.Overlay~="Away"or not showAway and s.Overlay=="Away"then refresh();return end
   if currentScreen()=="Leaderboard"then
    local pf=session.Portfolio;local rail=canvas:FindFirstChild("Sidebar")
    if rail and pf and rail.Rank.Text~=pf.Rank then refresh()end
    return
   end
   if #blownQueue>0 and not s.Overlay then nextBlown()end
   updateProtectionReadout()
   updateUnlockReadout()
   local cancelled=chartView:OnMarketUpdate()
   if cancelled then toast(cancelled)end
   -- Stop entries trigger on the server; report each one once (not the ones already there on join).
   local seenKey=tostring(session.AccountKey)
   if triggersSeen.Key~=seenKey then triggersSeen={Key=seenKey,Ids={}};for _,t in ipairs(session.Triggers or{})do triggersSeen.Ids[t.Id]=true end end
   for i=#(session.Triggers or{}),1,-1 do
    local t=session.Triggers[i]
    if not triggersSeen.Ids[t.Id]then
     triggersSeen.Ids[t.Id]=true
     local what=(t.Direction>0 and"Stop buy "or"Stop sell ")..t.Quantity.." "..t.Contract.." @ "..Market.Number(t.Price)
     if t.Queued then s.Tab="Orders";toast(what.." triggered · "..t.Filled.." filled, "..t.Remaining.." queued. View or cancel in Orders.","info")
     elseif t.Ok then toast(what.." triggered · filled "..t.Filled.." @ "..Market.Number(t.Average or t.Price),"success");if fx then fx:Play("Success")end
     else fail(what.." triggered but was not filled: "..tostring(t.Message or"no liquidity"))end
    end
   end
   if coachProgress()then refresh()end
   local screen=currentScreen()
   local signature=screen..":"..tostring(session.AccountKey)..":"..tostring(session.CanTrade)..":"..#session.Orders..":"..#session.History..":"..portfolioSignature()
   -- A new server Stats packet (after a close, depletion or restart) rebuilds the Stats page.
   if screen=="Stats"then signature..=":stats"..tostring(session.StatsAt)..tostring(session.ConnectionStatus)end
   for _,key in ipairs(Market.PositionOrder)do
    local p=session.Positions[key]
    if p then signature..=key..p.Quantity..":"..p.Entry..":"..tostring(p.Stop)..":"..tostring(p.Target)end
   end
   for _,o in ipairs(session.Orders)do signature..=":"..o.Id..":"..o.Quantity..":"..tostring(o.Price) end
   if signature~=lastStructure and not UIS:GetFocusedTextBox()then lastStructure=signature;refresh(true);return end
   -- Preserve controls, focus, scroll positions and overlays between network batches.
   local sum=session:Summary();local w,h=root.AbsoluteSize.X,root.AbsoluteSize.Y;local mobile=w<1000 or h<600
   local statsPage=canvas:FindFirstChild("Stats")
   if statsPage then StatsView.Update(statsContext(),statsPage)end
   local board=canvas:FindFirstChild("Dashboard")
   if board and session.Portfolio then
    -- Open P&L moves every batch; update it in place so dashboard buttons are never rebuilt mid-click.
    local pf=session.Portfolio;local kpi=board:FindFirstChild("KpiOpen")
    if kpi then kpi.Value.Text=Market.Signed(pf.Open or 0);kpi.Value.TextColor3=(pf.Open or 0)>=0 and SC.Green or SC.Red end

   end
   chartView.Dirty=true
   local metrics=canvas:FindFirstChild("AccountSummary")
   if metrics then
    local pnlIcon=metrics:FindFirstChild("UnrealizedCard")
    pnlIcon=pnlIcon and pnlIcon:FindFirstChild("IconPanel")
    if pnlIcon then
     pnlIcon.Rotation=0
     pnlIcon.ImageColor3=sum.Unrealized<0 and Color3.fromRGB(255,176,189)or Color3.new(1,1,1)
    end
    for _,field in ipairs({"Balance","Equity","Unrealized","Session","Allowance"})do
     local label=metrics:FindFirstChild(field.."Value",true)
     local value=field=="Balance"and sum.Equity or sum[field]
     if label then label.Text=(field=="Unrealized"or field=="Session")and Market.Signed(value)or Market.Money(value);if field=="Unrealized"or field=="Session"then label.TextColor3=value>=0 and SC.Green or SC.Red end end
    end
   end
   for _,panelName in ipairs({"OrderTicket","TradeDock","OptionsSheet"})do
    local panel=canvas:FindFirstChild(panelName)
    local quantity=panel and panel:FindFirstChild("Quantity",true)
    if quantity and not quantity.Value:IsFocused()then quantity.Value.Text=tostring(s.Qty)end
   end
   for _,panelName in ipairs({"OrderTicket","OptionsSheet"})do
    local panel=canvas:FindFirstChild(panelName);local label=panel and panel:FindFirstChild("CurrentPrice",true)
    if label then label.Text="Current "..Market.Number(session.Prices[s.Contract])end
   end
   local top=canvas:FindFirstChild("TopNavigation")
   if mobile and top and top:FindFirstChild("Account")and screen=="Trade"then
    local brand=top.Account:FindFirstChild("Brand");if brand then brand.Text=tradeStatus()end
   end
   local held=session.Positions[s.Contract]
   for _,name in ipairs({"OrderTicket","TradeDock"})do local panel=canvas:FindFirstChild(name)
    if panel and held then local label=panel:FindFirstChild("Pnl",true);if label then label.Text=Market.Signed(session:Pnl(held));label.TextColor3=session:Pnl(held)>=0 and C.Green or C.Red end end
   end
   local activityPanel=canvas:FindFirstChild("Activity")
   if activityPanel and s.Tab=="Positions"then
    local index=0
    for _,key in ipairs(Market.PositionOrder)do local p=session.Positions[key];if p then index+=1
     local row=activityPanel:FindFirstChild("Row"..index,true);local label=row and(row:FindFirstChild("Pnl")or row:FindFirstChild("Cell5"))
     if label then label.Text=Market.Signed(session:Pnl(p));label.TextColor3=session:Pnl(p)>=0 and C.Green or C.Red end
    end end
   end
   root:SetAttribute("ExchangeStatus",session.ConnectionStatus or "CONNECTING")
   root:SetAttribute("Balance",sum.Equity);root:SetAttribute("SettledBalance",sum.Balance);root:SetAttribute("Equity",sum.Equity);root:SetAttribute("UnrealizedPnL",sum.Unrealized)
   root:SetAttribute("MarketStep",session.Step or 0)
  end
  table.insert(connections,session.Changed.Event:Connect(marketUpdate))
  table.insert(connections,session.Replies.Event:Connect(function(reply)
   if reply.Kind=="ProtectionPreferences"then return end
   if reply.Kind=="AcknowledgeAway"then
    if not reply.Ok then s.AwaySeen=nil;refresh()end
    return
   end
   if reply.Kind=="ResetAccount"then
    s.PendingReset=nil
    if reply.Ok then s.Overlay=nil;blownQueue={};s.CoachDismissed=true end
   end
   chartView:OnReply(reply)
   s.Error=not reply.Ok and reply.Message or nil
   -- Server-confirmed feedback. Rejections are always audible; confirmations only for real actions.
   local order=s.PendingOrder and reply.RequestId==s.PendingOrder.Id and s.PendingOrder
   local closing=s.PendingClose and reply.RequestId==s.PendingClose.Id and s.PendingClose
   if order then s.PendingOrder=nil end
   if closing then s.PendingClose=nil end
   local restarting=s.PendingRestart and reply.RequestId==s.PendingRestart.Id and s.PendingRestart
   if restarting then s.PendingRestart=nil end

   if fx and reply.Kind~="Flag"then
    if not reply.Ok then
     fx:Play("Error")
     if order then effect(order.Direction>0 and tradePaths or sellPaths,"Error")end
    elseif order then
     fx:Play("Success");effect(order.Direction>0 and tradePaths or sellPaths,"Success",order.Direction>0 and C.Buy or C.Sell)
    elseif reply.Kind=="Start"or reply.Kind=="Restart"then fx:Play("Success")
    elseif reply.Kind=="Cancel"or reply.Kind=="AmendProtection"then fx:Play("Select")end
   end
   if reply.Ok and reply.Result then
    if reply.Result.Queued then s.Tab="Orders"elseif(reply.Result.Filled or 0)>0 then s.Tab="Positions"end
   end
   local pf=session.Portfolio
   if reply.Kind=="Start"then
    s.Starting=nil
    if reply.Ok then s.Screen="Trade";s.Nav="Trade";s.CoachDismissed=nil;if pf and pf.Tutorial=="Pending"then s.Coach=1;s.CoachBase=nil end end
   elseif (reply.Kind=="Restart"or reply.Kind=="ResetAccount")and reply.Ok then
    s.Overlay=nil;blownQueue={};s.Screen="Trade";s.Nav="Trade"
   end
   -- Full fills and accepted working orders stay quiet; incomplete fills must explain
   -- why the position differs from the requested quantity, including cancelled remainders.
   if reply.Ok and(reply.Kind=="Place"or order)then
    local result=reply.Result
    if result and (result.Queued or (result.Cancelled or 0)>0 or (result.Filled or 0)>0 and (result.Remaining or 0)>0) then
     toast(reply.Message,"info")
    else s.Toast=nil;refresh()end
   elseif reply.Ok and reply.Kind=="Close"and reply.Result and(reply.Result.Filled or 0)>0 then
    refresh() -- The matching TradeClosed event supplies the one close notification.
   elseif reply.Kind~="Flag"or not reply.Ok then
    toast(reply.Message,not reply.Ok and"error"or(closing or restarting)and"success"or"info")
   else refresh()end
  end))
  -- Events include any that arrived before the workspace mounted (e.g. a depletion while away).
  local announcedRank=session.Portfolio and session.Portfolio.RankId
  local depletedAccounts={}
  session:OnEvent(function(event)
   if not alive then return end
   if event.Kind=="Depleted"then
    depletedAccounts[event.Tier]=true
    -- Remove an already-visible close card and invalidate its delayed follow-up.
    if s.ToastPnl~=nil then toastId+=1;s.Toast=nil;s.ToastPnl=nil;s.ToastFollowup=nil end
    table.insert(blownQueue,{Tier=event.Tier,Event=event.Event})
    if fx then fx:Play("Error")end
    if s.Overlay~="Blown"then s.Overlay=nil;s.ProtectionDraft=nil;nextBlown()end
    refresh();return
   end
   if event.Kind=="TradeClosed" then
    local account=tierRow(event.Account)
    if event.Reason=="Account depleted"or depletedAccounts[event.Account]or account and account.Depleted then return end
    local pnl=event.Pnl or 0
    local notices={}
    local rewards=event.Rewards or {}
    if #rewards==1 then table.insert(notices,"Title earned: "..rewards[1])
    elseif #rewards>1 then table.insert(notices,#rewards.." titles earned")end
    -- Closing fills carry title rewards; the updated portfolio carries the earned rank.
    -- Announce awards after the compact close card, keeping its copy to title and P&L.
    local pf=session.Portfolio
    if pf and announcedRank and pf.RankId~=announcedRank then table.insert(notices,"Rank up: "..pf.Rank)end
    announcedRank=pf and pf.RankId or announcedRank
    toast("Trade closed · "..Market.Signed(pnl),pnl>0 and"success"or"info",pnl,#notices>0 and table.concat(notices," · ")or nil)
    if event.Reason=="Take profit"then
     if fx then fx:PlayFill("TakeProfit")end
    elseif event.Reason=="Stop loss"then
     if fx then fx:PlayFill("StopLoss")end
    else
     if fx then fx:Play("Success")end
    end
   elseif event.Kind=="RankUp" then announcedRank=event.Id;if fx then fx:Play("Milestone")end;toast("Rank up: "..event.Name,"success")
   elseif event.Kind=="Milestone" then if fx then fx:Play("Milestone") end;celebrate(event) end
   refresh()
  end)
 end
 table.insert(connections,leaderboard.Changed.Event:Connect(refresh))
 render()
 -- Studio-only layout/test hook: read or set presentation state and rebuild synchronously.
 if RunService:IsStudio()and not options.Preview then
  local hook=Instance.new("BindableFunction");hook.Name="UIDiagnostics";hook.Parent=root
  hook.OnInvoke=function(command,key,value)
   if command=="Set"then s[key]=value;render();return true
   elseif command=="Get"then return s[key]
   elseif command=="Render"then render();return true end
   return nil
  end
 end
 local controller={Root=root,State=s,Chart=chartView}
 function controller:Destroy()alive=false;depthPurchase:Destroy();for _,view in ipairs(depthViews)do view:Destroy()end;leaderboard:Destroy();chartView:Destroy();session:Destroy();if feedback then feedback:Destroy()end;if fx==feedback then fx=nil end;for _,c in ipairs(connections)do c:Disconnect()end;if root.Parent then root:Destroy()end end
 return controller
end
return UI
