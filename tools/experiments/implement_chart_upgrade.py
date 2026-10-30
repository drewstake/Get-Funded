from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sub(s,a,b):
 assert a in s,a[:120]
 return s.replace(a,b)
p=ROOT/'src/shared/ChartView.luau';s=p.read_text(encoding='utf-8')
s=s.replace('d.Contract==s.Contract and d.Timeframe==s.Timeframe','d.Contract==s.Contract')
s=s.replace('d.Contract==self.S.Contract and d.Timeframe==self.S.Timeframe','d.Contract==self.S.Contract')
s=sub(s,'if self.S.Tool~="Rect" or self.LastTouch or not self:CtrlDown()then self.RectangleLockTime=nil;return end',
 'local rect=self.S.Tool=="Rect" or self.Drag and self.Drag.Kind=="Edit" and self.Drag.Target.Kind=="Rect"\n if not rect or self.LastTouch or not self:CtrlDown() or self:SnapBypassed()then self.RectangleLockTime=nil;self.SoftSnap=nil;return end')
s=sub(s,'self.RectangleLockTime=Viewport.TimeAt(g.View,x/g.Width)','local c=Tools.NearestCandle(g.Data,g.X,x)\n  self.RectangleLockTime=c and c.Time or Viewport.TimeAt(g.View,x/g.Width)')
s=sub(s,'pt.Time=self.RectangleLockTime\n  return pt','pt.Time=self.RectangleLockTime\n  local g=self.Geometry;local candle=Tools.NearestCandle(g.Data,g.X,g.X(pt.Time))\n  self.SoftSnap=Tools.SoftSnap(candle,g.Y,y,self.SoftSnap)\n  if self.SoftSnap then pt.Price=self.SoftSnap.Price;pt.Snap=self.SoftSnap end\n  return pt')
s=sub(s,'-- Rectangle Ctrl locks only time; price continues following the pointer freely.', '-- Rectangle Ctrl retains its selected candle and softly attracts nearby OHLC prices.')
s=sub(s,'local lineColor=C.Muted','if self.RectangleLockTime~=nil then\n    local point=self:PlacementPointAt(x,y,false)\n    if point.Snap then n=point.Price;cy=math.floor(g.Y(n)+.5);ctx.Root:SetAttribute("CrosshairSnapped",true)end\n   end\n   local lineColor=C.Muted')
s=sub(s,'local protectionHits={}','local protectionHits={}\n self.EntryMarker=nil')
s=sub(s,'tag:SetAttribute("Price",n)','tag:SetAttribute("Price",n)\n  if opts and opts.Name=="EntryTag"then self.EntryMarker={X=tx-left,Y=ty-top,W=width,H=th}end')
s=sub(s,'local adjustment=drag and drag.Kind=="Protection" and drag or self.Pending','local adjustment=drag and drag.Kind=="Protection" and (not drag.Creating or drag.Moved) and drag or self.Pending')
s=sub(s,'-- Stop and target labels keep priority over drawing tools.', '-- Stop and target labels keep priority over drawing tools.')
needle='if x>g.Width then\n  -- Price axis:'
s=sub(s,needle,'''local entry=self.EntryMarker
 if kind~=MB3 and entry and held and not held.Triggered and (not held.Stop or not held.Target) and not self.Pending and not self.OrderPending
  and x>=entry.X and x<=entry.X+entry.W and y>=entry.Y and y<=entry.Y+entry.H then
  start("Protection",{Creating=true,Key=g.Key,Contract=s.Contract,Base=session.AccountKey,Id=held.Id,
   Original=held.Entry,Price=held.Entry,Entry=held.Entry,Quantity=held.Quantity,Direction=held.Direction,Stop=held.Stop,Target=held.Target})
  self.Ctx.Root:SetAttribute("DraggingProtection","Create");return
 end
 if x>g.Width then
  -- Price axis:''')
s=sub(s,'d.Price=math.max(tick,Market.Snap(d.Original-delta.Y/d.Height*(d.View.High-d.View.Low),d.Contract))',
 'd.Price=math.max(tick,Market.Snap(d.Original-delta.Y/d.Height*(d.View.High-d.View.Low),d.Contract))\n  if d.Creating then\n   local field=Tools.ProtectionField(d.Direction,d.Entry,d.Price)\n   d.Field=field and not d[field] and field or nil\n   self.Ctx.Root:SetAttribute("DraggingProtection",d.Field or "Unavailable")\n  end')
s=sub(s,'if commit and d.Moved and d.Price~=d.Original then\n   local ok,message,_,requestId=self.Ctx.Session:AmendProtection(d.Contract,d.Id,d.Field,d.Price,d.Original)',
 'if commit and d.Moved and d.Price~=d.Original and d.Field then\n   local ok,message,_,requestId\n   if d.Creating then ok,message,_,requestId=self.Ctx.Session:CreateProtection(d.Contract,d.Id,d.Field,d.Price,d.Quantity)\n   else ok,message,_,requestId=self.Ctx.Session:AmendProtection(d.Contract,d.Id,d.Field,d.Price,d.Original)end')
s=sub(s,'or held.Triggered or held[d.Field]~=d.Original then', 'or held.Triggered\n   or d.Creating and (held.Quantity~=d.Quantity or held.Entry~=d.Entry or held.Stop~=d.Stop or held.Target~=d.Target)\n   or not d.Creating and held[d.Field]~=d.Original then')
s=sub(s,'or held.Triggered or not held[pending.Field]then', 'or held.Triggered or not pending.Creating and not held[pending.Field]then')
s=sub(s,'function View:CancelPlacement() self.Placement=nil self.RectangleLockTime=nil ', 'function View:CancelPlacement() self.Placement=nil self.RectangleLockTime=nil self.SoftSnap=nil ')
p.write_text(s,encoding='utf-8')
