local Pool=require(script.Parent.ChartPaintPool)
return function()
 local root=Instance.new("Frame") local pool=Pool.new(root)
 local ok,result=pcall(function()
  local function mark(x,identity,animate)
   pool:Begin(animate)
   local object=pool:Get("Frame","Candle",root)
   pool:Props(object,{Position=UDim2.fromOffset(x,0),Size=UDim2.fromOffset(8,20)},identity)
   pool:Finish();return object
  end
  local candle=mark(0,60,false)
  assert(mark(0,60,true)==candle and #root:GetChildren()==1,"Unchanged paint must reuse its object")
  mark(100,60,true);assert(candle.Position.X.Offset==0,"Animation must start at the existing geometry")
  pool:Step(.02);assert(candle.Position.X.Offset>0 and candle.Position.X.Offset<100,"Intermediate geometry expected")
  pool:Step(.06);assert(candle.Position.X.Offset==100 and not next(pool.Moving),"Must settle exactly on the target")
  mark(200,60,true);pool:Step(.02)
  mark(300,120,true);assert(candle.Position.X.Offset==300,"Never animate a reused slot from a different candle")
  mark(400,120,true);pool:Step(.01);mark(450,120,false)
  assert(candle.Position.X.Offset==450 and not next(pool.Moving),"Dragging must follow the pointer without tween lag")
  mark(500,120,true);pool:Step(.01);pool:Begin(true);pool:Finish()
  assert(not candle.Visible)
  mark(500,120,true);assert(candle.Visible and candle.Position.X.Offset==500,"Hidden animation cannot resume with stale geometry")
  pool:Begin(false);local row=pool:Dash(root,0,30,600,Color3.new(1,1,1),5,3);pool:Finish()
  local count=#root:GetDescendants();local first=row:GetChildren()[1];local position=first.Position
  pool:Begin(false);local same=pool:Dash(root,0,80,600,Color3.new(1,1,1),5,3);pool:Finish()
  assert(row==same and #root:GetDescendants()==count and first.Position==position and row.Position.Y.Offset==80,"Dash movement must move only the parent")
  pool:Begin(false);pool:Dash(root,0,80,300,Color3.new(1,1,1),5,3);pool:Finish()
  local visible=0 for _,child in ipairs(row:GetChildren())do if child.Visible then visible+=1 end end
  assert(visible==30,"Resizing must hide surplus dashes")
  -- Keyed objects: a candle keeps its own object whatever order candles are drawn in.
  local keyed=Pool.new(root)
  local function draw(times)
   keyed:Begin(false) local out={}
   for _,t in ipairs(times)do out[t]=keyed:Get("Frame","KeyedCandle",root,t)end
   keyed:Finish() return out
  end
  local a=draw({60,120,180}) local b=draw({120,180,240})
  assert(a[120]==b[120] and a[180]==b[180] and b[240]~=a[60],"Keyed objects follow their identity")
  assert(not a[60].Visible and b[240].Visible,"Keyed objects out of view are hidden")
  local c=draw({60}) assert(c[60]==a[60] and c[60].Visible,"Returning candles reuse their object")
  for _=1,5 do draw({60}) end keyed:Prune(3)
  assert(a[120].Parent==nil and c[60].Parent==root,"Long-unused keyed objects are destroyed")
  return {Passed=true,Cases=10,Checks="Reuse, intermediate motion, exact settlement, candle identity, immediate drag, hidden motion, grouped dash resizing, keyed identity, keyed hiding, pruning"}
 end)
 root:Destroy();if not ok then error(result)end;return result
end
