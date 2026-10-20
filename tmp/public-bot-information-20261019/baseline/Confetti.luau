local Instance=require("@lune/roblox").Instance
local env=require("../environment")
local game,Enum,task=env.game,env.Enum,env.task
-- Lightweight celebration effects shared by the loading screen and the welcome guide. One Heartbeat
-- connection animates a burst; every piece is destroyed when it lands. Calm (reduced motion) bursts
-- fade a few sparkles in place instead of throwing pieces across the screen.
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Confetti={}
Confetti.Palette={Color3.fromRGB(46,249,160),Color3.fromRGB(255,222,40),Color3.fromRGB(0,220,255),Color3.fromRGB(190,132,255),
 Color3.fromRGB(255,120,168),Color3.fromRGB(245,249,255)}
local function sparkle(parent,x,y,size,color,z)
 local s=Instance.new("Frame");s.Name="Sparkle";s.AnchorPoint=Vector2.new(.5,.5);s.Position=UDim2.fromOffset(x,y)
 s.Size=UDim2.fromOffset(size,size);s.BackgroundTransparency=1;s.ZIndex=z;s.Active=false
 for i=0,1 do
  local ray=Instance.new("Frame");ray.AnchorPoint=Vector2.new(.5,.5);ray.Position=UDim2.fromScale(.5,.5);ray.BorderSizePixel=0
  ray.Size=UDim2.fromScale(1,.24);ray.Rotation=45+i*90;ray.BackgroundColor3=color;ray.ZIndex=z
  local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=ray;ray.Parent=s
 end
 s.Parent=parent
 return s
end
Confetti.Sparkle=sparkle
-- Burst from (x, y) in the parent's offset space. opts: Count, Power, Spread (radians), Calm, ZIndex, Duration.
function Confetti.Burst(parent,x,y,opts)
 opts=opts or {}
 if not parent or not parent.Parent then return end
 local z=opts.ZIndex or 50
 if opts.Calm then
  for i=1,math.min(6,opts.Count or 6)do
   local a=(i/6)*math.pi*2
   local s=sparkle(parent,x+math.cos(a)*28,y+math.sin(a)*22,14,Confetti.Palette[(i-1)%#Confetti.Palette+1],z)
   for _,ray in ipairs(s:GetChildren())do
    ray.BackgroundTransparency=1
    local t=TweenService:Create(ray,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,0,true),{BackgroundTransparency=0})
    t:Play()
   end
   task.delay(.8,function()s:Destroy()end)
  end
  return
 end
 local count=opts.Count or 24;local power=opts.Power or 420;local spread=opts.Spread or math.pi*.9
 local pieces={}
 for i=1,count do
  local p=Instance.new("Frame");p.Name="Confetti";p.BorderSizePixel=0;p.AnchorPoint=Vector2.new(.5,.5);p.Active=false;p.ZIndex=z
  local round=math.random()<.35
  p.Size=round and UDim2.fromOffset(8,8)or UDim2.fromOffset(math.random(6,10),math.random(10,15))
  p.BackgroundColor3=Confetti.Palette[math.random(#Confetti.Palette)]
  if round then local c=Instance.new("UICorner");c.CornerRadius=UDim.new(.5,0);c.Parent=p else local c=Instance.new("UICorner");c.CornerRadius=UDim.new(0,2);c.Parent=p end
  local angle=-math.pi/2+(math.random()-.5)*spread
  local speed=power*(.45+math.random()*.65)
  pieces[i]={F=p,X=x,Y=y,VX=math.cos(angle)*speed,VY=math.sin(angle)*speed,R=math.random(0,360),VR=math.random(-540,540),Flip=math.random()*6,W=p.Size.X.Offset,H=p.Size.Y.Offset}
  p.Position=UDim2.fromOffset(x,y);p.Parent=parent
 end
 local life=opts.Duration or 1.25;local age=0;local connection
 connection=RunService.Heartbeat:Connect(function(dt)
  age+=dt
  local fade=math.clamp((age-(life-.35))/.35,0,1)
  for _,q in ipairs(pieces)do
   q.VY+=980*dt;q.VX*=(1-1.6*dt);q.X+=q.VX*dt;q.Y+=q.VY*dt;q.R+=q.VR*dt
   local f=q.F;f.Position=UDim2.fromOffset(q.X,q.Y);f.Rotation=q.R;f.BackgroundTransparency=fade
   -- Flutter: the piece's width breathes as it tumbles.
   f.Size=UDim2.fromOffset(math.max(2,q.W*math.abs(math.cos(age*9+q.Flip))),q.H)
  end
  if age>=life or not parent.Parent then
   connection:Disconnect()
   for _,q in ipairs(pieces)do q.F:Destroy()end
  end
 end)
end
-- A shower across the top of the parent (the "You're ready!" moment).
function Confetti.Shower(parent,opts)
 opts=opts or {}
 if not parent or not parent.Parent then return end
 local w=parent.AbsoluteSize.X
 if opts.Calm then Confetti.Burst(parent,w/2,parent.AbsoluteSize.Y*.3,{Calm=true,ZIndex=opts.ZIndex});return end
 for i=0,2 do
  Confetti.Burst(parent,w*(.2+i*.3),parent.AbsoluteSize.Y*.42,{Count=opts.Count or 22,Power=opts.Power or 620,Spread=math.pi*.55,ZIndex=opts.ZIndex,Duration=1.6})
 end
end
return Confetti
