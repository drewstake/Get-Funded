-- Market Alert Bar. Presentation only: describes an already-executed instrument price move.
-- Kept outside the chart's repaint pool, so ticks and UI rebuilds never restart the animation.
local Banner={} Banner.__index=Banner
local INK=Color3.fromRGB(3,18,52)
local WHITE=Color3.fromRGB(247,252,255)
local GREEN=Color3.fromRGB(46,249,160)
local PINK=Color3.fromRGB(255,81,127)
local GOLD=Color3.fromRGB(255,211,51)
local DURATION=4
local function make(class,name,parent,props)
 local o=Instance.new(class);o.Name=name
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function frame(parent,name,color,z)
 return make("Frame",name,parent,{BackgroundColor3=color,BorderSizePixel=0,Active=false,ZIndex=z or 20})
end
local function rect(o,x,y,w,h)o.Position=UDim2.fromOffset(x,y);o.Size=UDim2.fromOffset(w,h)end
local function corner(o,r)make("UICorner","Corners",o,{CornerRadius=UDim.new(0,r)})end
local function stroke(o,color,thickness,alpha)
 return make("UIStroke","Outline",o,{Color=color,Thickness=thickness,Transparency=alpha or 0,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})
end
local function shade(o,a,b)make("UIGradient","Shade",o,{Color=ColorSequence.new(a,b),Rotation=90})end
local function label(parent,name,value,size,color)
 local o=make("TextLabel",name,parent,{BackgroundTransparency=1,Active=false,ZIndex=23,Text=value,
  Font=Enum.Font.FredokaOne,TextSize=size,TextColor3=color or WHITE,TextXAlignment=Enum.TextXAlignment.Left,
  TextStrokeColor3=INK,TextStrokeTransparency=.35,TextScaled=true})
 make("UITextSizeConstraint","TextLimit",o,{MaxTextSize=size,MinTextSize=10});return o
end
function Banner.new(root)
 local self=setmetatable({Root=root,LastId=nil,StartedAt=nil,Count=0},Banner)
 local group=make("CanvasGroup","MarketEventBanner",root,{BackgroundTransparency=1,BorderSizePixel=0,
  Active=false,Visible=false,ZIndex=20,GroupTransparency=1})
 self.Group=group
 local body=frame(group,"Bar",WHITE);corner(body,12)
 shade(body,Color3.fromRGB(11,47,105),INK)
 self.Body=body;self.Glow=stroke(body,GREEN,6,.82);self.Rim=stroke(body,GREEN,2)
 local track=frame(body,"LightTrack",WHITE,21);track.BackgroundTransparency=1;track.ClipsDescendants=true;track.Size=UDim2.fromScale(1,1);corner(track,12)
 self.Sweeps={}
 for _,name in ipairs({"TopSweep","BottomSweep"})do
  local beam=frame(track,name,WHITE,22)
  make("UIGradient","Feather",beam,{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.5,0),NumberSequenceKeypoint.new(1,1)})})
  table.insert(self.Sweeps,beam)
 end
 local tab=frame(body,"EventTab",WHITE,22);corner(tab,10)
 shade(tab,Color3.fromRGB(181,73,255),Color3.fromRGB(89,27,195));stroke(tab,Color3.fromRGB(209,148,255),2)
 self.Tab=tab
 self.Tag=label(tab,"EventLabel","PRICE\nMOVE",16)
 self.Tag.TextXAlignment=Enum.TextXAlignment.Center
 -- A small native gold megaphone stays crisp at every screen size, without an asset download.
 local icon=frame(tab,"Megaphone",GOLD,23);icon.BackgroundTransparency=1;rect(icon,8,11,32,32);icon.Rotation=-14
 self.Icon=icon
 local grip=frame(icon,"Handle",GOLD,23);rect(grip,8,19,7,13);corner(grip,2);stroke(grip,INK,1.5)
 local back=frame(icon,"Back",GOLD,24);rect(back,2,10,8,12);corner(back,3);stroke(back,INK,1.5)
 for i=1,4 do local horn=frame(icon,"Horn"..i,GOLD,24);rect(horn,7+i*4,10-i*2,5,12+i*4)end
 local mouth=frame(icon,"Bell",Color3.fromRGB(255,170,22),25);rect(mouth,25,1,7,30);corner(mouth,5);stroke(mouth,INK,1.5)
 local gleam=frame(icon,"Gleam",Color3.fromRGB(255,246,161),26);rect(gleam,27,5,2,17);corner(gleam,2)
 for i=-1,1 do local ray=frame(icon,"SoundRay"..(i+2),GOLD,24);rect(ray,35,13+i*8,5,2);ray.Rotation=i*35;corner(ray,1)end
 self.Title=label(body,"Headline","MARKET SURGE",28)
 self.Subtitle=label(body,"Outlook","Recent upward price move",15,Color3.fromRGB(183,207,255))
 local arrows=label(body,"Chevrons",">>",32,GREEN);self.Arrows=arrows
 local candles=frame(body,"Candles",GREEN,22);candles.BackgroundTransparency=1;self.Candles=candles;self.Bars={}
 for i=1,3 do
  local wick=frame(candles,"Wick"..i,GREEN,22)
  local bar=frame(candles,"Candle"..i,GREEN,23);corner(bar,2);shade(bar,WHITE,Color3.fromRGB(160,205,195))
  self.Bars[i]={Wick=wick,Body=bar}
 end
 return self
end
function Banner:Clear()
 self.StartedAt=nil;self.Group.Visible=false
end
function Banner:Update(event,simTime,allowed,now,contract)
 if contract and self.Contract and contract~=self.Contract then self:Clear()end
 if type(event)=='table'and contract and event.Contract~=contract then return false end
 if type(event)~="table"or type(event.Id)~="string"or(event.Direction~=1 and event.Direction~=-1)
  or type(event.ExpiresAt)~="number"or type(simTime)~="number"then return false end
 if self.LastId==event.Id then return false end
 self.LastId=event.Id -- Consume hidden/expired announcements too; never replay them after a dialog.
 if not allowed or event.ExpiresAt<=simTime then return false end
 self.StartedAt=now or os.clock();self.Direction=event.Direction;self.Contract=event.Contract;self.Count+=1
 local up=event.Direction==1;local color=up and GREEN or PINK
 self.Title.Text=up and"MARKET SURGE"or"MARKET SELLOFF"
 self.Subtitle.Text=up and"Recent upward price move"or"Recent downward price move"
 self.Rim.Color=color;self.Glow.Color=color;self.Arrows.TextColor3=color
 for _,bar in ipairs(self.Bars)do bar.Wick.BackgroundColor3=color;bar.Body.BackgroundColor3=color end
 self.Group:SetAttribute("EventId",event.Id);self.Group:SetAttribute("Direction",event.Direction)
 self.Group:SetAttribute("AnnouncementCount",self.Count)
 return true
end
function Banner:_layout(plot)
 local space=plot.AbsoluteSize;local origin=plot.AbsolutePosition-self.Root.AbsolutePosition
 local width=math.min(800,math.max(0,space.X-28));local height=(width<500 or space.Y<230)and 52 or 68
 if width<220 or space.Y<85 then return false end
 local compact=width<440;local short=height==52
 self.X=origin.X+(space.X-width)/2-4;self.Y=origin.Y+6
 self.Group.Size=UDim2.fromOffset(width+8,height+8)
 if self.Width==width and self.Height==height then return true end
 self.Width=width;self.Height=height
 rect(self.Body,4,4,width,height)
 local tabW=compact and 44 or(short and 116 or 142)
 rect(self.Tab,1,1,tabW-2,height-2)
 self.Icon.Position=UDim2.fromOffset(compact and 6 or 9,(height-32)/2-1)
 self.Tag.Visible=not compact;rect(self.Tag,44,6,tabW-50,height-12)
 local right=compact and 32 or 112
 local tx=tabW+12;local tw=width-tx-right-10
 rect(self.Title,tx,short and 5 or 8,tw,short and 24 or 32)
 self.Title.TextLimit.MaxTextSize=compact and 19 or(short and 23 or 28)
 rect(self.Subtitle,tx,short and 29 or 41,tw,short and 17 or 19)
 self.Subtitle.TextLimit.MaxTextSize=compact and 11 or(short and 12 or 15)
 self.Arrows.Visible=not compact;rect(self.Arrows,width-112,8,46,height-16)
 rect(self.Candles,width-(compact and 32 or 63),7,compact and 25 or 52,height-14)
 for i,beam in ipairs(self.Sweeps)do rect(beam,-120,i==1 and 1 or height-3,120,2)end
 return true
end
function Banner:Step(plot,allowed,calm,now)
 if not allowed then self:Clear();return end
 if not self.StartedAt or not plot or not plot.Parent then self.Group.Visible=false;return end
 local age=(now or os.clock())-self.StartedAt
 if age>=DURATION or age<0 then self:Clear();return end
 if not self:_layout(plot)then self.Group.Visible=false;return end
 self.Group.Visible=true
 local enter=math.clamp(age/.32,0,1);local leave=math.clamp((DURATION-age)/.35,0,1)
 local eased=1-(1-enter)^3
 self.Group.GroupTransparency=1-math.min(enter,leave)
 self.Group.Position=UDim2.fromOffset(self.X,self.Y+(calm and 0 or -20*(1-eased)+8*(1-leave)))
 self.Glow.Transparency=calm and .82 or .8+.08*math.sin(age*3)
 for i,beam in ipairs(self.Sweeps)do
  beam.Visible=not calm
  if not calm then beam.Position=UDim2.fromOffset(((age*.65+(i-1)*.5)%1)*(self.Width+120)-120,i==1 and 1 or self.Height-3)end
 end
 self.Arrows.TextTransparency=calm and 0 or .12+.2*(1+math.sin(age*5))
 self.Arrows.Position=UDim2.fromOffset(self.Width-112+(calm and 0 or 3*math.sin(age*5)),8)
 local cw=self.Candles.Size.X.Offset;local ch=self.Candles.Size.Y.Offset
 for i,bar in ipairs(self.Bars)do
  local rank=self.Direction==1 and i or 4-i
  local bh=math.floor(ch*(.32+rank*.09));local y=math.floor((4-rank)*ch*.16)
  local bob=calm and 0 or math.sin(age*4-i*.6)*1.5
  local x=(i-1)*cw/3+2;local bw=math.max(4,math.floor(cw/3)-4)
  rect(bar.Wick,x+bw/2-1,y-3+bob,2,bh+7)
  rect(bar.Body,x,y+bob,bw,bh)
 end
end
function Banner:Destroy()self.Group:Destroy()end
return Banner
