-- Interaction feedback for the Get Funded! GUI: hover/press/release tweens, selection pops, popup
-- transitions and a small palette of UI sounds. Presentation only; it never changes trading state.
-- The GUI is rebuilt on refresh, so per-control state (hover, last press, selection) is remembered by
-- the control's path. A rebuilt control continues its animation instead of snapping or replaying it.
local TweenService=game:GetService("TweenService")
local SoundService=game:GetService("SoundService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local FX={} FX.__index=FX

-- Official Roblox GUI sounds (public, Roblox-owned). Volumes are relative to the master volume.
FX.Sounds={
 Click={Id=17208396156,Volume=.30,Gap=.045,Speed=1.05},  -- Roblox GUI - Select
 Tick={Id=17208396156,Volume=.16,Gap=.04,Speed=1.25},    -- steppers: lighter and shorter
 Select={Id=17208204604,Volume=.24,Gap=.06},             -- Roblox GUI - Bubble: tabs, segments, toggles
 Open={Id=17208405682,Volume=.18,Gap=.09},               -- Roblox GUI - Swipe: popups and sheets
 Send={Id=17208399163,Volume=.26,Gap=.1},                -- Roblox GUI - Send: order submitted (not confirmed)
 Success={Id=17208380755,Volume=.34,Gap=.12},            -- Roblox GUI - Purchase: server-confirmed action
 TakeProfit={Id=17208380755,Volume=.34,Gap=0},          -- Confirmed TP: success
 StopLoss={Id=17208353912,Volume=.30,Gap=0},            -- Confirmed SL: distinct negative tone
 Milestone={Id=17208361335,Volume=.36,Gap=.4},           -- Roblox GUI - Notification High: unlocks
 Error={Id=17208353912,Volume=.30,Gap=.22},              -- Roblox GUI - Negative: rejected or invalid
}
FX.Levels={Low=.35,Medium=.65,High=1}
local QUICK=TweenInfo.new(.07,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local HOVER=TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local SETTLE=TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local BOUNCE=TweenInfo.new(.26,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local POP=TweenInfo.new(.22,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

function FX.new(root,options)
 options=options or {}
 local self=setmetatable({Root=root,Memory={},MemoryCount=0,Loops={},Last={},LastAny=0,Tweens=setmetatable({},{__mode="k"}),
  Enabled=options.Sound~=false,Level=options.Level or "Medium",Preview=options.Preview==true,Alive=true,Played={}},FX)
 -- Edit previews are saved into the place; they never create sounds or effect layers.
 if not self.Preview then self:_sounds() end
 return self
end
function FX:_sounds()
 local folder=Instance.new("Folder") folder.Name="GetFundedUISounds"
 local group=Instance.new("SoundGroup") group.Name="GetFundedUI" group.Volume=FX.Levels[self.Level] or .65 group.Parent=SoundService
 self.Group=group self.Folder=folder self.Instances={}
 for name,spec in pairs(FX.Sounds)do
  local s=Instance.new("Sound") s.Name=name s.SoundId="rbxassetid://"..spec.Id s.Volume=spec.Volume s.PlaybackSpeed=spec.Speed or 1
  s.SoundGroup=group s.Parent=folder self.Instances[name]=s
 end
 folder.Parent=SoundService
end
function FX:SetSound(enabled,level)
 if enabled~=nil then self.Enabled=enabled==true end
 if level and FX.Levels[level]then self.Level=level end
 if self.Group then self.Group.Volume=FX.Levels[self.Level] end
 if self.Root then self.Root:SetAttribute("SoundEnabled",self.Enabled);self.Root:SetAttribute("SoundLevel",self.Level)end
end
-- Plays one UI sound, rate limited per sound and overall so rapid input never becomes noise.
function FX:Play(name)
 local spec=FX.Sounds[name] local s=self.Instances and self.Instances[name]
 self.Played[name]=(self.Played[name] or 0)+1
 if not spec or not s or not self.Enabled then return false end
 local now=os.clock()
 if now-(self.Last[name] or 0)<spec.Gap or now-self.LastAny<.03 then return false end
 self.Last[name]=now self.LastAny=now
 s.TimePosition=0 s:Play()
 -- Studio diagnostics: how often each sound actually played (after rate limiting).
 if self.Root then self.Root:SetAttribute("SoundPlayed"..name,(self.Root:GetAttribute("SoundPlayed"..name)or 0)+1)end
 return true
end

-- Confirmed executions have already been deduplicated by MarketClient. They must not be
-- dropped by click throttling or cut off by another fill in the same network batch.
function FX:PlayFill(name)
 local template=self.Instances and self.Instances[name]
 if not self.Alive or not self.Enabled or not template then return false end
 local sound=template:Clone();sound.Name=name.."Fill";sound.Parent=self.Folder
 self.Played[name]=(self.Played[name]or 0)+1;self.LastAny=os.clock()
 sound.Ended:Once(function()sound:Destroy()end)
 game:GetService("Debris"):AddItem(sound,10)
 sound:Play()
 if self.Root then self.Root:SetAttribute("SoundPlayed"..name,(self.Root:GetAttribute("SoundPlayed"..name)or 0)+1)end
 return true
end

-- An accent only plays when nothing else just played (a popup opened by a click keeps the click).
function FX:Accent(name)
 if os.clock()-self.LastAny<.12 then return false end
 return self:Play(name)
end
-- Per-path memory survives GUI rebuilds.
function FX:Mem(key)
 local m=self.Memory[key]
 if not m then
  if self.MemoryCount>1500 then table.clear(self.Memory) self.MemoryCount=0 end
  m={} self.Memory[key]=m self.MemoryCount+=1
 end
 return m
end
function FX:Tween(o,info,props)
 local old=self.Tweens[o] if old then old:Cancel() end
 local t=TweenService:Create(o,info,props) self.Tweens[o]=t t:Play() return t
end
local function scaleOf(o,name)
 local s=o:FindFirstChild(name or "PressScale")
 if not s then s=Instance.new("UIScale") s.Name=name or "PressScale" s.Parent=o end
 return s
end
FX.ScaleOf=scaleOf
-- UIScale scales around the anchor point; centre it so controls grow and shrink in place.
local function centre(o)
 if o.AnchorPoint~=Vector2.zero or not o.Parent then return end
 local size,pos=o.Size,o.Position
 o.AnchorPoint=Vector2.new(.5,.5)
 o.Position=pos+UDim2.new(size.X.Scale/2,size.X.Offset/2,size.Y.Scale/2,size.Y.Offset/2)
end
FX.Centre=centre
local function inside(o)
 if not UIS.MouseEnabled or not o.Parent then return false end
 local m=UIS:GetMouseLocation()
 local gui=o:FindFirstAncestorWhichIsA("ScreenGui")
 if not(gui and gui.IgnoreGuiInset)then m-=GuiService:GetGuiInset()end
 local p,s=o.AbsolutePosition,o.AbsoluteSize
 return m.X>=p.X and m.X<=p.X+s.X and m.Y>=p.Y and m.Y<=p.Y+s.Y
end
local function sheen(o)
 local f=o:FindFirstChild("HoverSheen")
 if not f then
  f=Instance.new("Frame") f.Name="HoverSheen" f.Size=UDim2.fromScale(1,1) f.BackgroundColor3=Color3.new(1,1,1)
  f.BackgroundTransparency=1 f.BorderSizePixel=0 f.ZIndex=o.ZIndex f.Active=false
  local corner=o:FindFirstChildOfClass("UICorner")
  if corner then local c=Instance.new("UICorner") c.CornerRadius=corner.CornerRadius c.Parent=f end
  f.Parent=o
 end
 return f
end

-- Hover, press and release feedback for one button. Options: Lift, Press, Sheen (0..1), Quiet.
function FX:Bind(b,opts)
 if self.Preview then return end
 opts=opts or {}
 local fixed=b:GetAttribute("FixedGeometry")==true
 local lift,press=fixed and 1 or opts.Lift or 1.035,fixed and 1 or opts.Press or .94
 local glow=opts.Sheen or .9
 local key
 local rest
 local function k() key=key or b:GetFullName() return key end
 local function enabled() return b.Active~=false and not b:GetAttribute("Disabled") end
 local function darken(on)
  if b.BackgroundTransparency>=1 then return end
  rest=rest or b:GetAttribute("RestingColor") or b.BackgroundColor3
  self:Tween(b,on and QUICK or SETTLE,{BackgroundColor3=on and rest:Lerp(Color3.new(0,0,0),.16) or rest})
 end
 local function state(name,instant)
  if not b.Parent then return end
  local sc=scaleOf(b)
  local target=name=="Down" and press or name=="Hover" and lift or 1
  if instant then sc.Scale=target else
   self:Tween(sc,name=="Down" and QUICK or name=="Release" and BOUNCE or name=="Hover" and HOVER or SETTLE,{Scale=name=="Release" and lift or target})
  end
  if b.BackgroundTransparency<1 or opts.Sheen then
   local f=sheen(b)
   local t=(name=="Hover" or name=="Release") and glow or name=="Down" and math.min(1,glow+.05) or 1
   if instant then f.BackgroundTransparency=t else self:Tween(f,HOVER,{BackgroundTransparency=t})end
  end
 end
 b.MouseEnter:Connect(function()
  self:Mem(k()).Hover=true
  if enabled() then state("Hover") end
 end)
 b.MouseLeave:Connect(function()
  self:Mem(k()).Hover=false
  state("Leave") darken(false)
 end)
 b.MouseButton1Down:Connect(function()
  if not enabled() then if not opts.Quiet then self:Shake(b) end return end
  self:Mem(k()).PressedAt=os.clock()
  state("Down") darken(true)
 end)
 b.MouseButton1Up:Connect(function()
  darken(false)
  if enabled() then state(UIS.MouseEnabled and inside(b) and "Release" or "Leave") end
 end)
 -- After the whole render: centre, then restore hover or finish a press that caused the rebuild.
 task.defer(function()
  if not b.Parent or not self.Alive then return end
  if not fixed then centre(b)end
  local m=self.Memory[k()]
  if not m then return end
  local recent=m.PressedAt and os.clock()-m.PressedAt<.32
  local hovering=m.Hover and inside(b)
  if not hovering then m.Hover=false end
  if recent and enabled() then
   scaleOf(b).Scale=press state(hovering and "Release" or "Leave")
  elseif hovering and enabled() then state("Hover",true) end
 end)
end
-- Debounce: returns true when this activation should be ignored (repeat within `gap`, or disabled).
function FX:Guard(b,gap)
 if b:GetAttribute("Disabled") then return true end
 local m=self:Mem(b:GetFullName()) local now=os.clock()
 if m.ActivatedAt and now-m.ActivatedAt<(gap or .12) then return true end
 m.ActivatedAt=now m.PressedAt=m.PressedAt or now
 return false
end
-- Pops a control when it becomes selected (not when it is merely rebuilt while selected).
function FX:Selected(o,selected)
 if self.Preview or not o.Parent then return end
 local m=self:Mem(o:GetFullName())
 local was=m.Selected m.Selected=selected
 if selected and was==false then
  task.defer(function()
   if not o.Parent then return end
   centre(o) local sc=scaleOf(o) sc.Scale=.9 self:Tween(sc,POP,{Scale=1})
  end)
 end
end
-- A short bump when a displayed value changes (steppers). Frequent market readouts do not use this.
function FX:Bump(o,value)
 if self.Preview or not o.Parent then return end
 local m=self:Mem(o:GetFullName())
 local was=m.Value m.Value=value
 if was~=nil and was~=value then
  local sc=scaleOf(o,"BumpScale") sc.Scale=1.16 self:Tween(sc,BOUNCE,{Scale=1})
 end
end
function FX:Shake(o)
 if self.Preview or not o.Parent then return end
 if o:GetAttribute("FixedGeometry") then self:Ring(o,Color3.fromRGB(255,81,127));return end
 -- Establish the same anchor as Bind before capturing the rest position. A deferred Bind
 -- must never centre a control halfway through a shake and invalidate that saved position.
 centre(o)
 local m=self:Mem(o:GetFullName())
 if m.Shaking then return end m.Shaking=true
 local base=o.Position
 local offsets={-7,6,-4,3,0}
 task.spawn(function()
  for _,dx in ipairs(offsets)do
   if not o.Parent then break end
   local t=TweenService:Create(o,TweenInfo.new(.035,Enum.EasingStyle.Sine),{Position=base+UDim2.fromOffset(dx,0)})
   t:Play() t.Completed:Wait()
  end
  if o.Parent then o.Position=base end
  m.Shaking=false
 end)
end
-- Popup entrance: scale from 90% with a light overshoot and fade the backdrop in.
function FX:Open(dialog,backdrop,fromBottom)
 if self.Preview then return end
 if dialog and dialog.Parent then
  if fromBottom then
   local target=dialog.Position dialog.Position=target+UDim2.fromOffset(0,math.min(80,dialog.AbsoluteSize.Y*.25))
   self:Tween(dialog,TweenInfo.new(.24,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=target})
  else
   centre(dialog) local sc=scaleOf(dialog,"PopScale") sc.Scale=.9 self:Tween(sc,POP,{Scale=1})
  end
 end
 if backdrop and backdrop.Parent then
  local t=backdrop.BackgroundTransparency backdrop.BackgroundTransparency=1
  self:Tween(backdrop,TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=t})
 end
end
-- Popup exit: the closed popup is moved out of the canvas (which is about to be rebuilt) into a
-- non-interactive CanvasGroup that fades and shrinks, then is destroyed.
function FX:Ghost(items)
 if self.Preview or not self.Root or #items==0 then for _,o in ipairs(items)do o:Destroy()end return end
 local ghost=Instance.new("CanvasGroup") ghost.Name="PopupGhost" ghost.Size=UDim2.fromScale(1,1) ghost.BackgroundTransparency=1
 ghost.BorderSizePixel=0 ghost.ZIndex=6 pcall(function()ghost.Interactable=false end)
 ghost.Parent=self.Root
 for _,o in ipairs(items)do
  for _,d in ipairs(o:GetDescendants())do if d:IsA("GuiButton")or d:IsA("TextBox")then d.Active=false pcall(function()d.Interactable=false end)end end
  o.Parent=ghost
  if o.Name~="OverlayBackdrop"and o.Name~="SheetBackdrop"then
   centre(o) self:Tween(scaleOf(o,"PopScale"),TweenInfo.new(.13,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.94})
  end
 end
 local t=TweenService:Create(ghost,TweenInfo.new(.13,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1})
 t.Completed:Connect(function()ghost:Destroy()end) t:Play()
 task.delay(.5,function()if ghost.Parent then ghost:Destroy()end end)
end
-- Effects that must outlive a rebuild (success rings) live on a layer above the canvas.
function FX:Layer()
 if self.Preview or not self.Root then return nil end
 local layer=self.Root:FindFirstChild("EffectsLayer")
 if not layer then
  layer=Instance.new("Frame") layer.Name="EffectsLayer" layer.Size=UDim2.fromScale(1,1) layer.BackgroundTransparency=1
  layer.BorderSizePixel=0 layer.ZIndex=7 layer.Active=false layer.Parent=self.Root
 end
 return layer
end
-- Expanding glow ring around a control's on-screen rectangle.
function FX:Ring(o,color,radius)
 local layer=self:Layer() if not layer or not o or not o.Parent then return end
 local p=o.AbsolutePosition-self.Root.AbsolutePosition local s=o.AbsoluteSize
 local ring=Instance.new("Frame") ring.Name="SuccessRing" ring.AnchorPoint=Vector2.new(.5,.5)
 ring.Position=UDim2.fromOffset(p.X+s.X/2,p.Y+s.Y/2) ring.Size=UDim2.fromOffset(s.X,s.Y)
 ring.BackgroundColor3=color ring.BackgroundTransparency=.7 ring.BorderSizePixel=0 ring.ZIndex=8
 local c=Instance.new("UICorner") c.CornerRadius=UDim.new(0,radius or 12) c.Parent=ring
 local st=Instance.new("UIStroke") st.Color=color st.Thickness=3 st.Parent=ring
 ring.Parent=layer
 local info=TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
 TweenService:Create(ring,info,{Size=UDim2.fromOffset(s.X+26,s.Y+26),BackgroundTransparency=1}):Play()
 local fade=TweenService:Create(st,info,{Transparency=1}) fade.Completed:Connect(function()ring:Destroy()end) fade:Play()
end
function FX:Pulse(o)
 if self.Preview or not o or not o.Parent then return end
 if o:GetAttribute("FixedGeometry")then self:Ring(o,Color3.fromRGB(46,249,160));return end
 centre(o) local sc=scaleOf(o) sc.Scale=1.07 self:Tween(sc,BOUNCE,{Scale=1})
end
-- Looping decorations (loading dots, coach highlight) are stopped before each rebuild.
function FX:Loop(tween) table.insert(self.Loops,tween) tween:Play() return tween end
function FX:StopLoops() for _,t in ipairs(self.Loops)do t:Cancel()end table.clear(self.Loops) end
function FX:Destroy()
 self.Alive=false self:StopLoops()
 for o,t in pairs(self.Tweens)do t:Cancel()end
 if self.Folder then self.Folder:Destroy() end
 if self.Group then self.Group:Destroy() end
 local layer=self.Root and self.Root:FindFirstChild("EffectsLayer") if layer then layer:Destroy() end
end
return FX
