local T=require(script.Parent.ChartTools)

return function()

 local checks=0

 local function check(ok,message) checks+=1 assert(ok,message) end

 -- A simple linear transform stands in for the chart: 10 px per minute, 4 px per point.

 local function view(left,high) return function(t)return math.floor((t-left)/6+0.5)end,function(p)return math.floor((high-p)*4+0.5)end end

 local X,Y=view(0,120)

 local candles={{Time=600,Open=100,High=110,Low=95,Close=105},{Time=660,Open=105,High=108,Low=101,Close=101}}

 local snap=T.Snap(candles,X,Y,X(600)+3,Y(110)+4)

 check(snap and snap.Field=="High" and snap.Price==110 and snap.Time==600,"Snaps to the nearest OHLC point")

 local far=T.Snap(candles,X,Y,900,-300)
 check(far and far.Time==660,"Strong snap has no distance limit, including future space")
 check(T.Snap({},X,Y,900,-300)==nil,"No candles leaves snapping empty")
 for _,field in ipairs({"Open","High","Low","Close"})do
  local hit=T.Snap({candles[1]},X,Y,X(600),Y(candles[1][field]))
  check(hit and hit.Price==candles[1][field],"Every OHLC target: "..field)
 end
 local pixels=T.Snap({{Time=0,Open=0,High=0,Low=0,Close=0},{Time=100,Open=90,High=90,Low=90,Close=90}},function(t)return t end,function(p)return p end,0,90)
 check(pixels.Time==0,"Screen-space distance beats price-only distance")
 pixels=T.Snap({{Time=0,Open=0,High=0,Low=0,Close=0},{Time=10,Open=90,High=90,Low=90,Close=90}},function(t)return t end,function(p)return p end,0,90)
 check(pixels.Time==10,"Screen-space distance beats nearest candle in time")

 local close=T.Snap(candles,X,Y,X(660),Y(101)+2) check(close.Price==101,"Snaps to close/low")

 -- Rectangles: stored in time/price, hit-tested in pixels at any zoom.

 local r=T.New("Rect",{Time=600,Price=110},{Time=720,Price=100},"BX","1m")

 check(r.Id and r.Border=="Blue" and r.Opacity==0.15,"Defaults")

 local list={r}

 local inside=T.HitTest(list,X,Y,X(660),Y(105),6,8,nil,1000)

 check(inside.Interior and inside.Part=="Slide","Interior of an unselected rectangle is flagged (the view chooses grab or pan)")

 check(T.HitTest(list,X,Y,X(660),Y(105),6,8,r.Id,1000).Part=="Slide","Interior of the selected rectangle slides it")

 check(T.HitTest(list,X,Y,X(600),Y(105),6,8,nil,1000).Part=="Slide","Edge selects/slides")

 check(T.HitTest(list,X,Y,X(720)+3,Y(100)-2,6,8,r.Id,1000).Part=="Corner3","Corner handle")

 check(T.HitTest(list,X,Y,X(900),Y(50),6,8,r.Id,1000)==nil,"Empty space pans")

 local X2,Y2=view(300,140) -- panned and rescaled chart: same drawing, new pixels

 check(T.HitTest(list,X2,Y2,X2(720),Y2(100),6,8,r.Id,1000).Part=="Corner3","Anchors follow the chart after panning")

 local original=T.Copy(r)

 T.Edit(r,original,"Move",nil,{Time=60,Price=2})

 check(r.T1==660 and r.T2==780 and r.P1==112 and r.P2==102,"Move shifts both anchors")

 T.Edit(r,original,"Slide",nil,{Time=-90,Price=7})

 check(r.T1==510 and r.T2==630 and r.P1==110 and r.P2==100,"Slide moves horizontally only: width, height and prices kept")

 T.Edit(r,original,"Slide",nil,{Time=240,Price=0})

 check(r.T2-r.T1==original.T2-original.T1 and r.P1==original.P1 and r.P2==original.P2 and r.T1==840,"Slide right keeps size")

 -- Right-edge extension handle: midpoint of the right edge, extends width only.

 local ext=T.Copy(original) local elist={ext}

 local ex,ey=T.ExtendPoint(ext,X,Y) check(ex==X(720) and ey==(Y(110)+Y(100))/2,"Extension handle sits at the right-edge midpoint")

 check(T.HitTest(elist,X,Y,ex+2,ey-1,6,8,nil,1000).Part=="Slide","Unselected rectangle has no extension hit area")

 check(T.HitTest(elist,X,Y,ex,Y(100)+2,6,8,ext.Id,1000).Part=="Corner3","Corner still reachable next to the extension handle")

 check(T.HitTest(elist,X,Y,ex+2,ey-1,6,8,ext.Id,1000).Part=="Extend","Selected rectangle extension is hittable")

 local copyR=T.Copy(original)

 T.Edit(copyR,original,"Extend",{Time=900,Price=90},{Time=180,Price=-20,MinWidth=60})

 check(copyR.T1==600 and copyR.T2==900 and copyR.P1==110 and copyR.P2==100,"Extend moves only the right edge: left edge and prices fixed")

 T.Edit(copyR,original,"Extend",{Time=300,Price=90},{MinWidth=60})

 check(copyR.T1==600 and copyR.T2==660,"Extend never crosses the left edge (one-candle minimum)")

 local flipped=T.Copy(original) flipped.T1,flipped.T2=original.T2,original.T1 local flippedOriginal=T.Copy(flipped)

 T.Edit(flipped,flippedOriginal,"Extend",{Time=840,Price=0},{MinWidth=60})

 check(flipped.T1==840 and flipped.T2==600 and flipped.P1==110,"Extend works whichever corner the rectangle was drawn from")

 T.Edit(r,original,"Corner1",{Time=540,Price=115})

 check(r.T1==540 and r.P1==115 and r.T2==720 and r.P2==100,"Corner resize keeps the opposite corner")

 local trend=T.New("Trend",{Time=0,Price=100},{Time=600,Price=110},"BX","1m")

 check(T.HitTest({trend},X,Y,X(300),Y(105),6,8,nil,1000).Drawing==trend,"Trend hit")

 local line=T.New("Line",{Time=0,Price=104},nil,"BX","1m")

 check(T.HitTest({line},X,Y,50,Y(104)+2,6,8,nil,1000).Drawing==line,"Horizontal line hit")

 -- Clipping keeps rotated trend lines inside the plot.

 local ax,ay,bx,by=T.ClipSegment(-50,50,150,50,100,100) check(ax==0 and bx==100 and ay==50,"Clip horizontal")

 check(T.ClipSegment(-10,-10,-5,-5,100,100)==nil,"Clip outside")

 -- Undo/redo restores exact drawing lists.

 local h=T.History(3) local drawings={}

 h:Record(drawings) table.insert(drawings,T.Copy(r))

 local before=T.CopyList(drawings) drawings[1].P1=200 h:Push(before)

 check(h:Undo(drawings) and drawings[1].P1==115,"Undo edit")

 check(h:Undo(drawings) and #drawings==0,"Undo create")

 check(not h:Undo(drawings),"Nothing more to undo")

 check(h:Redo(drawings) and #drawings==1 and h:Redo(drawings) and drawings[1].P1==200,"Redo")

 h:Record(drawings) check(not h:CanRedo(),"A new edit clears redo")

 for _=1,10 do h:Record(drawings) end check(#h.Past==3,"History is bounded")

 -- Direction uses exact tick counts, so float noise can never flip a candle's colour.

 check(T.Direction({Open=2218.4,Close=2218.4000000001},0.1)==0,"Doji")

 check(T.Direction({Open=2218.3,Close=2218.4},0.1)==1 and T.Direction({Open=5824.75,Close=5824.5},0.25)==-1,"Up/down")

 return {Passed=true,Cases=checks,Checks="Magnet snapping, rectangle/trend/line hit tests, anchoring after pan, move/slide/extend/resize, clipping, undo/redo, direction"}

end

