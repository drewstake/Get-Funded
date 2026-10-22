-- Retained chart primitives: unchanged properties never invalidate Roblox's GUI layout.
-- Only candle geometry animates; execution prices and candle data remain authoritative.
local Pool={} Pool.__index=Pool
function Pool.new(root)
 return setmetatable({Root=root,Parents={},Objects={},Entries={},Moving={},Epoch=0,CanAnimate=false,Duration=0.08},Pool)
end
function Pool:Begin(animate)
 self.Epoch+=1 self.CanAnimate=animate==true
 if not self.CanAnimate then self:Snap() end
 for _,bucket in pairs(self.Parents)do table.clear(bucket.Counts)end
end
-- Without an identity, objects are reused by draw order. With one (a candle's time), the same
-- candle always owns the same objects, so panning can never hand a candle another candle's paint.
function Pool:Get(class,name,parent,identity)
 local bucket=self.Parents[parent]
 if not bucket then bucket={Counts={},Lists={},Keyed={}} self.Parents[parent]=bucket end
 local key=class..":"..name local entry
 if identity~=nil then
  local keyed=bucket.Keyed[key] if not keyed then keyed={} bucket.Keyed[key]=keyed end
  entry=keyed[identity]
  if not entry then
   local object=Instance.new(class) object.Name=name object.Parent=parent
   entry={Object=object,Values={},Gui=object:IsA("GuiObject"),Stroke=class=="UIStroke",Motion={},Keyed=keyed,Identity=identity,Key=identity}
   keyed[identity]=entry self.Entries[object]=entry table.insert(self.Objects,entry)
  end
 else
 local index=(bucket.Counts[key]or 0)+1 bucket.Counts[key]=index
 local list=bucket.Lists[key] if not list then list={} bucket.Lists[key]=list end
 entry=list[index]
 if not entry then
  local object=Instance.new(class) object.Name=name object.Parent=parent
  entry={Object=object,Values={},Gui=object:IsA("GuiObject"),Stroke=class=="UIStroke",Motion={}}
  list[index]=entry self.Entries[object]=entry table.insert(self.Objects,entry)
 end
 end
 entry.Epoch=self.Epoch
 if entry.Gui and not entry.Object.Visible then entry.Object.Visible=true
 elseif entry.Stroke and not entry.Object.Enabled then entry.Object.Enabled=true end
 entry.Active=true
 return entry.Object
end
function Pool:Props(object,props,identity)
 local entry=self.Entries[object]
 local animate=self.CanAnimate and identity~=nil and identity==entry.Identity
 if identity~=entry.Identity then
  for key in pairs(entry.Motion)do entry.Values[key]=nil end
  table.clear(entry.Motion) self.Moving[entry]=nil
 end
 entry.Identity=identity
 for key,value in pairs(props)do
  if entry.Values[key]~=value then
   entry.Values[key]=value
   if animate and(key=="Position"or key=="Size")then
    entry.Motion[key]={From=object[key],To=value,Elapsed=0} self.Moving[entry]=true
   else object[key]=value end
  end
 end
end
function Pool:Step(dt)
 for entry in pairs(self.Moving)do
  for key,motion in pairs(entry.Motion)do
   motion.Elapsed=math.min(self.Duration,motion.Elapsed+dt)
   local t=motion.Elapsed/self.Duration local alpha=1-(1-t)^3
   entry.Object[key]=motion.From:Lerp(motion.To,alpha)
   if t>=1 then entry.Motion[key]=nil end
  end
  if not next(entry.Motion)then self.Moving[entry]=nil end
 end
end
function Pool:Snap()
 for entry in pairs(self.Moving)do
  for key,motion in pairs(entry.Motion)do entry.Object[key]=motion.To end
  table.clear(entry.Motion)
 end
 table.clear(self.Moving)
end
-- `thickness` (default 1 px) is centred on y. Segments are sized to stay inside the row, so the row does
-- not clip: clipping a 1 px-tall row could round to an empty rectangle and hide the whole line.
function Pool:Dash(parent,x,y,width,color,length,z,thickness)
 thickness=thickness or 1
 local row=self:Get("Frame","DashedLineRow",parent)
 self:Props(row,{Position=UDim2.fromOffset(x,y-(thickness-1)//2),Size=UDim2.fromOffset(width,thickness),BackgroundTransparency=1,
  BorderSizePixel=0,ClipsDescendants=false,ZIndex=z or parent.ZIndex})
 local entry=self.Entries[row]
 -- Move a whole dash row with one property write, not hundreds of separate segments.
 if entry.Width~=width or entry.Color~=color or entry.Length~=length or entry.Z~=z or entry.T~=thickness then
  entry.Width=width entry.Color=color entry.Length=length entry.Z=z entry.T=thickness entry.Dashes=entry.Dashes or{}
  local count=math.ceil(width/(length+5))
  for i=1,math.max(count,#entry.Dashes)do
   local mark=entry.Dashes[i]
   if not mark then mark=Instance.new("Frame");mark.Name="DashedLine";mark.BorderSizePixel=0;mark.Parent=row;entry.Dashes[i]=mark end
   mark.Visible=i<=count
   if i<=count then
    local offset=(i-1)*(length+5)
    mark.Position=UDim2.fromOffset(offset,0);mark.Size=UDim2.fromOffset(math.min(length,width-offset),thickness)
    mark.BackgroundColor3=color;mark.ZIndex=z or parent.ZIndex
   end
  end
 end
 return row
end
-- Keyed objects not drawn for a long time (candles trimmed from history) are destroyed.
function Pool:Prune(age)
 local kept={}
 for _,entry in ipairs(self.Objects)do
  if entry.Keyed and not entry.Active and self.Epoch-(entry.Epoch or 0)>age then
   entry.Keyed[entry.Key]=nil self.Entries[entry.Object]=nil self.Moving[entry]=nil self.Parents[entry.Object]=nil
   entry.Object:Destroy()
  else table.insert(kept,entry) end
 end
 -- Children of destroyed objects (e.g. a hollow body's inner fill) go with them.
 local alive={}
 for _,entry in ipairs(kept)do
  if entry.Object.Parent then table.insert(alive,entry) else self.Entries[entry.Object]=nil self.Moving[entry]=nil end
 end
 self.Objects=alive
end
function Pool:Finish()
 if self.Epoch%600==0 then self:Prune(1800) end
 for _,entry in ipairs(self.Objects)do
  if entry.Epoch~=self.Epoch and entry.Active then
   if entry.Gui then entry.Object.Visible=false elseif entry.Stroke then entry.Object.Enabled=false end
   for key,motion in pairs(entry.Motion)do entry.Object[key]=motion.To end
   entry.Active=false table.clear(entry.Motion) self.Moving[entry]=nil
  end
 end
end
return Pool
