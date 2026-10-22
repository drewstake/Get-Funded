-- Native implementation of output/imagegen/while-you-were-away-clean-v1.png.
-- One full P&L amount comes from the server's return snapshot. Trades are always shown.
local TextService=game:GetService("TextService")
local View={}
local FONT=Enum.Font.FredokaOne
local LEFT,CENTER,RIGHT=Enum.TextXAlignment.Left,Enum.TextXAlignment.Center,Enum.TextXAlignment.Right
local function netPnl(summary)return (summary.Realized or 0)+(summary.Unrealized or 0)end
function View.ShouldShow(summary)
 return summary~=nil and (#(summary.Rows or {})>0 or netPnl(summary)~=0)
end
function View.Draw(ctx,w,h,summary,dismiss)
 local C=ctx.C
 local scale=math.min((w-24)/360,1.28)
 local compact=h-24<474*scale
 if compact then scale=math.min(scale,1)end
 local function px(n)return math.round(n*scale)end
 local pw=px(360)
 local baseHeight=math.min(h-24,px(compact and 356 or 474))
 local pad=px(22);local iw=pw-2*pad
 local panel=ctx.frame(ctx.Canvas,"AwayDialog",(w-pw)/2,(h-baseHeight)/2,pw,baseHeight,Color3.new(1,1,1),41)
 panel:SetAttribute("StaticButtons",true)
 ctx.round(panel,px(20));ctx.stroke(panel,C.Cyan).Thickness=2
 ctx.tint(panel,Color3.fromRGB(5,37,94),Color3.fromRGB(2,18,52))
 local function label(parent,name,value,x,y,ww,hh,size,color,align)
  local t=ctx.text(parent,name,value,x,y,ww,hh,size,color or C.Text,FONT,align or LEFT,44)
  t.TextStrokeTransparency=1
  return t
 end
 local function fit(t,size)
  t.TextScaled=true
  local constraint=Instance.new("UITextSizeConstraint");constraint.MinTextSize=10;constraint.MaxTextSize=size;constraint.Parent=t
  return t
 end
 local function color(n)return n<0 and C.Red or n>0 and C.Green or C.Muted end
 local secs=math.max(0,math.floor(summary.Seconds or 0))
 local elapsed=secs>=86400 and string.format("%dd %dh",secs//86400,secs%86400//3600)
  or secs>=3600 and string.format("%dh %dm",secs//3600,secs%3600//60)
  or secs>=60 and string.format("%dm %ds",secs//60,secs%60)or string.format("%ds",secs)

 -- Native shapes reproduce the mockup's purple clock without a raster dependency.
 local clockSize=px(compact and 40 or 56)
 local clock=ctx.frame(panel,"AwayArtwork",px(compact and 25 or 44),px(compact and 16 or 42),clockSize,clockSize,Color3.new(1,1,1),43)
 ctx.round(clock,clockSize/2);ctx.tint(clock,Color3.fromRGB(177,93,255),Color3.fromRGB(102,36,243))
 local inset=math.max(4,px(compact and 5 or 7))
 local face=ctx.frame(clock,"Face",inset,inset,clockSize-2*inset,clockSize-2*inset,Color3.fromRGB(10,27,74),44);ctx.round(face,clockSize/2)
 local function hand(name,x,y,ww,hh,rotation)
  local f=ctx.frame(clock,name,x,y,ww,hh,C.Text,45);ctx.round(f,ww/2);f.Rotation=rotation or 0
 end
 hand("Minute",clockSize*.45,clockSize*.23,clockSize*.10,clockSize*.31)
 hand("Hour",clockSize*.46,clockSize*.48,clockSize*.27,clockSize*.10,20)
 for i,ray in ipairs({{.86,-.24,.09,.25,20},{1.12,-.08,.09,.23,48},{1.23,.20,.19,.08,0}})do
  local f=ctx.frame(clock,"Ray"..i,clockSize*ray[1],clockSize*ray[2],clockSize*ray[3],clockSize*ray[4],C.Cyan,44)
  ctx.round(f,px(3));f.Rotation=ray[5]
 end
 local titleX=px(compact and 82 or 128)
 fit(label(panel,"Title",compact and "While you were away"or "While you\nwere away",titleX,px(compact and 13 or 26),pw-titleX-px(18),px(compact and 28 or 66),px(compact and 23 or 32)),px(compact and 23 or 32))
 fit(label(panel,"TimeAway","Away for "..elapsed,titleX,px(compact and 43 or 96),pw-titleX-px(18),px(23),px(compact and 14 or 16),C.Muted),px(compact and 14 or 16))

 local bodyTop=px(compact and 68 or 136)
 local body=Instance.new("ScrollingFrame");body.Name="Results";body.Position=UDim2.fromOffset(pad,bodyTop)
 body.BackgroundTransparency=1;body.BorderSizePixel=0;body.ScrollBarThickness=0;body.ScrollBarImageColor3=C.Muted
 body.ScrollingDirection=Enum.ScrollingDirection.Y;body.ClipsDescendants=true;body.ZIndex=43;body.Parent=panel
 body:SetAttribute("StaticButtons",true)
 local total=netPnl(summary)
 label(body,"NetChange","Total P&L",0,0,compact and iw*.4 or iw,px(compact and 30 or 22),px(compact and 14 or 16),C.Muted,compact and LEFT or CENTER)
 fit(label(body,"Total",ctx.signed(total),compact and iw*.4 or 0,px(compact and 0 or 24),compact and iw*.6 or iw,px(compact and 32 or 58),px(compact and 28 or 48),color(total),compact and RIGHT or CENTER),px(compact and 28 or 48))
 label(body,"SinceLeft","At your return",0,px(compact and 30 or 84),iw,px(compact and 18 or 22),px(compact and 12 or 15),C.Muted,compact and LEFT or CENTER)
 local function rule(name,y)
  local f=ctx.frame(body,name,0,px(y),iw,1,C.Border,43);f.BackgroundTransparency=.25
 end
 rule("SummaryDivider",compact and 50 or 106)

 local rows=summary.Rows or {}
 local headingY=px(compact and 58 or 118)
 local headingBand=ctx.frame(body,"TradesHeaderBand",0,headingY,iw,px(26),Color3.fromRGB(12,46,99),43);ctx.round(headingBand,px(5))
 local accent=ctx.frame(body,"TradesHeaderAccent",px(6),headingY+px(6),px(3),px(14),C.Cyan,44);ctx.round(accent,px(1))
 label(body,"TradesHeading","Trades",px(17),headingY,iw-px(29),px(26),px(20),C.Cyan)
 local detailsTop=px(compact and 88 or 152)
 local details=ctx.frame(body,"TradeDetails",0,detailsTop,iw,0,C.Panel,43);details.BackgroundTransparency=1
 local yy=0;local detailWidth=iw-px(12)
 local function copy(name,value,size,tone)
  local fontSize=px(size)
  local height=TextService:GetTextSize(value,fontSize,FONT,Vector2.new(detailWidth,10000)).Y+px(8)
  local t=label(details,name,value,px(6),yy,detailWidth,height,fontSize,tone)
  t.TextWrapped=true;t.TextYAlignment=Enum.TextYAlignment.Top;yy+=height+px(4)
 end
 if #rows==0 then copy("Empty","No trades changed while you were away.",14,C.Muted)end
 for i,row in ipairs(rows)do
  if i>1 then yy+=px(10)end
  copy("Trade"..i,row.Contract.." · "..(row.Direction>0 and "Long "or "Short ")..row.Quantity,17)
  for j,exit in ipairs(row.Exits or {})do
   local quantity=exit.Quantity or 0
   copy("Exit"..i.."_"..j,exit.Reason.." · "..quantity.." closed",13,C.Muted)
  end
 end
 details.Size=UDim2.fromOffset(iw,yy)
 -- Grow to fit the visible trades; short screens scroll the content above the fixed action.
 local canvasH=detailsTop+yy
 local buttonH=compact and 44 or px(60);local bottomPad=px(compact and 12 or 16)
 local ph=math.min(h-24,bodyTop+canvasH+px(14)+buttonH+bottomPad)
 panel.Position=UDim2.fromOffset((w-pw)/2,(h-ph)/2);panel.Size=UDim2.fromOffset(pw,ph)
 local buttonY=ph-bottomPad-buttonH;local viewportH=buttonY-px(14)-bodyTop
 body.Size=UDim2.fromOffset(iw,viewportH);body.CanvasSize=UDim2.fromOffset(0,canvasH)
 body.ScrollBarThickness=canvasH>viewportH and 3 or 0
 local continue=ctx.button(panel,"Continue","Continue",pad-px(4),buttonY,iw+px(8),buttonH,dismiss,C.Raised,C.Text,px(compact and 23 or 27),45)
 ctx.gloss(continue,"Purple");continue.Corners.CornerRadius=UDim.new(0,px(14));continue.Border.Thickness=px(3)
 panel:SetAttribute("SummaryId",summary.Id);panel:SetAttribute("Total",total);panel:SetAttribute("TradeCount",#rows)
 return panel
end
return View
