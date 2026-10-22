-- One uploaded ImageGen atlas, shared by titles and both leaderboard modes.
local Config=require(script.Parent.ProgressionConfig)
local Art={}
function Art.Create(parent,name,index,x,y,size)
 local icon=Instance.new("ImageLabel");icon.Name=name;icon.BackgroundTransparency=1
 icon.Position=UDim2.fromOffset(x,y);icon.Size=UDim2.fromOffset(size,size);icon.ScaleType=Enum.ScaleType.Fit
 icon.ZIndex=parent.ZIndex+1;icon:SetAttribute("BadgeIndex",index)
 if index then
  local n=math.clamp(index,1,16)-1;local cell=Config.BadgeAtlasSize/4
  -- Measured transparent gutters account for the generated atlas row spacing.
  local rows={0,251,499,738,1024};local row=math.floor(n/4)+1
  local left,top=math.floor(n%4*cell),rows[row]
  icon.Image=Config.BadgeAtlas;icon.ImageRectOffset=Vector2.new(left,top)
  icon.ImageRectSize=Vector2.new(math.floor((n%4+1)*cell)-left,rows[row+1]-top)
 end
 icon.Parent=parent;return icon
end
return Art
