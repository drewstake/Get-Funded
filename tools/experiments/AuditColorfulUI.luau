-- Studio CLIENT (Play) layout audit for the Get Funded! workspace. Uses the Studio-only
-- UIDiagnostics hook to open each screen and popup at several viewport sizes, then reports
-- text overflow, off-screen objects, clipped controls and small touch targets. It changes only
-- presentation state (no orders or account requests are sent).
local root=game.Players.LocalPlayer.PlayerGui.MarketReign.Workspace
local hook=root:WaitForChild("UIDiagnostics")
local sizes={{1920,1022},{1440,900},{1280,720},{1024,600},{844,390},{390,844},{320,568}}
local overlays={false,"Settings","Contracts","Account","Protection","Menu","Tools","Timeframes","Accounts","Help","Guide","Close"}
local decorative={Star=true,Ray=true,Diamond1=true,Diamond2=true,Diamond3=true,Diamond4=true,Diamond5=true,Shine=true,Texture=true,HoverSheen=true,
 Watermark=true,Motif=true,LowerEdge=true,Grip=true,CoachHighlight=true}
local function rect(o)local p,s=o.AbsolutePosition,o.AbsoluteSize return p.X,p.Y,p.X+s.X,p.Y+s.Y end
local function shown(o)
 local n=o while n and n~=root do if n:IsA("GuiObject")and not n.Visible then return false end n=n.Parent end
 return true
end
local function skip(o)
 local n=o
 while n and n~=root do
  if decorative[n.Name]or n.Name:match("^Star")or n.Name:match("^Diamond")or n.Name=="CandlestickPlot"or n.Name=="PopupGhost"or n.Name=="EffectsLayer"then return true end
  n=n.Parent
 end
 return false
end
local function audit(label,mobile)
 local issues={}
 local rx1,ry1,rx2,ry2=rect(root)
 for _,o in ipairs(root.Canvas:GetDescendants())do
  if o:IsA("GuiObject")and shown(o)and not skip(o)and o.AbsoluteSize.X>0 then
   local x1,y1,x2,y2=rect(o)
   local clip=o.Parent
   while clip and clip~=root and not(clip:IsA("GuiObject")and clip.ClipsDescendants)do clip=clip.Parent end
   local inScroll=clip and clip:IsA("ScrollingFrame")
   if not inScroll and o.Name~="OptionsSheet"and(x1<rx1-2 or y1<ry1-2 or x2>rx2+2 or y2>ry2+2)then table.insert(issues,"offscreen "..o:GetFullName():gsub(".-Canvas%.",""))end
   if clip and clip~=root and not inScroll and o:IsA("GuiButton")then
    local cx1,cy1,cx2,cy2=rect(clip)
    if x1<cx1-2 or y1<cy1-2 or x2>cx2+2 or y2>cy2+2 then table.insert(issues,"clipped "..o:GetFullName():gsub(".-Canvas%.",""))end
   end
   if(o:IsA("TextLabel")or o:IsA("TextButton"))and o.Text~=""and o.TextTransparency<1 and not o.TextScaled
    and o.TextTruncate==Enum.TextTruncate.None and not o.TextFits then
    table.insert(issues,"text "..o:GetFullName():gsub(".-Canvas%.","").." '"..o.Text:sub(1,30).."'")
   end
   if mobile and o:IsA("GuiButton")and o.Active and o.BackgroundTransparency<1 and(o.AbsoluteSize.X<32 or o.AbsoluteSize.Y<28)then
    table.insert(issues,"touch "..o:GetFullName():gsub(".-Canvas%.","")..string.format(" %dx%d",o.AbsoluteSize.X,o.AbsoluteSize.Y))
   end
  end
 end
 return issues
end
local report={}
for _,size in ipairs(sizes)do
 root.Size=UDim2.fromOffset(size[1],size[2])
 local mobile=size[1]<1000 or size[2]<600
 for _,screen in ipairs({"Trade","Dashboard"})do
  hook:Invoke("Set","Screen",screen);hook:Invoke("Set","Nav",screen=="Trade"and"Trade"or"Accounts")
  for _,ov in ipairs(screen=="Trade"and overlays or{false})do
   if ov=="Protection"then hook:Invoke("Set","ProtectionDraft",{StopOn=true,TargetOn=true,StopTicks=40,TargetTicks=120})end
   if ov=="Close"then hook:Invoke("Set","CloseContract","BX")end
   hook:Invoke("Set","Overlay",ov or nil)
   task.wait(.12)
   local found=audit(screen..(ov and(":"..ov)or""),mobile)
   if #found>0 then table.insert(report,string.format("%dx%d %s%s: %s",size[1],size[2],screen,ov and(":"..ov)or"",table.concat(found," | ")))end
  end
  hook:Invoke("Set","Overlay",nil)
 end
 if mobile then
  hook:Invoke("Set","Screen","Trade");hook:Invoke("Set","Sheet",true);task.wait(.12)
  local found=audit("Sheet",true)
  if #found>0 then table.insert(report,string.format("%dx%d Sheet: %s",size[1],size[2],table.concat(found," | ")))end
  hook:Invoke("Set","Sheet",false)
 end
end
root.Size=UDim2.fromScale(1,1);hook:Invoke("Set","Screen","Trade")
return #report==0 and"No layout issues"or table.concat(report,"\n")
