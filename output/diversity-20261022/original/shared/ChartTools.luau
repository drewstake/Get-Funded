-- Chart drawings: stored in time (seconds) and price, never in pixels, so they stay attached to
-- the market when the chart pans, zooms, rescales or resizes. Presentation only.
local Tools={}
Tools.Colors={"Blue","Green","Red","Muted"} -- UI Kit palette keys; resolved by the view
Tools.Opacities={0.08,0.15,0.25,0.4}
Tools.Defaults={Rect={Border="Blue",Fill="Blue",Opacity=0.15},Trend={Border="Blue"},Line={Border="Blue"}}
Tools.HitTolerance={Mouse=6,Touch=14}
Tools.HandleRadius={Mouse=8,Touch=20}
local nextId=0
function Tools.NewId() nextId+=1 return "d"..nextId.."-"..math.floor(os.clock()*1000)%100000 end
local function copy(d) local r={} for k,v in pairs(d)do r[k]=v end return r end
Tools.Copy=copy
function Tools.CopyList(list) local r={} for i,d in ipairs(list)do r[i]=copy(d)end return r end
-- Gives legacy drawings an id and style so they can be selected, edited and undone.
function Tools.Normalize(d)
 d.Id=d.Id or Tools.NewId()
 local defaults=Tools.Defaults[d.Kind] or {}
 for k,v in pairs(defaults)do if d[k]==nil then d[k]=v end end
 return d
end
function Tools.New(kind,a,b,contract,timeframe)
 local d={Kind=kind,Contract=contract,Timeframe=timeframe,T1=a.Time,P1=a.Price}
 if kind~="Line" then d.T2=b.Time d.P2=b.Price end
 return Tools.Normalize(d)
end
-- Rectangle corners: 1=(T1,P1) 2=(T2,P1) 3=(T2,P2) 4=(T1,P2).
local cornerFields={{"T1","P1"},{"T2","P1"},{"T2","P2"},{"T1","P2"}}
Tools.CornerFields=cornerFields
function Tools.Points(d)
 if d.Kind=="Rect" then
  local pts={} for i,f in ipairs(cornerFields)do pts[i]={Time=d[f[1]],Price=d[f[2]],Part="Corner"..i} end return pts
 elseif d.Kind=="Trend" then return {{Time=d.T1,Price=d.P1,Part="P1"},{Time=d.T2,Price=d.P2,Part="P2"}}
 end
 return {}
end
-- A rectangle's extension handle: the midpoint of its right edge, in the caller's pixel space.
function Tools.ExtendPoint(d,toX,toY)
 return math.max(toX(d.T1),toX(d.T2)),(toY(d.P1)+toY(d.P2))/2
end
-- Strong magnet: nearest candle open/high/low/close anywhere in screen space.
-- toX/toY map time/price to pixels in the same space as x,y.
function Tools.Snap(candles,toX,toY,x,y)
 local best,bestD=nil,math.huge
 for _,c in ipairs(candles)do
  local cx=toX(c.Time)
  if (cx-x)^2<=bestD then
   for _,field in ipairs({"Open","High","Low","Close"})do
    local cy=toY(c[field]) local d=(cx-x)^2+(cy-y)^2
    if d<=bestD then best={Time=c.Time,Price=c[field],Field=field,X=cx,Y=cy} bestD=d end
   end
  end
 end
 return best
end
local function segmentDistance(px,py,x1,y1,x2,y2)
 local dx,dy=x2-x1,y2-y1 local len=dx*dx+dy*dy
 local t=len>0 and math.clamp(((px-x1)*dx+(py-y1)*dy)/len,0,1) or 0
 local qx,qy=x1+t*dx,y1+t*dy return math.sqrt((px-qx)^2+(py-qy)^2)
end
Tools.SegmentDistance=segmentDistance
-- Pixel-space soft price magnet for the selected candle, stable at every zoom level.
function Tools.SoftSnap(candle,toY,y,previous,threshold)
 if not candle then return nil end
 local limit=threshold or 7;local best,distance
 for _,field in ipairs({"Open","Close","High","Low"})do
  local d=math.abs(toY(candle[field])-y)
  if not distance or d<distance then best=field;distance=d end
 end
 if previous and previous.Time==candle.Time then
  local held=math.abs(toY(candle[previous.Field])-y)
  if held<=limit+3 and (distance>limit or held<=distance+1)then best=previous.Field;distance=held;limit+=3 end
 end
 if distance<=limit then return {Time=candle.Time,Price=candle[best],Field=best}end
end
function Tools.NearestCandle(candles,toX,x)
 local best,distance
 for _,c in ipairs(candles)do local d=math.abs(toX(c.Time)-x)
  if not distance or d<distance then best=c;distance=d end
 end
 return best
end
function Tools.ProtectionField(direction,entry,price)
 local delta=(price-entry)*direction
 return delta<0 and "Stop" or delta>0 and "Target" or nil
end
-- Returns {Drawing,Part,Interior} for the topmost drawing under the pointer.
-- The selected rectangle has an "Extend" dot at the midpoint of its right edge (checked first, slightly tighter
-- than corner handles so a small rectangle's corners stay reachable). Other handles belong to the
-- selected drawing only. A rectangle's body is "Slide" (horizontal move).
-- Interiors of unselected rectangles are flagged Interior: the view decides whether a drag there
-- moves the rectangle (mouse) or pans the chart (touch, where rectangles cover a small plot).
function Tools.HitTest(drawings,toX,toY,x,y,tolerance,handleRadius,selectedId,width)
 local extendRadius=math.max(4,handleRadius-2)
 for i=#drawings,1,-1 do
  local d=drawings[i]
  if d.Kind=="Rect" and d.Id==selectedId then
   local ex,ey=Tools.ExtendPoint(d,toX,toY)
   if math.abs(ex-x)<=extendRadius and math.abs(ey-y)<=extendRadius then return {Drawing=d,Part="Extend"} end
  end
 end
 for i=#drawings,1,-1 do
  local d=drawings[i]
  if d.Id==selectedId then
   for _,pt in ipairs(Tools.Points(d))do
    local hx,hy=toX(pt.Time),toY(pt.Price)
    if math.abs(hx-x)<=handleRadius and math.abs(hy-y)<=handleRadius then return {Drawing=d,Part=pt.Part} end
   end
  end
 end
 local interior
 for i=#drawings,1,-1 do
  local d=drawings[i]
  if d.Kind=="Line" then
   if math.abs(toY(d.P1)-y)<=tolerance and x>=0 and x<=(width or math.huge) then return {Drawing=d,Part="Move"} end
  elseif d.Kind=="Trend" then
   if segmentDistance(x,y,toX(d.T1),toY(d.P1),toX(d.T2),toY(d.P2))<=tolerance then return {Drawing=d,Part="Move"} end
  elseif d.Kind=="Rect" then
   local x1,x2=math.min(toX(d.T1),toX(d.T2)),math.max(toX(d.T1),toX(d.T2))
   local y1,y2=math.min(toY(d.P1),toY(d.P2)),math.max(toY(d.P1),toY(d.P2))
   local inside=x>=x1-tolerance and x<=x2+tolerance and y>=y1-tolerance and y<=y2+tolerance
   if inside then
    local edge=math.abs(x-x1)<=tolerance or math.abs(x-x2)<=tolerance or math.abs(y-y1)<=tolerance or math.abs(y-y2)<=tolerance
    if edge or d.Id==selectedId then return {Drawing=d,Part="Slide"} end
    interior=interior or {Drawing=d,Part="Slide",Interior=true}
   end
  end
 end
 return interior
end
-- Applies an edit to `target` from its unmodified `original`.
function Tools.Edit(target,original,part,point,delta)
 for k,v in pairs(original)do target[k]=v end
 if part=="Move" then
  target.T1=original.T1 and original.T1+delta.Time target.P1=original.P1+delta.Price
  if original.T2 then target.T2=original.T2+delta.Time target.P2=original.P2+delta.Price end
 elseif part=="Extend" then
  -- Right edge only: the left edge and both price levels stay fixed; the edge never crosses the left
  -- edge (it keeps at least delta.MinWidth seconds, one candle, of width).
  local right=(original.T2 or original.T1)>=original.T1 and "T2" or "T1" local left=right=="T2" and "T1" or "T2"
  target[right]=math.max(point.Time,original[left]+(delta and delta.MinWidth or 0))
 elseif part=="Slide" then
  -- Horizontal only: width (T2-T1), height and both price levels stay exactly as they were.
  target.T1=original.T1+delta.Time if original.T2 then target.T2=original.T2+delta.Time end
 elseif part=="P1" or part=="P2" then
  local n=part:sub(2) target["T"..n]=point.Time target["P"..n]=point.Price
 else
  local index=tonumber(part:match("Corner(%d)"))
  if index then
   local f=cornerFields[index] target[f[1]]=point.Time target[f[2]]=point.Price
  end
 end
end
-- Liang-Barsky clip to [0,w]x[0,h]. Rotated GUI objects are not clipped by ClipsDescendants.
function Tools.ClipSegment(x1,y1,x2,y2,w,h)
 local t0,t1=0,1 local dx,dy=x2-x1,y2-y1
 for _,edge in ipairs({{-dx,x1},{dx,w-x1},{-dy,y1},{dy,h-y1}})do
  local p,q=edge[1],edge[2]
  if p==0 then if q<0 then return nil end
  else
   local r=q/p
   if p<0 then if r>t1 then return nil elseif r>t0 then t0=r end
   else if r<t0 then return nil elseif r<t1 then t1=r end end
  end
 end
 return x1+t0*dx,y1+t0*dy,x1+t1*dx,y1+t1*dy
end
-- Undo/redo of the whole drawing list (small, so snapshots are simple and exact).
local History={} History.__index=History
function Tools.History(limit) return setmetatable({Past={},Future={},Limit=limit or 100},History) end
function History:Record(list)
 table.insert(self.Past,Tools.CopyList(list)) if #self.Past>self.Limit then table.remove(self.Past,1) end
 table.clear(self.Future)
end
local function restore(list,snapshot) table.clear(list) for i,d in ipairs(snapshot)do list[i]=copy(d) end end
-- Records a snapshot taken before an edit that has already been applied (e.g. a finished drag).
function History:Push(snapshot)
 table.insert(self.Past,snapshot) if #self.Past>self.Limit then table.remove(self.Past,1) end
 table.clear(self.Future)
end
function History:Undo(list)
 local snapshot=table.remove(self.Past) if not snapshot then return false end
 table.insert(self.Future,Tools.CopyList(list)) restore(list,snapshot) return true
end
function History:Redo(list)
 local snapshot=table.remove(self.Future) if not snapshot then return false end
 table.insert(self.Past,Tools.CopyList(list)) restore(list,snapshot) return true
end
function History:CanUndo() return #self.Past>0 end
function History:CanRedo() return #self.Future>0 end
-- Candle direction from exact tick counts: 1 up, -1 down, 0 doji. Independent of the viewport.
function Tools.Direction(candle,tick)
 local o=math.round(candle.Open/tick) local c=math.round(candle.Close/tick)
 return c>o and 1 or c<o and -1 or 0
end
return Tools
