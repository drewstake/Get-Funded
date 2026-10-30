-- Smooth, transparent native rings. Circular strokes keep the inner/outer curves concentric;
-- a radial half-plane cuts each coloured prefix at the exact statistical angle.
-- No uploaded textures, pixel wedges, tessellation seams, or opaque centre masks.
local Charts={}
function Charts.Draw(ctx,parent,name,cx,cy,radius,thickness,win,loss,half,colors)
 local container=ctx.frame(parent,name,cx-radius-thickness/2-2,cy-radius-thickness/2-2,
  radius*2+thickness+4,(half and radius or radius*2)+thickness+4,colors.Neutral,4)
 container.BackgroundTransparency=1
 local margin=thickness/2+2 local center=radius+margin
 win=win and math.clamp(win,0,1) or nil
 loss=win and math.clamp(loss or 0,0,1-win) or 0
 container:SetAttribute("Renderer","CircularStroke")
 container:SetAttribute("WinShare",win)
 container:SetAttribute("LossShare",loss)
 container:SetAttribute("NeutralShare",win and math.max(0,1-win-loss) or 1)
 container:SetAttribute("Thickness",thickness)
 container:SetAttribute("ArcDegrees",half and 180 or 360)
 local function layer(label,color,share,z,side)
  if share<=0 then return end
  local clip=ctx.frame(container,label,side=="Right"and center or 0,0,
   half and center*2 or center,half and center or center*2,color,z)
  clip.BackgroundTransparency=1 clip.ClipsDescendants=true
  local disk=ctx.frame(clip,"Circle",side=="Right"and -radius or margin,margin,radius*2,radius*2,color,z)
  disk.BackgroundTransparency=1 ctx.round(disk,radius)
  local stroke=ctx.stroke(disk,color) stroke.Thickness=thickness stroke.BorderStrokePosition=Enum.BorderStrokePosition.Center
  if share<1 then
   local rotation=half and 90-share*180 or (side=="Right"and share*180 or 180+share*180)
   local cut=Instance.new("UIGradient") cut.Name="RadialBoundary" cut.Rotation=rotation
   local first,last=half and 1 or 0,half and 0 or 1
   cut.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,first),
    NumberSequenceKeypoint.new(.4995,first),NumberSequenceKeypoint.new(.5005,last),NumberSequenceKeypoint.new(1,last)})
   cut.Parent=stroke
  end
 end
 local function prefix(label,color,share,z)
  if half then layer(label,color,share,z,"Top")
  else
   layer(label.."Right",color,math.clamp(share*2,0,1),z,"Right")
   layer(label.."Left",color,math.clamp(share*2-1,0,1),z,"Left")
  end
 end
 prefix("Track",colors.Neutral,1,4)
 if win then
  prefix("Loss",colors.Loss,win+loss,5)
  prefix("Win",colors.Win,win,6)
 end
 return container
end
return Charts
