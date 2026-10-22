-- Welcome guide: Bucky the bull greets new players and walks them through four tiny missions on the
-- real trading controls: pick a market, set the safety net, place a trade, close it. A mission only
-- completes from the real action (a market selection, saved protection settings, a server-confirmed
-- fill, a server-confirmed close). Finishing or skipping is saved on the player's profile through the
-- existing Tutorial flag, so returning players get a short welcome back instead. Replay from Help.
-- Lives on its own ScreenGui above the terminal, so the terminal's full rebuilds never reset it.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local TextService=game:GetService("TextService")
local GuiService=game:GetService("GuiService")
local Mascot=require(script.Parent.Mascot)
local Confetti=require(script.Parent.Confetti)
local Guide={} Guide.__index=Guide

local INK=Color3.fromRGB(3,18,55)
local FONT=Enum.Font.FredokaOne
local K={Text=Color3.fromRGB(245,249,255),Cyan=Color3.fromRGB(0,220,255),Gold=Color3.fromRGB(255,222,40),Bubble=Color3.fromRGB(248,251,255),
 Ink=Color3.fromRGB(16,30,86),InkSoft=Color3.fromRGB(78,92,150),Title=Color3.fromRGB(88,30,214),Done=Color3.fromRGB(0,190,110),
 Profit=Color3.fromRGB(0,150,90),Loss=Color3.fromRGB(214,40,90)}
local GLOSS={
 Green={Color3.fromRGB(34,253,158),Color3.fromRGB(0,173,112),Color3.fromRGB(129,255,202),Color3.fromRGB(0,112,72)},
 Purple={Color3.fromRGB(152,80,255),Color3.fromRGB(80,28,214),Color3.fromRGB(196,140,255),Color3.fromRGB(40,10,120)},
 Navy={Color3.fromRGB(15,48,117),Color3.fromRGB(3,24,66),Color3.fromRGB(0,220,255),Color3.fromRGB(1,15,49)},
}
local TROPHY="rbxassetid://80175474742009" -- the game's own trophy artwork (summary goal card)

local MISSIONS={
 {Id="Market",Title="Pick a market",
  Say="Every adventure starts with a market! Tap the market picker and choose BX, BT or BG.",
  Cheer="Great pick! That chart is all yours now."},
 {Id="Protect",Title="Set your safety net",
  Say={Desktop="Smart traders use a safety net! Tap Stop loss to check your stop loss and take profit, then close it to save.",
   Mobile="Smart traders use a safety net! Tap Risk controls to check your stop loss and take profit, then close it to save."},
  Cheer="Safety net on! Your next trade is protected."},
 {Id="Trade",Title="Make your call",
  Say="Think the price will rise? Tap BUY. Think it'll fall? Tap SELL. One contract is plenty.",
  Cheer="Order filled! You're in the market."},
 {Id="Close",Title="Lock it in",
  Say="Watch your open profit move. When you're happy, tap Close to lock in your result.",
  Cheer="Trade closed! That's the whole loop."},
}
-- One-line hints while a terminal popup that belongs to the current mission is open.
local HINTS={Market={Contracts="Pick any market. You can switch anytime!"},Protect={Protection="Looks good? Tap the red X to save it."},
 Close={Close="Tap Close to lock it in!"}}

-- ── Small drawing helpers ──────────────────────────────────────────────────────────────────────
local function new(class,name,parent,props)
 local o=Instance.new(class);o.Name=name
 for k,v in pairs(props or {})do o[k]=v end
 if parent then o.Parent=parent end
 return o
end
local function frame(parent,name,x,y,w,h,color,z,props)
 local f=new("Frame",name,nil,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color or K.Ink,BorderSizePixel=0,ZIndex=z or 1,Active=false})
 for k,v in pairs(props or {})do f[k]=v end
 f.Parent=parent;return f
end
local function corner(o,r)return new("UICorner","Corners",o,{CornerRadius=typeof(r)=="UDim"and r or UDim.new(0,r or 12)})end
local function stroke(o,color,t)return new("UIStroke","Border",o,{Color=color or INK,Thickness=t or 2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
local function shade(o,a,b)return new("UIGradient","Shade",o,{Color=ColorSequence.new(a,b),Rotation=90})end
local function label(parent,name,text,x,y,w,h,size,color,z,props)
 local l=new("TextLabel",name,nil,{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,Font=FONT,TextSize=size,
  TextColor3=color or K.Text,ZIndex=z or 1,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=true})
 for k,v in pairs(props or {})do l[k]=v end
 l.Parent=parent;return l
end
local function outline(l,color,t)return new("UIStroke","TextOutline",l,{Color=color or INK,Thickness=t or 1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Contextual,LineJoinMode=Enum.LineJoinMode.Round})end
local function textHeight(text,size,width)return math.ceil(TextService:GetTextSize(text,size,FONT,Vector2.new(math.max(10,width),4000)).Y)end
local function textWidth(text,size)return math.ceil(TextService:GetTextSize(text,size,FONT,Vector2.new(4000,200)).X)end
local function check(parent,size,color,z)
 local box=frame(parent,"Check",0,0,size,size,color,z,{BackgroundTransparency=1})
 for i,seg in ipairs({{.24,.54,.43,.73},{.43,.73,.78,.3}})do
  local a,b=Vector2.new(seg[1]*size,seg[2]*size),Vector2.new(seg[3]*size,seg[4]*size);local d=b-a
  local l=frame(box,"Stroke"..i,(a.X+b.X)/2,(a.Y+b.Y)/2,d.Magnitude+size*.15,size*.15,color,z,{AnchorPoint=Vector2.new(.5,.5),Rotation=math.deg(math.atan2(d.Y,d.X))})
  corner(l,UDim.new(.5,0))
 end
 return box
end
-- Speech bubble: flat white card, cyan rim, and a tail on its left edge at tailY pointing at Bucky.
local function speech(parent,name,x,y,w,h,tailY,z)
 local tail=frame(parent,name.."Tail",x-3,y+tailY,18,18,K.Bubble,z,{AnchorPoint=Vector2.new(.5,.5),Rotation=45});stroke(tail,K.Cyan,3)
 local b=frame(parent,name,x,y,w,h,K.Bubble,z);corner(b,18);stroke(b,K.Cyan,3)
 -- Covers the rim where the tail joins, so the tail reads as part of the bubble.
 frame(b,"Join",-4,tailY-7,9,14,K.Bubble,z+1)
 return b
end
local function overlaps(a,b,pad)
 pad=pad or 0
 return a and b and a.X<b.X+b.W+pad and b.X<a.X+a.W+pad and a.Y<b.Y+b.H+pad and b.Y<a.Y+a.H+pad
end

function Guide.new(ctx)
 local player=Players.LocalPlayer
 local self=setmetatable({Ctx=ctx,S=ctx.State,Session=ctx.Session,Canvas=ctx.Canvas,Root=ctx.Root,Player=player,Fx=ctx.Fx,
  Phase="Waiting",Step=1,Done={},Connections={},Alive=true,Minimized=false,Typed=0,Speech="",Mobile=false},Guide)
 local stale=ctx.Gui.Parent and ctx.Gui.Parent:FindFirstChild("GetFundedGuide");if stale then stale:Destroy()end
 local gui=new("ScreenGui","GetFundedGuide",nil,{ResetOnSpawn=false,DisplayOrder=12,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 pcall(function()gui.ScreenInsets=ctx.Gui.ScreenInsets end)
 gui.Parent=ctx.Gui.Parent;self.Gui=gui
 self.Layer=frame(gui,"Layer",0,0,0,0,K.Ink,1,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
 self.Effects=frame(gui,"Effects",0,0,0,0,K.Ink,20,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
 local function on(signal,fn)table.insert(self.Connections,signal:Connect(fn))end
 on(self.Session.Changed.Event,function()self:_marketUpdate()end)
 on(self.Session.Replies.Event,function(reply)self:_reply(reply)end)
 on(RunService.RenderStepped,function(dt)self:_frame(dt)end)
 on(player:GetAttributeChangedSignal("GetFundedReducedMotion"),function()if self.Bucky then self.Bucky:SetCalm(self:Calm())end;self.LayoutKey=nil end)
 on(player:GetAttributeChangedSignal("GetFundedLoading"),function()self:_marketUpdate()end)
 on(self.Layer:GetPropertyChangedSignal("AbsoluteSize"),function()
  self.LayoutKey=nil
  if self.Modal and self.ModalBuilder then self.ModalBuilder()end
 end)
 self:_marketUpdate()
 return self
end
function Guide:Calm()
 local v=self.Player:GetAttribute("GetFundedReducedMotion")
 if v==nil then local ok,r=pcall(function()return GuiService.ReducedMotionEnabled end);return ok and r==true end
 return v==true
end
function Guide:_measure()
 local size=self.Layer.AbsoluteSize
 self.Mobile=size.X<1000 or size.Y<600
 return size.X,size.Y
end
function Guide:_play(name)if self.Fx then self.Fx:Play(name)end end
function Guide:_portfolio()return self.Session.Portfolio end
function Guide:_attributes()
 self.Root:SetAttribute("GuidePhase",self.Phase)
 self.Root:SetAttribute("GuideStep",self.Phase=="Missions"and self.Step or nil)
end

-- ── Buttons: the game's glossy look, its hover/press feedback and its sounds ─────────────────────
function Guide:_button(parent,name,text,x,y,w,h,variant,size,fn,z)
 local g=GLOSS[variant]or GLOSS.Navy
 local b=new("TextButton",name,nil,{Text="",AutoButtonColor=false,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=Color3.new(1,1,1),
  BorderSizePixel=0,ZIndex=z or 5})
 b:SetAttribute("RestingColor",Color3.new(1,1,1))
 corner(b,math.min(14,math.floor(h*.3)));stroke(b,g[3],variant=="Navy"and 2 or 3);shade(b,g[1],g[2])
 if variant~="Navy"and w>=40 then local shine=frame(b,"Shine",8,4,w-16,3,Color3.new(1,1,1),b.ZIndex+1,{BackgroundTransparency=.5});corner(shine,2)end
 local l=label(b,"Label",text,4,0,w-8,h,size or 18,K.Text,b.ZIndex+2,{TextXAlignment=Enum.TextXAlignment.Center,TextScaled=true,TextWrapped=false})
 new("UITextSizeConstraint","TextSize",l,{MinTextSize=10,MaxTextSize=size or 18})
 outline(l,g[4],1.5)
 b.Parent=parent
 b.Activated:Connect(function()
  if self.Fx and self.Fx:Guard(b,.25)then return end
  self:_play(variant=="Navy"and"Select"or"Click");fn()
 end)
 if self.Fx then self.Fx:Bind(b,w*h>9000 and{Lift=1.03,Press=.95}or{Lift=1.06,Press=.92})end
 return b
end

-- ── Flow ───────────────────────────────────────────────────────────────────────────────────────
function Guide:_ready()
 if self.Player:GetAttribute("GetFundedLoading")==true then return false end
 local pf=self:_portfolio();if not pf or pf.New then return false end
 -- The terminal's own notices (time away, failed account) are dismissed first.
 return self.S.Overlay==nil and not self.S.Sheet
end
function Guide:_marketUpdate()
 if not self.Alive then return end
 local pf=self:_portfolio()
 if self.PendingFlag then
  if pf and pf.Tutorial==(self.PendingFlag=="TutorialDone"and"Done"or"Skipped")then self.PendingFlag=nil else self:_sendFlag()end
 end
 if self.Phase=="Waiting"and self:_ready()then
  if pf.Tutorial=="Pending"then self:_intro(false)else self:_welcomeBack()end
 end
 if self.Phase=="Missions"then self:_trackTrades()end
end
-- Server-confirmed fills and closes, compared with what existed when the missions started.
function Guide:_snapshot()
 local s=self.Session
 self.Base={Account=s.AccountKey,Fill=s.Fills[1]and s.Fills[1].TradeId,History=s.History[1]and s.History[1].TradeId}
end
function Guide:_trackTrades()
 local s=self.Session;local base=self.Base
 if not base or base.Account~=s.AccountKey then self:_snapshot();return end
 local fill,closed=s.Fills[1],s.History[1]
 if fill and fill.TradeId~=base.Fill then base.Fill=fill.TradeId;self:_achieve("Trade")end
 if closed and closed.TradeId~=base.History then base.History=closed.TradeId;self.LastClosed=closed;self:_achieve("Close")end
end
function Guide:_reply(reply)
 if reply.Kind=="Flag"then
  if self.FlagRequest and reply.RequestId==self.FlagRequest then self.FlagRequest=nil;if reply.Ok then self.PendingFlag=nil end end
  return
 end
 -- A rejected order or close: Bucky reacts; the terminal's toast carries the exchange's reason.
 if self.Phase=="Missions"and not reply.Ok and(reply.Kind=="Place"or reply.Kind=="Close")then
  self:_express("Hmm, that one didn't go through. Check the message up top and give it another try!","Worried",3.5)
 end
end
-- Real UI actions reported by the terminal: "Market" (a market was chosen) and "Protection" (saved).
function Guide:Signal(kind)
 if self.Phase~="Missions"then return end
 if kind=="Market"then self:_achieve("Market")elseif kind=="Protection"then self:_achieve("Protect")end
end
function Guide:_sendFlag()
 if not self.PendingFlag or(self.FlagSentAt and os.clock()-self.FlagSentAt<3)then return end
 local ok,_,_,id=self.Session:Flag(self.PendingFlag)
 if ok then self.FlagRequest=id;self.FlagSentAt=os.clock()end
end
function Guide:_flag(stage)self.PendingFlag=stage;self.FlagSentAt=nil;self:_sendFlag()end

function Guide:_intro(replay)
 self:_clearCard();self:_clearModal()
 self.Phase="Intro";self.IsReplay=replay;self:_attributes()
 self:_play("Open")
 self.ModalBuilder=function()self:_buildIntro()end
 self.ModalBuilder()
end
function Guide:Replay()
 if self.Toast then self.Toast:Destroy();self.Toast=nil end
 self.Minimized=false
 self:_intro(true)
end
function Guide:_start()
 self:_clearModal()
 self.Phase="Missions";self.Done={};self.Step=1;self:_snapshot();self.Minimized=false;self.Override=nil
 self:_attributes()
 self:_say(self:_missionText(),"Happy")
 self.LayoutKey=nil
end
function Guide:_skip()
 self:_clearModal();self:_clearCard()
 local pf=self:_portfolio()
 -- Skipping a replay keeps an earlier "Done".
 if not(self.IsReplay and pf and pf.Tutorial=="Done")then self:_flag("TutorialSkipped")end
 self.Phase="Done";self:_attributes()
 self:_measure()
 self:_toastBubble(self.Mobile and"No problem! Replay me anytime: More, then How to play."or"No problem! Replay me anytime from the ? button.",4.5)
end
function Guide:_achieve(id)
 if self.Phase~="Missions"or self.Done[id]then return end
 self.Done[id]=true
 -- Done ahead of its turn: remembered, and ticked off when its turn comes.
 if MISSIONS[self.Step].Id==id then self:_advance()end
end
function Guide:_advance()
 local finished=MISSIONS[self.Step]
 local burstFrom=self.PipCentre and self.PipCentre(self.Step)
 local first=self.Step
 while self.Step<=#MISSIONS and self.Done[MISSIONS[self.Step].Id]do self.Step+=1 end
 self.Celebrate={From=first,To=self.Step-1}
 self:_play("Success")
 local cheer=finished.Cheer
 if finished.Id=="Close"and self.LastClosed then
  local pnl=self.LastClosed.Pnl or 0;local reason=self.LastClosed.Reason;local signed=self.Ctx.Market.Signed(pnl)
  cheer=reason=="Take profit"and("Take profit hit! "..signed.." cashed in for you.")
   or reason=="Stop loss"and("Your stop loss stepped in at "..signed..". Safety net working!")
   or pnl>0 and("Ka-ching! "..signed.." locked in.")or pnl<0 and("Closed at "..signed..". Small losses are part of the game.")or"Closed at break-even. Smooth!"
 end
 self:_express(cheer,"Happy",1.9)
 if self.Bucky then self.Bucky:Hop()end
 if burstFrom then Confetti.Burst(self.Effects,burstFrom.X,burstFrom.Y,{Count=18,Power=360,Calm=self:Calm(),ZIndex=30})end
 self.LayoutKey=nil
 if self.Step>#MISSIONS then
  self.Phase="Finishing"
  task.delay(1.3,function()if self.Alive and self.Phase=="Finishing"then self:_finish()end end)
 end
 self:_attributes()
end
function Guide:_finish()
 self:_clearCard()
 self.Phase="Ready";self:_attributes()
 self:_flag("TutorialDone")
 self:_play("Milestone")
 self.ModalBuilder=function()self:_buildReady()end
 self.ModalBuilder()
 Confetti.Shower(self.Effects,{Calm=self:Calm(),ZIndex=30})
end
function Guide:_welcomeBack()
 self.Phase="Done";self:_attributes()
 local pf=self:_portfolio();if not pf then return end
 self:_measure()
 local n=pf.Next
 local whole=self.Ctx.Whole
 local goal=n and(n.Name.." · "..((n.Kind=="Trades"or n.Kind=="Wins")and(math.floor(n.Progress).." / "..n.Goal)or(whole(n.Progress).." / "..whole(n.Goal))))
 local count=self.Session:Summary().Count or 0
 local text="Welcome back, "..self.Player.DisplayName.."!\n"..(goal and("Next goal: "..goal)or"Every title is yours. Legendary!")
  ..(count>0 and("\n"..count.." open position"..(count==1 and""or"s").." still running.")or"")
 self:_toastBubble(text,7,n and math.clamp(n.Progress/math.max(1,n.Goal),0,1)or nil)
end

-- ── Speech ─────────────────────────────────────────────────────────────────────────────────────
function Guide:_missionText()
 local m=MISSIONS[self.Step];if not m then return self.Speech end
 local say=m.Say
 if type(say)=="table"then say=self.Mobile and say.Mobile or say.Desktop end
 return say
end
function Guide:_say(text,mood)
 if text==self.Speech then return end
 self.Speech=text;self.Typed=self:Calm()and #text or 0
 self.Mood=mood or"Happy"
 if self.Bucky then self.Bucky:SetMood(self.Mood);self.Bucky:Talk(self.Typed<#text)end
 self.LayoutKey=nil
end
-- A line that wins over the mission's own text for a few seconds (cheers, a rejected order).
function Guide:_express(text,mood,seconds)
 self.Override={Text=text,Mood=mood,Until=os.clock()+seconds}
 self:_say(text,mood)
end

-- ── Targets: real controls in the terminal, found by path after every rebuild ────────────────────
function Guide:_find(path)
 local node=self.Canvas
 for part in path:gmatch("[^%.]+")do
  if not node then return nil end
  if part:sub(1,1)=="*"then node=node:FindFirstChild(part:sub(2),true)else node=node:FindFirstChild(part)end
 end
 return node
end
function Guide:_held()
 local s=self.Session
 for _,key in ipairs(self.Ctx.Market.PositionOrder)do if s.Positions[key]then return key end end
end
-- Returns the control paths to highlight and, when the player must take a detour, what Bucky says.
function Guide:_targets()
 local s=self.S;local m=MISSIONS[self.Step];if not m or self.Phase~="Missions"then return nil end
 local mobile=self.Mobile
 if m.Id=="Market"then
  if s.Overlay=="Contracts"then return{"Dialog.Content.ChooseBX","Dialog.Content.ChooseBT","Dialog.Content.ChooseBG"}end
  return mobile and{"Chart.Header.ContractSelector"}or{"OrderTicket.Fields.ContractSelector"}
 elseif m.Id=="Protect"then
  if s.Overlay=="Protection"then return{"ProtectionDialog.Dismiss"}end
  if s.Sheet==true then return{"OptionsSheet.Fields.StopCard","OptionsSheet.Fields.TargetCard"}end
  return mobile and{"TradeDock.RiskControls","TradeDock.Fields.RiskControls"}or{"OrderTicket.Fields.StopCard","OrderTicket.Fields.TargetCard"}
 elseif m.Id=="Trade"then
  return mobile and{"TradeDock.BuyLong","TradeDock.SellShort"}or{"OrderTicket.OrderActions.BuyLong","OrderTicket.OrderActions.SellShort"}
 elseif m.Id=="Close"then
  if s.Overlay=="Close"then return{"Dialog.Content.ConfirmClose"}end
  local key=self:_held();if not key then return nil end
  if s.Sheet=="Activity"then return{"Activity.*Close"..key}end
  if key==s.Contract then
   return mobile and{"TradeDock.PositionBar.ClosePosition","TradeDock.Fields.PositionBar.ClosePosition"}or{"OrderTicket.OrderActions.ClosePosition"}
  end
  return mobile and{"Chart.Header.ContractSelector"}or{"Sidebar.Market"..key},"Your "..key.." trade is still open. Switch back to "..key.." to close it."
 end
end
-- Union of the visible targets, clipped by scrolling/clipping ancestors. Nil when nothing is on screen.
function Guide:_targetRect(paths)
 local origin=self.Layer.AbsolutePosition
 local x1,y1,x2,y2
 for _,path in ipairs(paths or{})do
  local o=self:_find(path)
  if o and o:IsA("GuiObject")then
   local a,b=o.AbsolutePosition,o.AbsolutePosition+o.AbsoluteSize
   local visible=true;local node=o
   while node and node~=self.Canvas do
    if node:IsA("GuiObject")then
     if not node.Visible then visible=false;break end
     if node~=o and node.ClipsDescendants then
      local cp,cs=node.AbsolutePosition,node.AbsoluteSize
      a=Vector2.new(math.max(a.X,cp.X),math.max(a.Y,cp.Y));b=Vector2.new(math.min(b.X,cp.X+cs.X),math.min(b.Y,cp.Y+cs.Y))
     end
    end
    node=node.Parent
   end
   if visible and b.X-a.X>4 and b.Y-a.Y>4 then
    x1=math.min(x1 or a.X,a.X);y1=math.min(y1 or a.Y,a.Y);x2=math.max(x2 or b.X,b.X);y2=math.max(y2 or b.Y,b.Y)
   end
  end
 end
 if not x1 then return nil end
 return {X=x1-origin.X,Y=y1-origin.Y,W=x2-x1,H=y2-y1}
end
function Guide:_rect(o)
 if not o or not o:IsA("GuiObject")or not o.Visible then return nil end
 local p=o.AbsolutePosition-self.Layer.AbsolutePosition
 return {X=p.X,Y=p.Y,W=o.AbsoluteSize.X,H=o.AbsoluteSize.Y}
end
function Guide:_rectOf(name)return self:_rect(self.Canvas:FindFirstChild(name))end

-- ── Highlight ring and pointer ─────────────────────────────────────────────────────────────────
function Guide:_ensureRing()
 if self.Ring then return end
 local ring=frame(self.Layer,"Highlight",0,0,10,10,K.Gold,3,{BackgroundTransparency=1,Visible=false})
 corner(ring,14);stroke(ring,K.Gold,4)
 local inner=frame(ring,"Inner",3,3,4,4,K.Cyan,3,{BackgroundTransparency=1,Size=UDim2.new(1,-6,1,-6)});corner(inner,11);stroke(inner,K.Cyan,2)
 local halo=frame(ring,"Halo",-6,-6,0,0,K.Gold,2,{BackgroundTransparency=1,Size=UDim2.new(1,12,1,12)});corner(halo,18)
 self.Ring={Frame=ring,Halo=halo,HaloStroke=stroke(halo,K.Gold,3)}
 local pointer=frame(self.Layer,"Pointer",0,0,46,46,K.Gold,4,{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Visible=false})
 local glyph=label(pointer,"Glyph","▲",0,0,46,46,40,Color3.new(1,1,1),4,{TextXAlignment=Enum.TextXAlignment.Center,TextScaled=true,Size=UDim2.fromScale(1,1)})
 shade(glyph,Color3.fromRGB(255,246,130),Color3.fromRGB(255,150,0));outline(glyph,INK,3)
 self.Pointer=pointer
end
function Guide:_placeRing(rect,cardRect,now)
 self:_ensureRing()
 local ring,pointer=self.Ring.Frame,self.Pointer
 if not rect then ring.Visible=false;pointer.Visible=false;return end
 local pad=6
 ring.Visible=true
 ring.Position=UDim2.fromOffset(rect.X-pad,rect.Y-pad);ring.Size=UDim2.fromOffset(rect.W+pad*2,rect.H+pad*2)
 local calm=self:Calm()
 local pulse=calm and 0 or(math.sin(now*4)+1)/2
 self.Ring.HaloStroke.Transparency=calm and .55 or .3+pulse*.6
 self.Ring.Halo.Size=UDim2.new(1,12+pulse*8,1,12+pulse*8);self.Ring.Halo.Position=UDim2.fromOffset(-6-pulse*4,-6-pulse*4)
 -- Pointer: above the target, else below, else beside; never over the card or another control.
 -- The choice is cached until the target or the card moves.
 local W,H=self.Layer.AbsoluteSize.X,self.Layer.AbsoluteSize.Y
 local size=self.Mobile and 36 or 44;local bob=calm and 0 or math.sin(now*5)*6
 -- 8 px buckets, so a control's hover growth does not trigger a rescan every frame.
 local function bucket(r)return r and string.format("%d,%d,%d,%d",r.X//8,r.Y//8,r.W//8,r.H//8)or"-"end
 local cacheKey=bucket(rect).."|"..bucket(cardRect)
 if self.PointerKey~=cacheKey then
  self.PointerKey=cacheKey
  local cx,cy=rect.X+rect.W/2,rect.Y+rect.H/2;local gap=pad+size*.7
  local controls={}
  for _,d in ipairs(self.Canvas:GetDescendants())do
   if(d:IsA("GuiButton")or d:IsA("TextBox")or d:IsA("ImageLabel")or d:IsA("TextLabel")and d.Text~="")and d.Visible then
    local r=self:_rect(d)
    -- Skip full-screen backdrops, chart watermarks and the highlighted controls themselves.
    if r and r.W*r.H<W*H*.25 and not overlaps(r,rect,-2)then table.insert(controls,r)end
   end
  end
  self.PointerChoice=nil
  for _,o in ipairs({{cx,rect.Y-gap,180,0,-1},{cx,rect.Y+rect.H+gap,0,0,1},{rect.X-gap,cy,90,-1,0},{rect.X+rect.W+gap,cy,-90,1,0}})do
   local r={X=o[1]-size/2,Y=o[2]-size/2,W=size,H=size}
   local free=r.X>=0 and r.Y>=0 and r.X+r.W<=W and r.Y+r.H<=H and not overlaps(r,cardRect,4)
   for _,c in ipairs(controls)do if not free then break end;if overlaps(r,c,-4)then free=false end end
   if free then self.PointerChoice=o;break end
  end
 end
 local chosen=self.PointerChoice
 if not chosen then pointer.Visible=false;return end
 pointer.Visible=true;pointer.Size=UDim2.fromOffset(size,size);pointer.Rotation=chosen[3]
 pointer.Position=UDim2.fromOffset(chosen[1]+chosen[4]*bob,chosen[2]+chosen[5]*bob)
end

-- ── Bucky is shared by the card and the modals; detach him before either is destroyed ───────────
function Guide:_bucky(parent,size,z)
 if not self.Bucky or not self.Bucky.Alive then self.Bucky=Mascot.new(parent,size,{Calm=self:Calm(),ZIndex=z,Name="Bucky"})
 else self.Bucky.Root.Parent=parent;self.Bucky:SetSize(size)end
 self.Bucky:SetMood(self.Mood or"Happy");self.Bucky:Talk(self.Typed<#self.Speech)
 return self.Bucky
end
-- Only when he is inside the container about to be destroyed.
function Guide:_detachBucky(container)
 if container and self.Bucky and self.Bucky.Alive and self.Bucky.Root:IsDescendantOf(container)then self.Bucky.Root.Parent=nil end
end
function Guide:_clearCard()
 self:_detachBucky(self.Card)
 if self.Card then self.Card:Destroy();self.Card=nil end
 self.Body=nil;self.PipCentre=nil;self.LivePnl=nil;self.LayoutKey=nil
 if self.Ring then self.Ring.Frame.Visible=false;self.Pointer.Visible=false end
end
function Guide:_clearModal()
 self:_detachBucky(self.Modal)
 if self.Modal then self.Modal:Destroy();self.Modal=nil end
 self.ModalBuilder=nil;self.LayoutKey=nil
end

-- ── Mission card: speech bubble with the checklist ("Full"), or a one-line pill ("Mini"/"Paused") ─
function Guide:_buildCard(mode,width,hint)
 local hadCard=self.Card~=nil
 self:_detachBucky(self.Card)
 if self.Card then self.Card:Destroy()end
 local mobile=self.Mobile
 local card=frame(self.Layer,"GuideCard",0,0,width,10,K.Ink,10,{BackgroundTransparency=1})
 self.Card=card
 local count=0;for _,m in ipairs(MISSIONS)do if self.Done[m.Id]then count+=1 end end
 local step=math.min(self.Step,#MISSIONS)
 local celebrate=self.Celebrate;self.Celebrate=nil
 if mode=="Full"then
  local mascotSize=mobile and 58 or 90
  local bx=mascotSize+14;local bw=width-bx
  local pad=mobile and 12 or 14
  local bodySize=mobile and 14 or 16;local titleSize=mobile and 17 or 20
  local bodyH=textHeight(self.Speech,bodySize,bw-pad*2)+4
  local bh=pad+24+8+titleSize+6+bodyH+6+28+pad-6
  local h=math.max(bh,math.floor(mascotSize*1.2))
  card.Size=UDim2.fromOffset(width,h)
  local bubble=speech(card,"Bubble",bx,h-bh,bw,bh,math.max(22,bh-mascotSize*.62),11)
  -- Checklist: "YOUR FIRST ADVENTURE · 1/4" and one pip per mission.
  local chipText=(bw<400 and"ADVENTURE · "or"YOUR FIRST ADVENTURE · ")..count.."/"..#MISSIONS
  local pipSize=mobile and 18 or 20;local pipGap=5;local pipsW=#MISSIONS*(pipSize+pipGap)
  local chipW=math.min(bw-pad*2-pipsW-48,textWidth(chipText,mobile and 11 or 12)+20)
  local chip=frame(bubble,"Checklist",pad,pad,chipW,24,Color3.new(1,1,1),12);corner(chip,UDim.new(.5,0));stroke(chip,Color3.fromRGB(196,140,255),2)
  shade(chip,Color3.fromRGB(152,80,255),Color3.fromRGB(80,28,214))
  local chipLabel=label(chip,"Label",chipText,8,0,chipW-16,24,mobile and 11 or 12,K.Text,13,{TextXAlignment=Enum.TextXAlignment.Center,TextScaled=true,TextWrapped=false})
  new("UITextSizeConstraint","TextSize",chipLabel,{MinTextSize=7,MaxTextSize=mobile and 11 or 12})
  local pips={}
  for i,m in ipairs(MISSIONS)do
   local done=self.Done[m.Id];local current=i==step and not done
   local pip=frame(bubble,"Pip"..i,pad+chipW+8+(i-1)*(pipSize+pipGap),pad+(24-pipSize)/2,pipSize,pipSize,
    done and K.Done or current and K.Gold or Color3.fromRGB(214,224,246),12)
   corner(pip,UDim.new(.5,0));stroke(pip,done and Color3.fromRGB(0,120,70)or current and Color3.fromRGB(214,140,0)or Color3.fromRGB(170,184,220),2)
   if done then
    check(pip,pipSize,Color3.new(1,1,1),13)
    if celebrate and i>=celebrate.From and i<=celebrate.To and not self:Calm()then
     local s=new("UIScale","Pop",pip,{Scale=.2});TweenService:Create(s,TweenInfo.new(.38,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
    end
   else
    label(pip,"Number",tostring(i),0,0,pipSize,pipSize,mobile and 11 or 12,current and Color3.fromRGB(120,50,0)or K.InkSoft,13,{TextXAlignment=Enum.TextXAlignment.Center})
   end
   pips[i]=pip
  end
  self.PipCentre=function(i)
   local pip=pips[i];if not pip or not pip.Parent then return nil end
   return pip.AbsolutePosition-self.Effects.AbsolutePosition+pip.AbsoluteSize/2
  end
  self:_button(bubble,"Minimize","−",bw-pad-34,pad-3,34,30,"Navy",20,function()self.Minimized=true;self.LayoutKey=nil end,13)
  local title=self.Phase=="Finishing"and"All missions complete!"or MISSIONS[step].Title
  local tl=label(bubble,"Title",title,pad,pad+24+8,bw-pad*2,titleSize+2,titleSize,K.Title,13,{TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
  local body=label(bubble,"Body",self.Speech,pad,pad+24+8+titleSize+6,bw-pad*2,bodyH,bodySize,K.Ink,13,{TextYAlignment=Enum.TextYAlignment.Top})
  body.MaxVisibleGraphemes=self.Typed>=#self.Speech and -1 or math.floor(self.Typed)
  self.Body=body
  -- Tapping the bubble finishes the sentence.
  local finish=new("TextButton","FinishSpeech",bubble,{Text="",BackgroundTransparency=1,AutoButtonColor=false,Position=UDim2.fromOffset(pad,pad+28),
   Size=UDim2.new(1,-pad*2,1,-pad*2-60),ZIndex=12})
  finish.Activated:Connect(function()self.Typed=#self.Speech;if self.Body then self.Body.MaxVisibleGraphemes=-1 end;if self.Bucky then self.Bucky:Talk(false)end end)
  -- Footer: live open profit while the first trade is open, and Skip guide.
  local fy=bh-pad-28
  self.LivePnl=nil
  if MISSIONS[step].Id=="Close"and self:_held()then
   self.LivePnl=label(bubble,"LivePnl","",pad,fy,bw-pad*2-110,28,mobile and 14 or 16,K.Profit,13,{TextWrapped=false})
  end
  local skip=new("TextButton","SkipGuide",bubble,{Text="Skip guide",Font=FONT,TextSize=mobile and 14 or 15,TextColor3=K.InkSoft,BackgroundTransparency=1,
   Position=UDim2.fromOffset(bw-pad-100,fy-6),Size=UDim2.fromOffset(100,40),ZIndex=13,TextXAlignment=Enum.TextXAlignment.Right,AutoButtonColor=false})
  skip.Activated:Connect(function()self:_play("Select");self:_confirmSkip()end)
  skip.MouseEnter:Connect(function()skip.TextColor3=K.Loss end);skip.MouseLeave:Connect(function()skip.TextColor3=K.InkSoft end)
  local bucky=self:_bucky(card,mascotSize,11)
  bucky.Root.Position=UDim2.fromOffset(0,h-mascotSize*1.2)
 else
  -- One line beside Bucky's head. Tap to expand, or when paused, to return to the Trade screen.
  local h=mobile and 52 or 58;local head=h-8
  local text=mode=="Paused"and"Adventure paused · tap to continue"or hint or MISSIONS[step].Title
  local size=mobile and 14 or 16
  local tw=math.min(width-head-44,textWidth(text,size)+8)
  local w=head+tw+40
  card.Size=UDim2.fromOffset(w,h)
  local pill=new("TextButton","Mini",card,{Text="",AutoButtonColor=false,BackgroundColor3=K.Bubble,Size=UDim2.fromOffset(w,h),ZIndex=11})
  pill:SetAttribute("RestingColor",K.Bubble)
  corner(pill,UDim.new(.5,0));stroke(pill,K.Cyan,3)
  local l=label(pill,"Text",text,head+18,0,tw,h,size,K.Ink,13,{TextScaled=true,TextWrapped=false})
  new("UITextSizeConstraint","TextSize",l,{MinTextSize=10,MaxTextSize=size})
  local badge=frame(card,"Progress",w-20,-8,40,22,Color3.new(1,1,1),14);corner(badge,UDim.new(.5,0));stroke(badge,Color3.fromRGB(196,140,255),2)
  shade(badge,Color3.fromRGB(152,80,255),Color3.fromRGB(80,28,214))
  label(badge,"Label",count.."/"..#MISSIONS,0,0,40,22,12,K.Text,15,{TextXAlignment=Enum.TextXAlignment.Center})
  pill.Activated:Connect(function()
   self:_play("Select")
   if mode=="Paused"then self.Ctx.GoTrade()else self.Minimized=false end
   self.LayoutKey=nil
  end)
  if self.Fx then self.Fx:Bind(pill,{Lift=1.04,Press=.95})end
  -- Bucky's head peeks out of a round window at the pill's left end.
  local window=frame(card,"HeadWindow",6,4,head,head,Color3.fromRGB(70,40,190),12,{ClipsDescendants=true});corner(window,UDim.new(.5,0))
  shade(window,Color3.fromRGB(110,60,230),Color3.fromRGB(40,20,140))
  local bucky=self:_bucky(window,head*1.05,13)
  bucky.Root.Position=UDim2.fromOffset(-head*.025,-head*.02)
  self.PipCentre=function()return badge.AbsolutePosition-self.Effects.AbsolutePosition+badge.AbsoluteSize/2 end
  self.LivePnl=nil;self.Body=nil
 end
 if not hadCard and not self:Calm()then
  local s=new("UIScale","Enter",card,{Scale=.85})
  TweenService:Create(s,TweenInfo.new(.28,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
  self:_play("Open")
 end
 return card
end
function Guide:_confirmSkip()
 if self.Phase~="Missions"then return end
 local W=self:_measure()
 local pw=math.min(440,W-24)
 self.ModalBuilder=function()
  local modal=self:_modalShell("Skip the guide?",pw,64,"You can replay it anytime from How to play.")
  local bw=(modal.W-12)/2
  self:_button(modal.Content,"KeepGoing","Keep going",0,4,bw,54,"Green",19,function()self:_clearModal()end,46)
  self:_button(modal.Content,"ConfirmSkip","Skip guide",bw+12,4,bw,54,"Navy",17,function()self:_skip()end,46)
 end
 self.ModalBuilder()
end

-- ── Modals: intro, "You're ready!" and the skip confirmation ─────────────────────────────────────
function Guide:_modalShell(title,pw,contentH,subtitle)
 local W,H=self:_measure()
 pw=math.min(pw,W-24)
 if self.Modal then self:_detachBucky(self.Modal);self.Modal:Destroy()end
 local modal=frame(self.Layer,"GuideModal",0,0,0,0,K.Ink,40,{BackgroundTransparency=1,Size=UDim2.fromScale(1,1)})
 self.Modal=modal
 local backdrop=new("TextButton","Backdrop",modal,{Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(2,17,49),BackgroundTransparency=.3,
  Size=UDim2.fromScale(1,1),ZIndex=40})
 local narrow=pw<420
 local headH=subtitle and(narrow and 70 or 80)or 60
 local ph=math.min(H-20,9+headH+16+contentH+18)
 local shell=frame(modal,"Shell",W/2,H/2,pw,ph,Color3.new(1,1,1),41,{AnchorPoint=Vector2.new(.5,.5)});corner(shell,22);stroke(shell,Color3.fromRGB(4,221,255),4)
 shade(shell,Color3.fromRGB(6,56,147),Color3.fromRGB(3,30,83))
 local head=frame(shell,"Header",9,9,pw-18,headH,Color3.new(1,1,1),42);corner(head,16);stroke(head,Color3.fromRGB(168,100,255),3)
 shade(head,Color3.fromRGB(150,70,255),Color3.fromRGB(84,32,232))
 local titleSize=narrow and 22 or 28
 local t=label(head,"Title",title,16,subtitle and 6 or 0,pw-50,subtitle and titleSize+12 or headH,titleSize,K.Text,43,{TextScaled=true,TextWrapped=false})
 new("UITextSizeConstraint","TextSize",t,{MinTextSize=14,MaxTextSize=titleSize});outline(t,INK,2)
 if subtitle then label(head,"Subtitle",subtitle,16,headH-30,pw-50,24,narrow and 13 or 15,Color3.fromRGB(236,227,255),43)end
 local top=9+headH+16
 local content=new("ScrollingFrame","Content",shell,{Position=UDim2.fromOffset(22,top),Size=UDim2.fromOffset(pw-44,ph-top-12),CanvasSize=UDim2.fromOffset(0,contentH),
  BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=K.Cyan,ZIndex=43})
 if not self:Calm()and not self.ModalShown then
  backdrop.BackgroundTransparency=1;TweenService:Create(backdrop,TweenInfo.new(.18),{BackgroundTransparency=.3}):Play()
  local s=new("UIScale","Pop",shell,{Scale=.88})
  TweenService:Create(s,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 end
 -- Size changes rebuild the same modal without replaying its entrance.
 self.ModalShown=true;task.defer(function()self.ModalShown=nil end)
 return {Frame=modal,Shell=shell,Content=content,W=pw-44}
end
-- Bucky beside a speech bubble at the top of a modal; returns the height used.
function Guide:_heroRow(c,iw,text,mascotSize,textSize)
 local bx=mascotSize+18;local bw=iw-bx
 local bubbleH=textHeight(text,textSize,bw-28)+28
 local rowH=math.max(math.floor(mascotSize*1.2),bubbleH)
 local by=(rowH-bubbleH)/2
 local bubble=speech(c,"Speech",bx,by,bw,bubbleH,math.min(bubbleH-20,math.max(20,rowH-mascotSize*.62-by)),44)
 label(bubble,"Text",text,14,14,bw-28,bubbleH-28,textSize,K.Ink,46,{TextYAlignment=Enum.TextYAlignment.Top})
 local bucky=self:_bucky(c,mascotSize,44);bucky.Root.Position=UDim2.fromOffset(0,rowH-mascotSize*1.2)
 return rowH,bucky
end
function Guide:_buildIntro()
 local W,H=self:_measure()
 local narrow=W<520;local short=H<480
 local pw=math.min(600,W-24);local iw=pw-44
 local pf=self:_portfolio()
 local returning=self.IsReplay or(pf and(pf.Trades or 0)>0)
 local name=self.Player.DisplayName
 local text=returning and("Hey "..name..", ready for a quick refresher? Four tiny missions on the real controls.")
  or("Hey "..name..", I'm Bucky! You've got "..self.Ctx.Whole((pf and pf.StartingBalance)or 10000).." in play money. Let's learn the ropes with four tiny missions!")
 local mascotSize=short and 60 or narrow and 72 or 108
 local textSize=narrow and 15 or 17
 local bubbleH=textHeight(text,textSize,iw-mascotSize-18-28)+28
 local rowH=math.max(math.floor(mascotSize*1.2),bubbleH)
 local cols=narrow and 1 or 2;local rows=math.ceil(#MISSIONS/cols);local chipH=short and 38 or 44
 local listH=rows*(chipH+8)
 local btnH=short and 50 or 58
 local contentH=rowH+14+listH+8+(narrow and btnH*2+10 or btnH)+4
 local modal=self:_modalShell(returning and"Welcome guide"or"Welcome to Get Funded!",pw,contentH,"Your first adventure · about a minute")
 local c=modal.Content
 local _,bucky=self:_heroRow(c,iw,text,mascotSize,textSize)
 bucky:SetMood("Happy");bucky:Wave(2.2)
 local y=rowH+14
 local chipW=(iw-(cols-1)*10)/cols
 for i,m in ipairs(MISSIONS)do
  local col=(i-1)%cols;local row=(i-1)//cols
  local chip=frame(c,"Mission"..i,col*(chipW+10),y+row*(chipH+8),chipW,chipH,Color3.fromRGB(3,24,70),44);corner(chip,12);stroke(chip,Color3.fromRGB(27,92,196),2)
  local n=frame(chip,"Number",9,(chipH-26)/2,26,26,K.Gold,45);corner(n,UDim.new(.5,0));stroke(n,INK,2)
  label(n,"Value",tostring(i),0,0,26,26,15,Color3.fromRGB(120,50,0),46,{TextXAlignment=Enum.TextXAlignment.Center})
  local l=label(chip,"Label",m.Title,44,0,chipW-52,chipH,short and 16 or 18,K.Text,45,{TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
  outline(l,INK,1)
 end
 y+=listH+8
 if narrow then
  self:_button(c,"LetsGo","Let's go!",0,y,iw,btnH,"Green",24,function()self:_start()end,46)
  self:_button(c,"SkipGuide","Skip guide",0,y+btnH+10,iw,btnH-8,"Navy",17,function()self:_skip()end,46)
 else
  local skipW=math.floor(iw*.34)
  self:_button(c,"SkipGuide","Skip guide",0,y,skipW,btnH,"Navy",18,function()self:_skip()end,46)
  self:_button(c,"LetsGo","Let's go!",skipW+12,y,iw-skipW-12,btnH,"Green",26,function()self:_start()end,46)
 end
end
function Guide:_buildReady()
 local W,H=self:_measure()
 local narrow=W<520;local short=H<480
 local pw=math.min(580,W-24);local iw=pw-44
 local pf=self:_portfolio();local Market=self.Ctx.Market;local whole=self.Ctx.Whole
 local pnl=self.LastClosed and self.LastClosed.Pnl;local reason=self.LastClosed and self.LastClosed.Reason
 local text=pnl==nil and"You know the whole loop now: pick, protect, trade, close."
  or reason=="Take profit"and("Your take profit cashed in "..Market.Signed(pnl).." automatically. You know the whole loop now!")
  or reason=="Stop loss"and("Your stop loss closed it at "..Market.Signed(pnl)..". That's your safety net doing its job, and every pro has red days!")
  or pnl>0 and("Your first trade made "..Market.Signed(pnl).."! You know the whole loop now: pick, protect, trade, close.")
  or pnl<0 and("Your first trade: "..Market.Signed(pnl)..". Every pro has red days. Your stop loss is there to keep them small.")
  or"Your first trade closed at break-even. You know the whole loop now!"
 local mascotSize=short and 60 or narrow and 72 or 100
 local textSize=narrow and 15 or 17
 local bubbleH=textHeight(text,textSize,iw-mascotSize-18-28)+28
 local rowH=math.max(math.floor(mascotSize*1.2),bubbleH)
 local n=pf and pf.Next
 local goalH=n and(short and 108 or 122)or 0
 local btnH=short and 50 or 58
 local contentH=rowH+14+goalH+(n and 14 or 0)+(narrow and btnH*2+10 or btnH)+4
 local modal=self:_modalShell("You're ready!",pw,contentH,"Your first adventure · 4/4 complete")
 local c=modal.Content
 local _,bucky=self:_heroRow(c,iw,text,mascotSize,textSize)
 bucky:SetMood("Happy");bucky:Hop();bucky:Wave(1.8)
 task.spawn(function()for _=1,2 do task.wait(.55);if bucky.Alive then bucky:Hop()end end end)
 local y=rowH+14
 if n then
  -- Next objective: the server's next milestone, its progress and its permanent reward.
  local goal=frame(c,"NextObjective",0,y,iw,goalH,Color3.new(1,1,1),44);corner(goal,16);stroke(goal,Color3.fromRGB(255,244,98),3)
  shade(goal,Color3.fromRGB(255,206,30),Color3.fromRGB(255,150,0))
  local icon=short and 58 or 72
  new("ImageLabel","Trophy",goal,{Image=TROPHY,BackgroundTransparency=1,Position=UDim2.fromOffset(10,(goalH-icon)/2),Size=UDim2.fromOffset(icon,icon),ZIndex=45,ScaleType=Enum.ScaleType.Fit})
  local tx=icon+20;local tw=iw-tx-14
  label(goal,"Label","NEXT OBJECTIVE",tx,10,tw,18,13,Color3.fromRGB(110,48,0),45)
  local goalName=label(goal,"Goal",n.Name,tx,28,tw,28,short and 19 or 23,K.Text,45,{TextScaled=true,TextWrapped=false})
  new("UITextSizeConstraint","TextSize",goalName,{MinTextSize=12,MaxTextSize=short and 19 or 23});outline(goalName,Color3.fromRGB(150,70,0),2)
  local progress=math.clamp((n.Progress or 0)/math.max(1,n.Goal),0,1)
  local track=frame(goal,"Track",tx,62,tw,14,INK,45);corner(track,UDim.new(.5,0))
  local fill=frame(track,"Fill",2,2,math.max(10,(tw-4)*progress),10,Color3.new(1,1,1),46,{Visible=progress>0});corner(fill,UDim.new(.5,0))
  shade(fill,Color3.fromRGB(120,255,170),Color3.fromRGB(0,190,110))
  local amount=(n.Kind=="Trades"or n.Kind=="Wins")and(math.floor(n.Progress).." / "..n.Goal)or(whole(n.Progress).." / "..whole(n.Goal))
  local reward=(n.Title and("Earns the "..n.Title.." title")or"")..((n.StartingBonus or 0)>0 and(" + "..whole(n.StartingBonus).." on every fresh start")or"")
  label(goal,"Amount",amount..(reward~=""and("  ·  "..reward)or""),tx,82,tw,goalH-88,short and 12 or 14,Color3.fromRGB(110,48,0),45,{TextYAlignment=Enum.TextYAlignment.Top})
  y+=goalH+14
 end
 local function keep()self:_clearModal();self.Phase="Done";self:_attributes()end
 if narrow then
  self:_button(c,"KeepTrading","Keep trading",0,y,iw,btnH,"Green",22,keep,46)
  self:_button(c,"SeeGoals","See my goals",0,y+btnH+10,iw,btnH-8,"Purple",17,function()keep();self.Ctx.GoProgress()end,46)
 else
  local gw=math.floor(iw*.38)
  self:_button(c,"SeeGoals","See my goals",0,y,gw,btnH,"Purple",18,function()keep();self.Ctx.GoProgress()end,46)
  self:_button(c,"KeepTrading","Keep trading",gw+12,y,iw-gw-12,btnH,"Green",26,keep,46)
 end
end
-- A small self-dismissing Bucky bubble (welcome back, after skipping).
function Guide:_toastBubble(text,seconds,progress)
 if self.Toast then self.Toast:Destroy();self.Toast=nil end
 local W,H=self:_measure()
 local mobile=self.Mobile
 local mascotSize=mobile and 52 or 70
 local w=math.min(mobile and W-24 or 440,W-24)
 local bx=mascotSize+14;local bw=w-bx;local size=mobile and 14 or 16
 local th=textHeight(text,size,bw-28)
 local bh=th+28+(progress and 20 or 0)
 local h=math.max(bh,math.floor(mascotSize*1.2))
 local x,y
 if mobile then
  local strip=self:_rectOf("AccountSummary")
  x=12;y=strip and strip.Y+strip.H+8 or 64
 else
  local chart=self:_rectOf("Chart")
  x=chart and chart.X+16 or 240;y=chart and(chart.Y+chart.H-h-44)or(H-h-24)
 end
 local toast=new("TextButton","WelcomeToast",self.Layer,{Text="",AutoButtonColor=false,BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),ZIndex=30})
 self.Toast=toast
 local bubble=speech(toast,"Bubble",bx,h-bh,bw,bh,math.max(20,bh-mascotSize*.62),31)
 label(bubble,"Text",text,14,14,bw-28,th,size,K.Ink,33,{TextYAlignment=Enum.TextYAlignment.Top})
 if progress then
  local track=frame(bubble,"Track",14,th+22,bw-28,12,INK,33);corner(track,UDim.new(.5,0))
  local fill=frame(track,"Fill",2,2,math.max(8,(bw-32)*progress),8,Color3.new(1,1,1),34,{Visible=progress>0});corner(fill,UDim.new(.5,0))
  shade(fill,Color3.fromRGB(255,248,137),Color3.fromRGB(255,176,16))
 end
 local m=Mascot.new(toast,mascotSize,{Calm=self:Calm(),ZIndex=31,Name="Bucky"});m.Root.Position=UDim2.fromOffset(0,h-mascotSize*1.2);m:Wave(1.6)
 local open=true
 local function close()
  if not open then return end;open=false
  if self.Toast==toast then self.Toast=nil end
  if self:Calm()or not toast.Parent then m:Destroy();toast:Destroy();return end
  local s=new("UIScale","Out",toast,{Scale=1})
  local t=TweenService:Create(s,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=.8})
  t.Completed:Connect(function()m:Destroy();toast:Destroy()end);t:Play()
 end
 toast.Activated:Connect(close)
 if not self:Calm()then
  local s=new("UIScale","In",toast,{Scale=.7});TweenService:Create(s,TweenInfo.new(.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
 end
 self:_play("Open")
 task.delay(seconds or 6,close)
end

-- ── Per frame: speech, card layout, live P&L and the highlight ───────────────────────────────────
function Guide:_frame(dt)
 if not self.Alive then return end
 local W,H=self:_measure()
 if W<=0 then return end
 local now=os.clock()
 if self.Phase=="Waiting"then if self:_ready()then self:_marketUpdate()end;return end
 if self.Phase~="Missions"and self.Phase~="Finishing"then
  if self.Ring then self.Ring.Frame.Visible=false;self.Pointer.Visible=false end
  return
 end
 local s=self.S
 local onTrade=(self.Root:GetAttribute("Screen")or"Trade")=="Trade"
 local paths,detour
 if onTrade then paths,detour=self:_targets()end
 local rect=paths and self:_targetRect(paths)
 local m=MISSIONS[math.min(self.Step,#MISSIONS)]
 -- What Bucky says: a cheer or warning first, then any detour, then the mission's own line.
 if self.Phase=="Missions"then
  local override=self.Override and now<self.Override.Until and self.Override
  if not override then self.Override=nil end
  if override then self:_say(override.Text,override.Mood)
  elseif detour then self:_say(detour,"Wow")
  else self:_say(self:_missionText(),"Happy")end
 end
 -- Typing: ~46 characters a second; Bucky's mouth moves while he talks.
 if self.Typed<#self.Speech then
  self.Typed=math.min(#self.Speech,self.Typed+dt*46)
  if self.Body then self.Body.MaxVisibleGraphemes=self.Typed>=#self.Speech and -1 or math.floor(self.Typed)end
  if self.Typed>=#self.Speech and self.Bucky then self.Bucky:Talk(false)end
 end
 local overlay=s.Overlay or(s.Sheet and"Sheet")
 local hint=s.Overlay and HINTS[m.Id]and HINTS[m.Id][s.Overlay]
 if s.PendingOrder and m.Id=="Trade"then hint="Sending your order to the exchange…"end
 if s.PendingClose and m.Id=="Close"then hint="Closing… almost there!"end
 if not self.Session.CanTrade then hint="The market is paused. Your mission picks up when it's back."end
 local pf=self:_portfolio();if pf and pf.Failed then hint="Your account needs a restart first. Tap the goal card."end
 local mode=not onTrade and"Paused"or(overlay or self.Minimized or hint)and"Mini"or"Full"
 local chart=self:_rectOf("Chart")
 local plot=chart and self:_rect(self:_find("Chart.CandlestickPlot"))
 local area=plot or chart or{X=12,Y=60,W=W-24,H=H-140}
 local width=mode=="Full"and math.floor(math.min(self.Mobile and area.W-12 or 540,area.W-16))or math.min(W-24,440)
 local count=0;for _,mm in ipairs(MISSIONS)do if self.Done[mm.Id]then count+=1 end end
 local key=table.concat({mode,width,self.Step,count,tostring(hint),self.Speech,tostring(self.Mobile),tostring(m.Id=="Close"and self:_held()),self.Phase},"|")
 if key~=self.LayoutKey then self.LayoutKey=key;self:_buildCard(mode,width,hint)end
 -- Live open profit while the first trade runs.
 if self.LivePnl and self.LivePnl.Parent then
  local k=self:_held();local pos=k and self.Session.Positions[k]
  if pos then local pnl=self.Session:Pnl(pos);self.LivePnl.Text="Open profit  "..self.Ctx.Market.Signed(pnl);self.LivePnl.TextColor3=pnl>=0 and K.Profit or K.Loss end
 end
 -- Placement inside the chart, top or bottom, whichever keeps the highlighted control clear. With a
 -- popup open the pill moves to a free corner, or hides when the popup covers the screen.
 local card=self.Card;local cardRect
 if card then
  local cw,ch=card.Size.X.Offset,card.Size.Y.Offset
  local x,y
  if mode=="Paused"then
   local nav=self:_rectOf("MobileNavigation");local rail=self:_rectOf("Sidebar")
   x=rail and rail.X+rail.W+16 or 12;y=(nav and nav.Y or H)-ch-14
  elseif overlay then
   x=area.X+8;y=area.Y+area.H-ch-(self.Mobile and 30 or 40)
  else
   local top={X=area.X+8,Y=area.Y+8,W=cw,H=ch}
   local bottom={X=area.X+8,Y=area.Y+area.H-ch-(self.Mobile and 30 or 40),W=cw,H=ch}
   local pick=self.Mobile and top or bottom;local other=self.Mobile and bottom or top
   if rect and overlaps(pick,rect,10)and not overlaps(other,rect,10)then pick=other end
   x,y=pick.X,pick.Y
  end
  x=math.clamp(x,4,math.max(4,W-cw-4));y=math.clamp(y,4,math.max(4,H-ch-4))
  cardRect={X=x,Y=y,W=cw,H=ch}
  local blocker
  for _,name in ipairs({"Dialog","ProtectionDialog","ShopDialog","OptionsSheet"})do blocker=blocker or self:_rectOf(name)end
  card.Visible=not(overlay and blocker and overlaps(cardRect,blocker,6))
  if not card.Visible then cardRect=nil end
  local target=UDim2.fromOffset(x,y)
  if card:GetAttribute("Placed")and not self:Calm()then
   if card:GetAttribute("TweenTo")~=tostring(target)then
    card:SetAttribute("TweenTo",tostring(target))
    TweenService:Create(card,TweenInfo.new(.25,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=target}):Play()
   end
  else card.Position=target;card:SetAttribute("Placed",true);card:SetAttribute("TweenTo",tostring(target))end
 end
 self:_placeRing(rect,cardRect,now)
end

function Guide:Destroy()
 self.Alive=false
 for _,c in ipairs(self.Connections)do c:Disconnect()end
 if self.Bucky then self.Bucky:Destroy()end
 self.Gui:Destroy()
end
Guide.Missions=MISSIONS
return Guide
