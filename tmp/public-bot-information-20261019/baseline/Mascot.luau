local Instance=require("@lune/roblox").Instance
local env=require("../environment")
local game,Enum,task=env.game,env.Enum,env.task
-- Bucky, the Get Funded! bull: the green bull in a purple varsity jacket from the game's thumbnails.
-- Built from native GuiObjects in scale units, so one Size change resizes the whole character and no
-- uploaded artwork is needed. Presentation only. Calm mode (reduced motion) keeps him still apart from
-- blinking and talking.
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Mascot={} Mascot.__index=Mascot
local INK=Color3.fromRGB(3,18,55)
local K={
 Green=Color3.fromRGB(78,222,112),GreenDark=Color3.fromRGB(26,158,74),Ear=Color3.fromRGB(150,250,170),
 Horn=Color3.fromRGB(255,224,96),HornDark=Color3.fromRGB(232,150,16),Muzzle=Color3.fromRGB(250,220,166),MuzzleDark=Color3.fromRGB(222,176,112),
 Jacket=Color3.fromRGB(136,66,246),JacketDark=Color3.fromRGB(78,26,196),Trim=Color3.fromRGB(0,222,255),Tee=Color3.fromRGB(246,250,255),
 Mouth=Color3.fromRGB(92,22,48),Tongue=Color3.fromRGB(255,112,146),Nostril=Color3.fromRGB(128,74,40),Gold=Color3.fromRGB(255,214,64),
}
-- Design grid: 100 x 120 units. Parts use scale coordinates of that box.
local GW,GH=100,120
local function part(parent,name,x,y,w,h,color,z,opts)
 opts=opts or {}
 local f=Instance.new("Frame");f.Name=name;f.BorderSizePixel=0;f.BackgroundColor3=color
 f.Position=UDim2.fromScale(x/(opts.PW or GW),y/(opts.PH or GH));f.Size=UDim2.fromScale(w/(opts.PW or GW),h/(opts.PH or GH))
 f.Rotation=opts.Rot or 0;f.ZIndex=z;f.BackgroundTransparency=opts.Alpha or 0
 if opts.Anchor then f.AnchorPoint=opts.Anchor end
 if opts.Radius~=false then local c=Instance.new("UICorner");c.CornerRadius=UDim.new(opts.Radius or .5,0);c.Parent=f end
 if opts.Top then local g=Instance.new("UIGradient");g.Color=ColorSequence.new(opts.Top,color);g.Rotation=90;g.Parent=f;f.BackgroundColor3=Color3.new(1,1,1) end
 f.Parent=parent
 return f
end

function Mascot.new(parent,size,opts)
 opts=opts or {}
 local self=setmetatable({Strokes={},Mood="Happy",Talking=false,Calm=opts.Calm==true,Alive=true,NextBlink=os.clock()+1.2,WaveUntil=0,HopAt=-10},Mascot)
 local z=opts.ZIndex or 1;self.Z=z
 local holder=Instance.new("Frame");holder.Name=opts.Name or"Mascot";holder.BackgroundTransparency=1;holder.BorderSizePixel=0
 holder.Size=UDim2.fromOffset(size,size*GH/GW);holder.ZIndex=z;holder.Active=false;self.Root=holder
 local function ink(f,t)local s=Instance.new("UIStroke");s.Color=INK;s.Thickness=1;s.LineJoinMode=Enum.LineJoinMode.Round;s.Parent=f;table.insert(self.Strokes,{s,t or 1});return s end
 self.Shadow=part(holder,"Shadow",22,111,56,8,INK,z,{Alpha=.72})
 local rig=Instance.new("Frame");rig.Name="Rig";rig.BackgroundTransparency=1;rig.Size=UDim2.fromScale(1,1);rig.ZIndex=z;rig.Parent=holder;self.Rig=rig
 -- Torso: varsity jacket over a white tee with cyan trim and a tiny gold candle emblem.
 local torso=part(rig,"Jacket",22,72,56,42,K.JacketDark,z+1,{Radius=.28,Top=K.Jacket});ink(torso,1)
 part(torso,"Tee",39,0,22,42,K.Tee,z+2,{PW=100,PH=42,Radius=.2})
 part(torso,"TrimL",34,0,5,42,K.Trim,z+3,{PW=100,PH=42,Radius=.4})
 part(torso,"TrimR",61,0,5,42,K.Trim,z+3,{PW=100,PH=42,Radius=.4})
 for i,hh in ipairs({10,16,22})do part(torso,"Emblem"..i,8+i*6,30-hh,4,hh,K.Gold,z+3,{PW=100,PH=42,Radius=.3})end
 -- Arms pivot at the shoulder: the sleeve sits below the centre of a rotating shoulder frame.
 local function arm(name,x,rot)
  local shoulder=part(rig,name,x-14,64,28,28,K.Jacket,z,{Alpha=1,Rot=rot,Radius=false})
  local sleeve=part(shoulder,"Sleeve",29,46,42,80,K.JacketDark,z,{PW=100,PH=100,Radius=.45,Top=K.Jacket});ink(sleeve,1)
  part(sleeve,"Cuff",0,74,100,14,K.Trim,z+1,{PW=100,PH=100,Radius=.3})
  local hoof=part(shoulder,"Hoof",28,106,44,44,K.GreenDark,z+1,{PW=100,PH=100,Top=K.Green});ink(hoof,1)
  return shoulder
 end
 self.LeftArm=arm("LeftArm",22,22)
 self.RightArm=arm("RightArm",78,-22)
 self.RightRest=-22
 -- Head group: ears and horns sit behind the head; the face sits in front.
 local head=Instance.new("Frame");head.Name="Head";head.BackgroundTransparency=1;head.Size=UDim2.fromScale(1,.66);head.ZIndex=z+2;head.Parent=rig;self.Head=head
 local HP={PW=100,PH=79.2}
 local function hp(t)for k,v in pairs(HP)do t[k]=t[k]or v end;return t end
 -- Each horn is three overlapping capsules (out, up, then a tip curling inward). One ink underlay per
 -- capsule draws a single outline around the whole horn without seams where the capsules overlap.
 local HORN={{14,20,24,13,20},{3,6,12,21,-4},{7,-6,9,13,22}}
 for i,side in ipairs({-1,1})do
  for layer=1,2 do
   for j,seg in ipairs(HORN)do
    local cx=side<0 and seg[1]or 100-seg[1];local grow=layer==1 and 5 or 0
    part(head,(i==1 and"HornL"or"HornR")..j..(layer==1 and"Outline"or""),cx,seg[2],seg[3]+grow,seg[4]+grow,layer==1 and INK or K.HornDark,z+layer,
     hp{Anchor=Vector2.new(.5,.5),Rot=side<0 and seg[5]or -seg[5],Radius=.5,Top=layer==2 and(j==3 and Color3.fromRGB(255,246,196)or K.Horn)or nil})
   end
  end
  local ear=part(head,i==1 and"EarL"or"EarR",side<0 and -2 or 76,30,26,14,K.GreenDark,z+3,hp{Rot=side*-16,Radius=.5,Top=K.Green});ink(ear,.9)
  part(ear,"Inner",24,26,52,46,K.Ear,z+3,{PW=100,PH=100,Radius=.5})
 end
 local face=part(head,"Face",14,12,72,64,K.GreenDark,z+4,hp{Radius=.3,Top=K.Green});ink(face,1.2)
 self.Face=face
 local F={PW=72,PH=64}
 local function fp(t)for k,v in pairs(F)do t[k]=t[k]or v end;return t end
 part(face,"Tuft",28,-4,16,10,K.GreenDark,z+5,fp{Radius=.5})
 self.Eyes={}
 for i,ex in ipairs({12,40})do
  local eye=part(face,i==1 and"EyeL"or"EyeR",ex,14,20,22,K.Tee,z+5,fp{Radius=.5});ink(eye,.8)
  local pupil=part(eye,"Pupil",i==1 and 34 or 22,30,44,52,INK,z+6,{PW=100,PH=100,Radius=.5})
  part(pupil,"Glint",14,12,36,34,K.Tee,z+7,{PW=100,PH=100,Radius=.5})
  self.Eyes[i]={Eye=eye,Base=eye.Size,Pos=eye.Position}
 end
 self.Brows={part(face,"BrowL",11,6,20,5,INK,z+6,fp{Rot=-8}),part(face,"BrowR",41,6,20,5,INK,z+6,fp{Rot=8})}
 self.BrowBase={self.Brows[1].Position,self.Brows[2].Position}
 local muzzle=part(face,"Muzzle",8,34,56,28,K.MuzzleDark,z+6,fp{Radius=.48,Top=K.Muzzle});ink(muzzle,1)
 part(muzzle,"NostrilL",26,16,12,14,K.Nostril,z+7,{PW=100,PH=100,Radius=.5})
 part(muzzle,"NostrilR",62,16,12,14,K.Nostril,z+7,{PW=100,PH=100,Radius=.5})
 local mouth=part(muzzle,"Mouth",30,44,40,40,K.Mouth,z+7,{PW=100,PH=100,Radius=.5});self.Mouth=mouth
 self.Tongue=part(mouth,"Tongue",20,52,60,48,K.Tongue,z+8,{PW=100,PH=100,Radius=.5})
 holder.Parent=parent
 self:_strokes()
 self.SizeConnection=holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()self:_strokes()end)
 self:SetMood("Happy")
 self.Connection=RunService.RenderStepped:Connect(function()self:_step()end)
 return self
end
-- Outline weight follows the rendered size so small and large Buckys read the same.
function Mascot:_strokes()
 local w=self.Root.AbsoluteSize.X;if w<=0 then w=self.Root.Size.X.Offset end
 for _,item in ipairs(self.Strokes)do item[1].Thickness=math.max(1,w*.026*item[2])end
end
function Mascot:SetSize(size)self.Root.Size=UDim2.fromOffset(size,size*GH/GW);self:_strokes()end
function Mascot:SetCalm(calm)self.Calm=calm==true;if self.Calm then self.Rig.Position=UDim2.new();self.Head.Rotation=0;self.RightArm.Rotation=self.RightRest end end
-- Moods: Happy (open grin), Talk, Wow (round mouth, raised brows), Worried, Proud (closed smile).
local MOUTHS={Happy={30,44,40,40},Wow={40,40,20,46},Worried={34,58,32,14},Proud={28,54,44,18}}
function Mascot:SetMood(mood)
 self.Mood=MOUTHS[mood]and mood or"Happy"
 local m=MOUTHS[self.Mood]
 self.Mouth.Position=UDim2.fromScale(m[1]/100,m[2]/100);self.Mouth.Size=UDim2.fromScale(m[3]/100,m[4]/100)
 self.Tongue.Visible=self.Mood=="Happy"
 -- Left brow angle; the right brow mirrors it. Positive tips the inner ends down (keen), negative up (worried).
 local lift=self.Mood=="Wow"and -.05 or 0
 local tilt=self.Mood=="Worried"and -14 or self.Mood=="Wow"and -4 or 7
 for i,b in ipairs(self.Brows)do b.Position=self.BrowBase[i]+UDim2.fromScale(0,lift);b.Rotation=i==1 and tilt or -tilt end
end
function Mascot:Talk(on)self.Talking=on==true;if not on then self:SetMood(self.Mood)end end
function Mascot:Wave(seconds)self.WaveUntil=os.clock()+(seconds or 1.4)end
function Mascot:Hop()self.HopAt=os.clock()end
function Mascot:_step()
 if not self.Alive or not self.Root.Parent then return end
 local now=os.clock()
 -- Blink: squash the eyes for ~0.12 s every few seconds.
 local blink=now>=self.NextBlink
 if blink and now>self.NextBlink+.12 then self.NextBlink=now+2.4+math.random()*2.6;blink=false end
 for _,e in ipairs(self.Eyes)do
  local open=blink and .12 or 1
  e.Eye.Size=UDim2.fromScale(e.Base.X.Scale,e.Base.Y.Scale*open)
  e.Eye.Position=e.Pos+UDim2.fromScale(0,e.Base.Y.Scale*(1-open)/2)
 end
 if self.Talking then
  local open=(math.sin(now*17)+1)/2
  local w,h=.34+open*.08,.14+open*.32
  self.Mouth.Size=UDim2.fromScale(w,h);self.Mouth.Position=UDim2.fromScale(.5-w/2,.5+.08-h/2+.12);self.Tongue.Visible=open>.6
 end
 if self.Calm then return end
 local hop=now-self.HopAt;local lift=0
 if hop<.5 then lift=-math.sin(hop/.5*math.pi)*.12 end
 self.Rig.Position=UDim2.fromScale(0,math.sin(now*2.3)*.012+lift)
 self.Head.Rotation=math.sin(now*1.5)*3
 if now<self.WaveUntil then self.RightArm.Rotation=-140+math.sin(now*13)*22
 else self.RightArm.Rotation=self.RightRest+math.sin(now*2.3)*3 end
end
function Mascot:Destroy()
 self.Alive=false
 if self.Connection then self.Connection:Disconnect()end
 if self.SizeConnection then self.SizeConnection:Disconnect()end
 self.Root:Destroy()
end
Mascot.Colors=K
return Mascot
