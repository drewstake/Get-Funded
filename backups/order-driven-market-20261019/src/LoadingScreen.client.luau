-- Get Funded! loading screen (ReplicatedFirst). Replaces Roblox's default screen on every join and shows
-- the real loading stages: game content, the trading desk, your account, live prices, then artwork and
-- sounds. It never waits for anything but that work; when the exchange is slow it says why and offers a
-- way in. The finish is a "You're in!" moment and a camera dolly through the scene into the terminal.
local ReplicatedFirst=game:GetService("ReplicatedFirst")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local ContentProvider=game:GetService("ContentProvider")
local GuiService=game:GetService("GuiService")
local SoundService=game:GetService("SoundService")
local TextService=game:GetService("TextService")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
player:SetAttribute("GetFundedLoading",true)

-- Comfort settings shared with the trading terminal and the welcome guide for this session.
local function calm()
 local v=player:GetAttribute("GetFundedReducedMotion")
 if v==nil then local ok,r=pcall(function()return GuiService.ReducedMotionEnabled end);return ok and r==true end
 return v==true
end
local function soundOn()return player:GetAttribute("GetFundedSoundOn")~=false end

local INK=Color3.fromRGB(3,18,55)
local P={Text=Color3.fromRGB(245,249,255),Muted=Color3.fromRGB(176,214,255),Cyan=Color3.fromRGB(0,220,255),Green=Color3.fromRGB(46,249,160),
 Red=Color3.fromRGB(255,81,127),Gold=Color3.fromRGB(255,222,40),GoldDark=Color3.fromRGB(255,150,0),Purple=Color3.fromRGB(150,70,255),Navy=Color3.fromRGB(5,39,111)}
local FONT=Enum.Font.FredokaOne

local function new(class,name,parent,props)
 local o=Instance.new(class);o.Name=name
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function box(parent,name,color,z,props)
 local f=new("Frame",name,parent,{BackgroundColor3=color or P.Navy,BorderSizePixel=0,ZIndex=z or 1,Active=false})
 for k,v in pairs(props or {})do f[k]=v end
 return f
end
local function corner(o,r)return new("UICorner","Corners",o,{CornerRadius=typeof(r)=="UDim"and r or UDim.new(0,r or 12)})end
local function outline(o,color,t)return new("UIStroke","Border",o,{Color=color or INK,Thickness=t or 2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function gradient(o,a,b,rot)return new("UIGradient","Shade",o,{Color=ColorSequence.new(a,b),Rotation=rot or 90})end
local function label(parent,name,text,size,color,z,props)
 local l=new("TextLabel",name,parent,{BackgroundTransparency=1,Text=text,Font=FONT,TextSize=size,TextColor3=color or P.Text,ZIndex=z or 1,
  TextStrokeTransparency=1,TextWrapped=false})
 for k,v in pairs(props or {})do l[k]=v end
 return l
end
local function inked(l,t)return new("UIStroke","TextOutline",l,{Color=INK,Thickness=t or 2,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual,LineJoinMode=Enum.LineJoinMode.Round})end
local function seg(parent,name,x1,y1,x2,y2,width,color,z)
 local d=Vector2.new(x2-x1,y2-y1)
 local f=box(parent,name,color,z,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset((x1+x2)/2,(y1+y2)/2),
  Size=UDim2.fromOffset(d.Magnitude+width,width),Rotation=math.deg(math.atan2(d.Y,d.X))})
 corner(f,UDim.new(.5,0));return f
end

local gui=new("ScreenGui","GetFundedLoading",nil,{IgnoreGuiInset=true,ResetOnSpawn=false,DisplayOrder=100,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
pcall(function()gui.ScreenInsets=Enum.ScreenInsets.None end)
local root=box(gui,"Scene",Color3.new(1,1,1),1,{Size=UDim2.fromScale(1,1),Active=true})
new("UIGradient","Sky",root,{Rotation=90,Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(34,64,196)),
 ColorSequenceKeypoint.new(.45,Color3.fromRGB(14,30,116)),ColorSequenceKeypoint.new(1,Color3.fromRGB(64,26,158))})})
gui.Parent=playerGui
ReplicatedFirst:RemoveDefaultLoadingScreen()

local sounds={}
for name,spec in pairs({Pop={17208204604,.32,1.15},Success={17208380755,.38,1},Select={17208396156,.22,1.05}})do
 sounds[name]=new("Sound",name,gui,{SoundId="rbxassetid://"..spec[1],Volume=spec[2],PlaybackSpeed=spec[3]})
end
local function play(name)if soundOn()and sounds[name]then sounds[name].TimePosition=0;sounds[name]:Play()end end

-- Depth layers. Each zooms around the screen centre during the reveal at its own rate (parallax dolly).
local function layer(name,z)
 local l=box(root,name,P.Navy,z,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1,1)})
 new("UIScale","Dolly",l);return l
end
local far,mid,near,sparkleLayer,starLayer,hud,top=layer("Far",2),layer("Mid",3),layer("Near",4),layer("Sparkles",5),layer("Stars",6),layer("Hud",7),layer("Moment",9)

-- Far: light beams, a soft skyline of bars and a bank of clouds (the game icon's backdrop).
local beams={}
for i=1,4 do beams[i]=box(far,"Beam"..i,Color3.fromRGB(150,210,255),2,{BackgroundTransparency=.93,AnchorPoint=Vector2.new(.5,.5)})end
local bars={}
for i=1,14 do
 local h=.1+((i*37)%11)/11*.24
 bars[i]=box(far,"Skyline"..i,Color3.fromRGB(56,96,230),2,{BackgroundTransparency=.62,AnchorPoint=Vector2.new(.5,1),
  Position=UDim2.fromScale((i-.5)/14,.98),Size=UDim2.fromScale(.032,h)})
 corner(bars[i],4)
end
for i,c in ipairs({{.04,.9,.22},{.2,.95,.2},{.36,.93,.24},{.55,.96,.22},{.72,.92,.24},{.9,.94,.24},{.12,.99,.26},{.46,1.02,.28},{.8,1.01,.28},{1,.98,.2}})do
 local puff=box(far,"Cloud"..i,i%2==0 and Color3.fromRGB(86,62,206)or Color3.fromRGB(70,48,184),3,{AnchorPoint=Vector2.new(.5,.5),
  Position=UDim2.fromScale(c[1],c[2]),Size=UDim2.fromScale(c[3],c[3]),SizeConstraint=Enum.SizeConstraint.RelativeXX})
 corner(puff,UDim.new(.5,0))
end

-- Mid: rising candles and the gold arrow swoosh from the game icon. Laid out in pixels on resize.
local CANDLES={{.12,.18,.24,.08},{.18,.3,.36,.14},{.26,.22,.34,.18},{.22,.38,.44,.2},{.36,.46,.5,.32},{.44,.4,.5,.36},
 {.4,.56,.6,.36},{.54,.66,.7,.5},{.62,.58,.68,.54},{.58,.76,.8,.56},{.72,.86,.9,.68},{.84,.96,1,.8}}
local candleParts={}
for i in ipairs(CANDLES)do
 local wick=box(mid,"Wick"..i,INK,2);corner(wick,2)
 local body=box(mid,"Candle"..i,Color3.new(1,1,1),3);corner(body,6);outline(body,INK,2)
 local up=CANDLES[i][2]>=CANDLES[i][1]
 gradient(body,up and Color3.fromRGB(120,255,170)or Color3.fromRGB(255,140,160),up and Color3.fromRGB(0,190,100)or Color3.fromRGB(226,36,80))
 candleParts[i]={Wick=wick,Body=body}
end
local swoosh=box(mid,"Swoosh",P.Gold,4,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
-- Candles grow up from their base in a quick stagger when the screen opens (instantly in calm mode).
local growing=not calm()
local function backOut(k)local c1=1.70158;local c3=c1+1;return 1+c3*(k-1)^3+c1*(k-1)^2 end
local function growCandles(t)
 local done=true
 for i,parts in ipairs(candleParts)do
  local g=parts.Target;if g then
   local k=t and math.clamp((t-.05*i)/.45,0,1)or 1
   if k<1 then done=false end
   local h=g.H*(k<1 and backOut(k)or 1)
   parts.Body.Position=UDim2.fromOffset(g.X,g.Bottom-h);parts.Body.Size=UDim2.fromOffset(g.W,math.max(0,h))
   parts.Wick.Visible=k>.3
  end
 end
 return done
end

-- Near: floating coins, market tickers and bills.
local floaters={}
local function coin(parent)
 local c=box(parent,"Coin",Color3.new(1,1,1),2);corner(c,UDim.new(.5,0));outline(c,INK,3);gradient(c,Color3.fromRGB(255,240,120),P.GoldDark)
 local ring=box(c,"Ring",P.Gold,2,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.72,.72)})
 corner(ring,UDim.new(.5,0));outline(ring,Color3.fromRGB(255,190,30),2)
 label(c,"Mark","$",10,Color3.fromRGB(186,96,0),3,{Size=UDim2.fromScale(1,1),TextScaled=true})
 return c
end
local function ticker(parent,symbol,change)
 local t=box(parent,"Ticker"..symbol,Color3.new(1,1,1),2);corner(t,UDim.new(.5,0));outline(t,P.Cyan,2);gradient(t,Color3.fromRGB(14,70,180),Color3.fromRGB(4,30,90))
 local l=label(t,"Text",symbol..'  <font color="#2EF9A0">'..change.."</font>",10,P.Text,3,{Size=UDim2.fromScale(1,1),TextScaled=true,RichText=true})
 new("UIPadding","Pad",l,{PaddingLeft=UDim.new(.12,0),PaddingRight=UDim.new(.12,0),PaddingTop=UDim.new(.2,0),PaddingBottom=UDim.new(.2,0)})
 return t
end
local function bill(parent)
 local b=box(parent,"Bill",Color3.new(1,1,1),2);corner(b,6);outline(b,INK,2);gradient(b,Color3.fromRGB(150,255,170),Color3.fromRGB(40,190,100))
 local seal=box(b,"Seal",Color3.fromRGB(220,255,226),3,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(.42,.42),SizeConstraint=Enum.SizeConstraint.RelativeYY})
 corner(seal,UDim.new(.5,0))
 label(seal,"Mark","$",10,Color3.fromRGB(0,120,70),4,{Size=UDim2.fromScale(1,1),TextScaled=true})
 return b
end
for _,f in ipairs({
 {"Coin",.09,.2,1},{"Ticker",.86,.17,1.6,"BX","+1.24%"},{"Bill",.9,.48,1.3},{"Coin",.93,.76,.8},
 {"Ticker",.1,.62,1.6,"BG","+0.86%"},{"Coin",.16,.86,.9},{"Ticker",.84,.9,1.6,"BT","+2.03%"},{"Bill",.06,.42,1.2},
})do
 local o=f[1]=="Coin"and coin(near)or f[1]=="Ticker"and ticker(near,f[5],f[6])or bill(near)
 o.AnchorPoint=Vector2.new(.5,.5)
 table.insert(floaters,{O=o,Kind=f[1],X=f[2],Y=f[3],K=f[4],Phase=math.random()*6,Speed=.7+math.random()*.6})
end
-- Sparkles: four-point twinkles.
local sparkles={}
for i=1,16 do
 local s=box(sparkleLayer,"Twinkle"..i,P.Text,2,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(math.random(),math.random()*.9+.05)})
 local rays={}
 for r=0,1 do local ray=box(s,"Ray",i%3==0 and P.Gold or i%3==1 and P.Cyan or P.Text,2,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=r==0 and UDim2.fromScale(.2,1)or UDim2.fromScale(.62,.2)});corner(ray,UDim.new(.5,0));rays[r+1]=ray end
 sparkles[i]={S=s,Rays=rays,Phase=math.random()*6,Speed=1.2+math.random()*1.8,Size=10+math.random()*14}
end

-- HUD: logo, tagline, progress card, tips, slow-load help and comfort toggles.
local logo=box(hud,"Logo",P.Navy,3,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,0)})
local logoScale=new("UIScale","Breath",logo)
local function logoLine(name,text,a,b,depth)
 local shadow=label(logo,name.."Depth",text,40,depth,3,{Size=UDim2.fromScale(1,.5),TextScaled=true})
 inked(shadow,4)
 local main=label(logo,name,text,40,Color3.new(1,1,1),4,{Size=UDim2.fromScale(1,.5),TextScaled=true})
 gradient(main,a,b);inked(main,4)
 return main,shadow
end
local getLine,getDepth=logoLine("Get","GET",Color3.new(1,1,1),Color3.fromRGB(196,214,255),Color3.fromRGB(70,90,170))
local fundedLine,fundedDepth=logoLine("Funded","FUNDED!",Color3.fromRGB(255,246,130),P.GoldDark,Color3.fromRGB(176,82,0))
local tagPill=box(hud,"TaglinePill",Color3.fromRGB(4,22,80),2,{AnchorPoint=Vector2.new(.5,0),BackgroundTransparency=.3});corner(tagPill,UDim.new(.5,0))
local tagline=label(hud,"Tagline","Trade the Blox markets · Earn your rank",16,P.Text,3,{AnchorPoint=Vector2.new(.5,0)})
inked(tagline,1.5)

local card=box(hud,"Progress",Color3.new(1,1,1),5,{AnchorPoint=Vector2.new(.5,0)})
corner(card,20);outline(card,P.Cyan,3);gradient(card,Color3.fromRGB(70,38,200),Color3.fromRGB(6,40,116))
local status=label(card,"Status","Unpacking the trading floor…",20,P.Text,6,{TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
inked(status,2)
local percent=label(card,"Percent","0%",20,P.Gold,6,{TextXAlignment=Enum.TextXAlignment.Right});inked(percent,2)
local track=box(card,"Track",INK,6);corner(track,UDim.new(.5,0))
local well=box(track,"Well",Color3.fromRGB(10,34,96),6,{Position=UDim2.fromOffset(3,3)});corner(well,UDim.new(.5,0));outline(well,Color3.fromRGB(40,80,170),1)
local fill=box(well,"Fill",Color3.new(1,1,1),7,{Size=UDim2.fromScale(0,1),ClipsDescendants=true});corner(fill,UDim.new(.5,0))
gradient(fill,Color3.fromRGB(255,248,137),Color3.fromRGB(255,170,10))
local shine=box(fill,"Shine",Color3.new(1,1,1),8,{BackgroundTransparency=.55,Size=UDim2.new(0,26,1,0),Rotation=18})
local gleam=box(fill,"Gleam",Color3.new(1,1,1),8,{BackgroundTransparency=.5,Position=UDim2.new(0,8,0,3),Size=UDim2.new(1,-16,0,3)});corner(gleam,2)
local detail=label(card,"Detail","Getting ready",14,P.Muted,6,{TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd})
local divider=box(card,"Divider",P.Cyan,6,{BackgroundTransparency=.7})
local tipButton=new("TextButton","Tip",card,{BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=6})
local tipChip=box(tipButton,"Chip",Color3.new(1,1,1),7);corner(tipChip,UDim.new(.5,0));outline(tipChip,Color3.fromRGB(255,244,120),2)
gradient(tipChip,P.Gold,P.GoldDark)
local tipChipText=label(tipChip,"Label","TIP",12,Color3.fromRGB(120,50,0),8,{Size=UDim2.fromScale(1,1)})
local tipText=label(tipButton,"Text","",15,P.Text,7,{TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true})
local slow=box(card,"Slow",Color3.fromRGB(3,24,70),6,{Visible=false});corner(slow,14);outline(slow,P.Gold,2)
local slowText=label(slow,"Text","Taking longer than usual. Your account and trades are safe.",14,P.Text,7,{TextXAlignment=Enum.TextXAlignment.Left,TextWrapped=true})
local enter=new("TextButton","EnterAnyway",slow,{Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),ZIndex=7})
corner(enter,12);outline(enter,Color3.fromRGB(129,255,202),2);gradient(enter,Color3.fromRGB(34,253,158),Color3.fromRGB(0,173,112))
local enterText=label(enter,"Label","Enter anyway",16,P.Text,8,{Size=UDim2.fromScale(1,1)});new("UIStroke","TextOutline",enterText,{Color=Color3.fromRGB(0,112,72),Thickness=1.5})

local TIPS={
 "BUY if you think the price will rise. SELL if you think it will fall.",
 "A stop loss closes a losing trade early, so one bad call stays small.",
 "Take profit cashes in a winner at your target, even while you look away.",
 "Close 25 trades to earn the Opening Bell title and +$2,500 on every fresh start.",
 "Every $1,000 of settled balance lets you trade one more contract (minimum 5).",
 "Blox Gold moves $10 per tick per contract. The Blox 500 moves $12.50.",
 "Open trades keep running while you're away. Close them when you're done.",
 "Hit $0 and your account fails. Restart free and keep your ranks and titles.",
 "Climb from Market Rookie to Market Sovereign by trading, winning and growing profit.",
 "Limit orders only fill at your price or better.",
}
local tipIndex=math.random(#TIPS)
tipText.Text=TIPS[tipIndex]

local function pill(name,text)
 local b=new("TextButton",name,hud,{Text="",AutoButtonColor=false,BackgroundColor3=Color3.new(1,1,1),ZIndex=8,AnchorPoint=Vector2.new(1,1)})
 corner(b,UDim.new(.5,0));outline(b,P.Cyan,2);gradient(b,Color3.fromRGB(14,70,180),Color3.fromRGB(4,30,90))
 local l=label(b,"Label",text,15,P.Text,9,{Size=UDim2.fromScale(1,1)});inked(l,1.5)
 new("UIScale","Press",b)
 return b,l
end
local soundButton,soundLabel=pill("SoundToggle","")
local motionButton,motionLabel=pill("MotionToggle","")
local hint=label(hud,"StarHint","Psst… tap the floating stars!",15,P.Gold,4,{AnchorPoint=Vector2.new(.5,0),TextTransparency=1});inked(hint,1.5)
local counter=box(hud,"PopCounter",Color3.new(1,1,1),8,{AnchorPoint=Vector2.new(1,0),Visible=false});corner(counter,UDim.new(.5,0));outline(counter,P.Gold,2)
gradient(counter,Color3.fromRGB(70,38,200),Color3.fromRGB(6,40,116))
local counterText=label(counter,"Label","",16,P.Text,9,{Size=UDim2.fromScale(1,1)});inked(counterText,1.5)
local cheer=label(hud,"Cheer","",15,P.Gold,9,{AnchorPoint=Vector2.new(1,0),TextXAlignment=Enum.TextXAlignment.Right,TextTransparency=1});inked(cheer,1.5)

local function refreshToggles()
 soundLabel.Text=soundOn()and"Sound: On"or"Sound: Off"
 motionLabel.Text=calm()and"Motion: Calm"or"Motion: On"
end
refreshToggles()
local function press(b)
 local s=b:FindFirstChild("Press");if not s then return end
 if calm()then return end
 s.Scale=.9;TweenService:Create(s,TweenInfo.new(.25,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
end
for _,b in ipairs({soundButton,motionButton,enter})do
 local s=b:FindFirstChild("Press")or new("UIScale","Press",b)
 b.MouseEnter:Connect(function()if not calm()then TweenService:Create(s,TweenInfo.new(.12),{Scale=1.05}):Play()end end)
 b.MouseLeave:Connect(function()TweenService:Create(s,TweenInfo.new(.12),{Scale=1}):Play()end)
end

-- Bucky peeks over the progress card once the game's modules have arrived.
local mascot,mascotSize
local function addMascot()
 local folder=game:GetService("ReplicatedStorage"):WaitForChild("MarketReign",20)
 local module=folder and folder:WaitForChild("Mascot",10)
 if not module or not gui.Parent then return end
 local ok,Mascot=pcall(require,module);if not ok then return end
 mascot=Mascot.new(hud,mascotSize or 80,{Calm=calm(),ZIndex=4,Name="Bucky"})
 mascot.Root.AnchorPoint=Vector2.new(1,1)
 mascot:Wave(1.6)
end

-- Layout (re-run on every resize and rotation).
local W,H=0,0
local cardH=0
local function topInset()
 local inset=GuiService:GetGuiInset()
 local ok,bar=pcall(function()return GuiService.TopbarInset end)
 return math.max(inset.Y,ok and bar.Max.Y or 0)
end
local function layout()
 W,H=root.AbsoluteSize.X,root.AbsoluteSize.Y
 if W<=0 or H<=0 then return end
 local m=math.min(W,H);local safeTop=topInset()+8
 local compact=H<520;local narrow=W<560
 local togglesH=compact and 40 or 44;local bottomPad=12
 local cardW=math.min(compact and 520 or 560,W-32)
 -- Comfort toggles sit in the side margin when there is room (side by side, else stacked);
 -- otherwise they get their own row along the bottom.
 local pw=compact and 120 or 140
 local sideRoom=(W-cardW)/2-16
 local togglesMode=sideRoom>=pw*2+16 and"Row"or sideRoom>=pw+8 and"Stack"or"Bottom"
 local reserve=togglesMode=="Bottom"and togglesH+bottomPad+10 or bottomPad
 local avail=H-safeTop-reserve
 -- Tall phones: the rising chart moves into its own band below the card so the logo stays clean.
 local portrait=H>W*1.25
 local chartBand=portrait and math.clamp(avail*.24,110,240)or 0
 local pad=compact and 12 or 16
 local tipH=compact and 38 or 46
 cardH=pad+26+8+(compact and 20 or 26)+6+18+10+1+8+tipH+pad
 local slowH=slow.Visible and(compact and 52 or 60)+10 or 0
 cardH+=slowH
 -- Bucky peeks over the card's top-right corner (room left below the tagline), or on short
 -- landscape screens stands beside the card's left edge.
 mascotSize=math.clamp(math.floor(cardH*.42),48,compact and 64 or 78)
 local beside=compact and sideRoom>=mascotSize+8
 local gapL=math.clamp(avail*.05,8,40)
 if not beside then gapL=math.max(gapL,mascotSize*.95)end
 -- Short landscape screens drop the tagline; the logo takes whatever height is left.
 local fundedSize=math.min(W*(portrait and .18 or .15),avail*(compact and .2 or .15))
 local tagH=compact and 0 or math.clamp(math.floor(fundedSize*.24),13,22)
 fundedSize=math.clamp(math.min(fundedSize,(avail-6-tagH-gapL-cardH-chartBand)/1.86),24,120)
 tagline.Visible=not compact
 local logoH=math.floor(fundedSize*1.86)
 local logoW=math.floor(fundedSize*4.6)
 local total=logoH+6+tagH+gapL+cardH+chartBand
 local y0=safeTop+math.max(0,(avail-total)*(portrait and .5 or .42))
 logo.Position=UDim2.fromOffset(W/2,y0);logo.Size=UDim2.fromOffset(logoW,logoH)
 local depth=math.max(3,math.floor(fundedSize*.07))
 getLine.Size=UDim2.new(.62,0,.44,0);getLine.Position=UDim2.fromScale(.19,0);getDepth.Size=getLine.Size;getDepth.Position=getLine.Position+UDim2.fromOffset(0,depth)
 fundedLine.Size=UDim2.new(1,0,.56,0);fundedLine.Position=UDim2.fromScale(0,.44);fundedDepth.Size=fundedLine.Size;fundedDepth.Position=fundedLine.Position+UDim2.fromOffset(0,depth)
 for _,l in ipairs({getLine,getDepth,fundedLine,fundedDepth})do l.TextOutline.Thickness=math.max(2,fundedSize*.06)end
 tagline.TextSize=math.max(12,tagH-4)
 local tagW=math.min(W-32,TextService:GetTextSize(tagline.Text,tagline.TextSize,FONT,Vector2.new(2000,100)).X+30)
 tagline.Position=UDim2.fromOffset(W/2,y0+logoH+6);tagline.Size=UDim2.fromOffset(tagW,tagH)
 tagPill.Visible=tagline.Visible;tagPill.Position=tagline.Position-UDim2.fromOffset(0,2);tagPill.Size=UDim2.fromOffset(tagW,tagH+4)
 local cy=y0+logoH+6+tagH+gapL
 card.Position=UDim2.fromOffset(W/2,cy);card.Size=UDim2.fromOffset(cardW,cardH)
 local iw=cardW-pad*2;local y=pad
 status.Position=UDim2.fromOffset(pad,y);status.Size=UDim2.fromOffset(iw-70,26);status.TextSize=compact and 18 or narrow and 18 or 21
 percent.Position=UDim2.fromOffset(pad+iw-66,y);percent.Size=UDim2.fromOffset(66,26);percent.TextSize=status.TextSize;y+=26+8
 local barH=compact and 20 or 26
 track.Position=UDim2.fromOffset(pad,y);track.Size=UDim2.fromOffset(iw,barH)
 well.Size=UDim2.new(1,-6,1,-6);y+=barH+6
 detail.Position=UDim2.fromOffset(pad+2,y);detail.Size=UDim2.fromOffset(iw-4,18);detail.TextSize=compact and 13 or 14;y+=18+10
 divider.Position=UDim2.fromOffset(pad,y);divider.Size=UDim2.fromOffset(iw,1);y+=1+8
 tipButton.Position=UDim2.fromOffset(pad,y);tipButton.Size=UDim2.fromOffset(iw,tipH)
 tipChip.Position=UDim2.fromOffset(0,(tipH-24)/2);tipChip.Size=UDim2.fromOffset(46,24)
 tipText.Position=UDim2.fromOffset(56,0);tipText.Size=UDim2.fromOffset(iw-56,tipH);tipText.TextSize=compact and 13 or narrow and 14 or 15
 y+=tipH+10
 if slow.Visible then
  local sh=compact and 52 or 60
  slow.Position=UDim2.fromOffset(pad,y);slow.Size=UDim2.fromOffset(iw,sh)
  local bw=enter.Visible and math.min(150,math.floor(iw*.4))or -14
  slowText.Position=UDim2.fromOffset(12,0);slowText.Size=UDim2.fromOffset(iw-bw-30,sh);slowText.TextSize=compact and 12 or 14
  enter.Position=UDim2.fromOffset(iw-bw-8,(sh-44)/2);enter.Size=UDim2.fromOffset(bw,44)
 end
 hint.Position=UDim2.fromOffset(W/2,cy+cardH+8);hint.Size=UDim2.fromOffset(W-32,20)
 hint.Visible=cy+cardH+30<=H-reserve or togglesMode~="Bottom"
 soundButton.Size=UDim2.fromOffset(pw,togglesH);motionButton.Size=UDim2.fromOffset(pw,togglesH)
 motionButton.Position=UDim2.fromOffset(W-16,H-bottomPad)
 soundButton.Position=togglesMode=="Stack"and UDim2.fromOffset(W-16,H-bottomPad-togglesH-8)or UDim2.fromOffset(W-16-pw-8,H-bottomPad)
 counter.Position=UDim2.fromOffset(W-16,safeTop+4);counter.Size=UDim2.fromOffset(112,36)
 cheer.Position=UDim2.fromOffset(W-16,safeTop+46);cheer.Size=UDim2.fromOffset(240,20)
 -- Beams fan out from above the top centre.
 for i,b in ipairs(beams)do
  local angle=math.rad(-36+(i-1)*24);local len=H*1.5
  b.Size=UDim2.fromOffset(W*.07,len);b.Rotation=-math.deg(angle)
  b.Position=UDim2.fromOffset(W/2+math.sin(angle)*len/2,-H*.08+math.cos(angle)*len/2)
 end
 -- Candles fill a band behind the logo and run up to the right, like the icon.
 local bandX,bandW=W*.08,W*.84;local bandTop,bandBottom=math.max(safeTop,H*.08),H*.56
 if portrait then bandTop=cy+cardH+44;bandBottom=bandTop+chartBand-24 end
 local cw=math.clamp(bandW/#CANDLES*.48,10,44)
 for i,c in ipairs(CANDLES)do
  local x=bandX+(i-.5)/#CANDLES*bandW
  local function Y(v)return bandBottom-(bandBottom-bandTop)*v end
  local open,close,high,low=c[1],c[2],c[3],c[4]
  local parts=candleParts[i]
  local bodyTop,bodyBottom=Y(math.max(open,close)),Y(math.min(open,close))
  parts.Target={X=x-cw/2,Bottom=bodyBottom,W=cw,H=math.max(8,bodyBottom-bodyTop)}
  parts.Wick.Position=UDim2.fromOffset(x-math.max(2,cw*.12)/2,Y(high));parts.Wick.Size=UDim2.fromOffset(math.max(2,cw*.12),Y(low)-Y(high))
 end
 if not growing then growCandles(nil)end
 swoosh:ClearAllChildren()
 local th=math.clamp(m*.024,8,22)
 local pts={}
 for i=0,12 do
  local t=i/12
  local x=W*(.04+.84*t);local y=bandBottom+(H*.04)-(bandBottom-bandTop)*(.05+.8*t^1.6)
  pts[#pts+1]=Vector2.new(x,y)
 end
 local tip=pts[#pts];local dir=(tip-pts[#pts-1]).Unit
 for pass=1,2 do
  local width=pass==1 and th+6 or th;local color=pass==1 and INK or P.Gold;local z=pass==1 and 4 or 5
  for i=1,#pts-1 do seg(swoosh,"Arc",pts[i].X,pts[i].Y,pts[i+1].X,pts[i+1].Y,width,color,z)end
 end
 -- Arrowhead: a ▲ glyph turned to the curve's final direction.
 local at=tip+dir*th*.9
 local head=label(swoosh,"Head","▲",40,Color3.new(1,1,1),6,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(at.X,at.Y),
  Size=UDim2.fromOffset(th*5.2,th*5.2),TextScaled=true,Rotation=math.deg(math.atan2(dir.Y,dir.X))+90})
 gradient(head,Color3.fromRGB(255,246,130),P.GoldDark);inked(head,3)
 for _,f in ipairs(floaters)do
  local size=math.clamp(m*.075,30,64)*f.K
  if f.Kind=="Ticker"then f.O.Size=UDim2.fromOffset(size*1.15,size*.42)
  elseif f.Kind=="Bill"then f.O.Size=UDim2.fromOffset(size*.9,size*.5)
  else f.O.Size=UDim2.fromOffset(size,size)end
 end
 for _,s in ipairs(sparkles)do s.S.Size=UDim2.fromOffset(s.Size,s.Size)end
 if mascot then
  mascot:SetSize(mascotSize)
  mascot.Root.Position=beside and UDim2.fromOffset(W/2-cardW/2-6,cy+cardH)or UDim2.fromOffset(W/2+cardW/2-14,cy+mascotSize*.42)
 end
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()
task.spawn(function()
 if not game:IsLoaded()then game.Loaded:Wait()end
 addMascot();layout()
end)

-- ── Real loading stages ─────────────────────────────────────────────────────────────────────────
local STAGES={
 {Key="Game",Weight=.22,Text="Unpacking the trading floor…"},
 {Key="Desk",Weight=.1,Text="Setting up your trading desk…"},
 {Key="Account",Weight=.3,Text="Ringing the opening bell…"},
 {Key="Prices",Weight=.14,Text="Pulling live prices…"},
 {Key="Art",Weight=.24,Text="Polishing the gold coins…"},
}
local stage={};for _,s in ipairs(STAGES)do stage[s.Key]=s;s.Sub=0;s.Detail="";s.Done=false end
local started=os.clock();local current,currentSince=nil,os.clock()
local maxQueue=1
local function terminal()
 local screen=playerGui:FindFirstChild("MarketReign");local ws=screen and screen:FindFirstChild("Workspace")
 if ws and ws:GetAttribute("EditPreview")~=true then return ws end
end
-- Friendly words for the exchange's own connection labels.
local function exchangeText(raw)
 if not raw or raw==""or raw=="EDIT PREVIEW"or raw=="CONNECTING"then return"Connecting to the exchange"end
 local map={["Connecting to the shared exchange"]="Connecting to the exchange",["Restoring the saved exchange"]="Restoring today's market, almost there",
  ["PAUSED · WAITING FOR SAVED EXCHANGE"]="The market is waking up. Hang tight",["Saved exchange unavailable · retrying safely"]="Exchange busy, retrying safely",
  ["Verifying the saved exchange"]="Double-checking the market",["Reconnecting to the saved exchange"]="Reconnecting to the market",["LOCAL · NOT SAVED"]="Studio sandbox · not saved",
  ["SHARED · SAVED"]="Connected"}
 return map[raw]or raw
end
local artStarted=false
local function startArt()
 if artStarted then return end;artStarted=true
 task.spawn(function()
  local ids,seen={},{}
  local function add(id)if type(id)=="string"and id~=""and not seen[id]then seen[id]=true;table.insert(ids,id)end end
  local screen=playerGui:FindFirstChild("MarketReign")
  for _,d in ipairs(screen and screen:GetDescendants()or{})do
   if d:IsA("ImageLabel")or d:IsA("ImageButton")then add(d.Image)end
  end
  local soundFolder=SoundService:FindFirstChild("GetFundedUISounds")
  for _,d in ipairs(soundFolder and soundFolder:GetChildren()or{})do if d:IsA("Sound")then add(d.SoundId)end end
  local s=stage.Art;local done=0
  s.Detail="Loading artwork and sounds · 0 / "..#ids
  if #ids>0 then
   pcall(function()
    ContentProvider:PreloadAsync(ids,function()
     done+=1;s.Sub=done/#ids;s.Detail="Loading artwork and sounds · "..done.." / "..#ids
    end)
   end)
  end
  s.Sub=1;s.Done=true
 end)
end
local function poll()
 local g=stage.Game
 if not g.Done then
  if game:IsLoaded()then g.Done=true
  else
   local q=ContentProvider.RequestQueueSize;maxQueue=math.max(maxQueue,q)
   g.Sub=math.max(g.Sub,1-q/maxQueue);g.Detail=q>0 and("Downloading game content · "..q.." left")or"Unpacking game content"
  end
 end
 local ws=terminal()
 if ws and not stage.Desk.Done then stage.Desk.Done=true end
 if not stage.Desk.Done then stage.Desk.Detail="Building charts, tickets and buttons" end
 local live=ws and ws:GetAttribute("EditPreview")==false
 local a=stage.Account
 if not a.Done then
  a.Detail=exchangeText(ws and ws:GetAttribute("ExchangeStatus"))
  if live and ws:GetAttribute("Screen")~=nil and ws:GetAttribute("Screen")~="Loading"then a.Done=true end
 end
 local p=stage.Prices
 if not p.Done then
  p.Detail="Blox 500 · BloxTech 100 · Blox Gold"
  if live and(ws:GetAttribute("MarketStep")or 0)>0 then p.Done=true end
 end
 if a.Done and not artStarted then startArt()end
 if not artStarted then stage.Art.Detail="Artwork and sounds" end
end

-- ── Interaction: poppable stars ─────────────────────────────────────────────────────────────────
local stars={};local pops=0;local nextStar=os.clock()+.6
local CHEERS={[5]="Nice catch!",[12]="Star trader!",[25]="To the moon!",[50]="Legendary!"}
local function burst(x,y)
 for i=1,8 do
  local a=i/8*math.pi*2
  local dot=box(starLayer,"Spark",i%2==0 and P.Gold or Color3.new(1,1,1),9,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(8,8)})
  corner(dot,UDim.new(.5,0))
  local t=TweenService:Create(dot,TweenInfo.new(.42,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(x+math.cos(a)*46,y+math.sin(a)*46),
   BackgroundTransparency=1,Size=UDim2.fromOffset(3,3)})
  t.Completed:Connect(function()dot:Destroy()end);t:Play()
 end
 local plus=label(starLayer,"PlusOne","+1",18,P.Gold,9,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(x,y-10),Size=UDim2.fromOffset(40,24)});inked(plus,1.5)
 local t=TweenService:Create(plus,TweenInfo.new(.6,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Position=UDim2.fromOffset(x,y-44),TextTransparency=1})
 t.Completed:Connect(function()plus:Destroy()end);t:Play()
end
local function drawStar(parent,size,z)
 local holder=box(parent,"Star",P.Gold,z,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(size,size)})
 local glow=box(holder,"Glow",P.Gold,z,{BackgroundTransparency=.78,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.56),Size=UDim2.fromScale(.9,.9)})
 corner(glow,UDim.new(.5,0))
 -- The star glyph renders at ~60% of its text box, so the label overhangs the holder.
 local star=label(holder,"Glyph","★",40,Color3.new(1,1,1),z+1,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromScale(1.7,1.7),TextScaled=true})
 gradient(star,Color3.fromRGB(255,250,170),P.GoldDark);inked(star,math.max(2,size*.07))
 return holder
end
local function spawnStar()
 local size=math.clamp(math.min(W,H)*.06,28,44)
 local hit=new("TextButton","PopStar",starLayer,{Text="",AutoButtonColor=false,BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),
  Size=UDim2.fromOffset(math.max(56,size*1.6),math.max(56,size*1.6)),ZIndex=6})
 local art=drawStar(hit,size,7)
 local scale=new("UIScale","Pop",art)
 local still=calm()
 local star={B=hit,Art=art,Scale=scale,X=.08+math.random()*.84,Y=still and(.2+math.random()*.6)or 1.06,Speed=.06+math.random()*.04,
  Sway=math.random()*6,Born=os.clock(),Life=still and 6 or nil}
 hit.Position=UDim2.fromScale(star.X,star.Y)
 if still then scale.Scale=.01;TweenService:Create(scale,TweenInfo.new(.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=1}):Play()end
 hit.Activated:Connect(function()
  if star.Popped then return end;star.Popped=true
  pops+=1;play("Pop")
  local p=hit.AbsolutePosition-starLayer.AbsolutePosition+hit.AbsoluteSize/2
  if not calm()then burst(p.X,p.Y)end
  counter.Visible=true;counterText.Text="★ "..pops
  if hint.TextTransparency<1 then TweenService:Create(hint,TweenInfo.new(.3),{TextTransparency=1}):Play()end
  if CHEERS[pops]then
   cheer.Text=CHEERS[pops];cheer.TextTransparency=0
   TweenService:Create(cheer,TweenInfo.new(1.6,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{TextTransparency=1}):Play()
   if mascot then mascot:SetMood("Wow");mascot:Hop();task.delay(.9,function()if mascot and mascot.Alive then mascot:SetMood("Happy")end end)end
  end
  local t=TweenService:Create(scale,TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Scale=calm()and .01 or 1.5})
  TweenService:Create(art.Glyph,TweenInfo.new(.16),{TextTransparency=1}):Play();TweenService:Create(art.Glyph.TextOutline,TweenInfo.new(.16),{Transparency=1}):Play()
  TweenService:Create(art.Glow,TweenInfo.new(.16),{BackgroundTransparency=1}):Play()
  t.Completed:Connect(function()hit:Destroy()end);t:Play()
 end)
 table.insert(stars,star)
end

-- ── Reveal: "You're in!", then a camera dolly through the scene into the terminal ─────────────
local revealing,finished=false,false
local display,target=0,0
local loop
local function finish()
 if finished then return end;finished=true
 if loop then loop:Disconnect()end
 if mascot then mascot:Destroy();mascot=nil end
 player:SetAttribute("GetFundedLoading",false)
 gui:Destroy()
end
local function reveal(early)
 if revealing then return end;revealing=true
 local still=calm()
 status.Text=early and"Heading in…"or"You're in!";status.TextColor3=P.Gold
 detail.Text=early and"The terminal keeps connecting in the background"or"Welcome to the trading floor"
 target=1;percent.Text="100%"
 TweenService:Create(fill,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromScale(1,1)}):Play()
 play("Success")
 local badge=box(top,"YoureIn",Color3.new(1,1,1),2,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.46)})
 local bw=math.clamp(math.min(W,H)*.62,240,460)
 badge.Size=UDim2.fromOffset(bw,bw*.3);corner(badge,UDim.new(.5,0));outline(badge,INK,5);gradient(badge,Color3.fromRGB(255,246,130),P.GoldDark)
 local shineBar=box(badge,"Shine",Color3.new(1,1,1),3,{BackgroundTransparency=.45,Position=UDim2.new(.1,0,.12,0),Size=UDim2.new(.8,0,.08,0)});corner(shineBar,UDim.new(.5,0))
 local words=label(badge,"Label",early and"HERE WE GO!"or"YOU'RE IN!",40,Color3.new(1,1,1),4,{Size=UDim2.fromScale(.86,.74),Position=UDim2.fromScale(.07,.13),TextScaled=true})
 new("UIStroke","TextOutline",words,{Color=Color3.fromRGB(150,60,0),Thickness=math.max(2,bw*.012),LineJoinMode=Enum.LineJoinMode.Round})
 local pop=new("UIScale","Pop",badge)
 local tapSkip=new("TextButton","SkipReveal",top,{Text="",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),ZIndex=1})
 tapSkip.Activated:Connect(finish)
 if still then
  pop.Scale=1;badge.BackgroundTransparency=1;words.TextTransparency=1
  TweenService:Create(badge,TweenInfo.new(.25),{BackgroundTransparency=0}):Play();TweenService:Create(words,TweenInfo.new(.25),{TextTransparency=0}):Play()
 else
  pop.Scale=.3;TweenService:Create(pop,TweenInfo.new(.38,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 end
 if mascot then mascot:SetMood("Happy");mascot:Hop();mascot:Wave(1)end
 task.spawn(function()
  local ok,Confetti=pcall(function()return require(game:GetService("ReplicatedStorage").MarketReign.Confetti)end)
  if ok and Confetti and top.Parent then
   local c=badge.AbsolutePosition-top.AbsolutePosition+badge.AbsoluteSize/2
   Confetti.Burst(top,c.X,c.Y,{Count=34,Power=560,Spread=math.pi*1.2,Calm=still,ZIndex=5})
  end
 end)
 task.wait(still and .55 or .5)
 if finished then return end
 -- Swap the scene into a CanvasGroup so everything fades as one image while the layers dolly.
 local group=new("CanvasGroup","Fade",gui,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,GroupTransparency=0})
 root.Parent=group
 local d=still and .35 or .65
 if not still then
  local info=TweenInfo.new(d,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
  for l,s in pairs({[far]=1.3,[mid]=1.75,[near]=2.6,[sparkleLayer]=2.2,[starLayer]=2.4,[hud]=1.9,[top]=1.35})do
   TweenService:Create(l.Dolly,info,{Scale=s}):Play()
  end
 end
 local fade=TweenService:Create(group,TweenInfo.new(d,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1})
 fade.Completed:Connect(finish);fade:Play()
 task.delay(d+.4,finish)
end
enter.Activated:Connect(function()play("Select");press(enter);reveal(true)end)
soundButton.Activated:Connect(function()
 player:SetAttribute("GetFundedSoundOn",not soundOn());refreshToggles();press(soundButton);play("Select")
end)
motionButton.Activated:Connect(function()
 player:SetAttribute("GetFundedReducedMotion",not calm());refreshToggles();press(motionButton);play("Select")
 if mascot then mascot:SetCalm(calm())end
end)
local tipAt=os.clock()
local function nextTip()
 tipIndex=tipIndex%#TIPS+1;tipAt=os.clock()
 if calm()then tipText.Text=TIPS[tipIndex];return end
 local out=TweenService:Create(tipText,TweenInfo.new(.18),{TextTransparency=1})
 out.Completed:Connect(function()tipText.Text=TIPS[tipIndex];TweenService:Create(tipText,TweenInfo.new(.25),{TextTransparency=0}):Play()end)
 out:Play()
end
tipButton.Activated:Connect(function()play("Select");nextTip()end)

local t0=os.clock()
loop=RunService.RenderStepped:Connect(function(dt)
 if finished then return end
 local now=os.clock();local t=now-t0;local still=calm()
 if not revealing then
  poll()
  local sum=0;local first
  for _,s in ipairs(STAGES)do sum+=s.Weight*(s.Done and 1 or math.clamp(s.Sub,0,1));if not s.Done and not first then first=s end end
  target=math.max(target,sum)
  if first~=current then current=first;currentSince=now end
  if first then
   status.Text=first.Text
   local waited=now-currentSince
   detail.Text=first.Detail..(waited>6 and(" · "..math.floor(waited).."s")or"")
   -- After 20 s, explain. Once the terminal exists it can take over with its own connecting state.
   local slowNow=now-started>20
   local canEnter=stage.Desk.Done==true
   if slowNow~=slow.Visible or canEnter~=enter.Visible then
    slow.Visible=slowNow;enter.Visible=canEnter
    slowText.Text=canEnter and"Taking longer than usual. Your account and trades are safe."or"Still downloading. Slower connections take a little longer."
    layout()
    if mascot then mascot:SetMood(slowNow and"Worried"or"Happy")end
   end
  else
   -- Everything is ready: reveal now (the bar fills as part of the reveal, not before it).
   task.spawn(reveal,false);return
  end
  display+=(target-display)*math.min(1,dt*6)
  fill.Size=UDim2.fromScale(math.clamp(display,0,1),1);percent.Text=math.floor(display*100+.5).."%"
  if now-tipAt>5.5 then nextTip()end
  if pops==0 and t>3 and hint.TextTransparency>=1 and not hint:GetAttribute("Shown")then
   hint:SetAttribute("Shown",true);TweenService:Create(hint,TweenInfo.new(.4),{TextTransparency=0}):Play()
  end
  -- Stars: up to four drift up at a time; calm mode fades them in place instead.
  if now>=nextStar and #stars<4 then spawnStar();nextStar=now+1.4+math.random()*1.2 end
 end
 for i=#stars,1,-1 do
  local s=stars[i]
  if s.Popped or not s.B.Parent then table.remove(stars,i)
  elseif s.Life then
   if now-s.Born>s.Life then s.B:Destroy();table.remove(stars,i)end
  else
   s.Y-=s.Speed*dt
   s.B.Position=UDim2.fromScale(s.X+math.sin(now*1.3+s.Sway)*.015,s.Y)
   s.Art.Rotation=math.sin(now*1.7+s.Sway)*14
   if s.Y<-.08 then s.B:Destroy();table.remove(stars,i)end
  end
 end
 shine.Position=UDim2.new((t*.55)%1.6-.3,0,-.4,0);shine.Size=UDim2.new(0,26,1.8,0)
 if growing and(still or growCandles(t))then growing=false;growCandles(nil)end
 if still then
  logoScale.Scale=1
  for _,f in ipairs(floaters)do f.O.Position=UDim2.fromScale(f.X,f.Y);f.O.Rotation=0 end
  for _,s in ipairs(sparkles)do for _,r in ipairs(s.Rays)do r.BackgroundTransparency=.35 end end
  return
 end
 -- The logo drops in over the first half second, then breathes.
 local intro=math.clamp(t/.55,0,1)
 logoScale.Scale=(intro<1 and .4+.6*backOut(intro)or 1)*(1+math.sin(t*2)*.018)
 for _,f in ipairs(floaters)do
  f.O.Position=UDim2.new(f.X,0,f.Y,math.sin(t*f.Speed+f.Phase)*10)
  f.O.Rotation=math.sin(t*f.Speed*.8+f.Phase)*7
 end
 for _,s in ipairs(sparkles)do
  local a=.5+.5*math.sin(t*s.Speed+s.Phase)
  for _,r in ipairs(s.Rays)do r.BackgroundTransparency=1-a*.9 end
 end
end)

