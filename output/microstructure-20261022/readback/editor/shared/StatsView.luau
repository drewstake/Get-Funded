-- Stats page: trading performance for the current account. Every number is computed and
-- persisted by the server (TradeStats / FundedAccounts:Stats). Only Stats content is drawn here, using
-- individual editable components from 06 - Polished Stats Pieces. TerminalUI owns all shared navigation.
local TextService=game:GetService("TextService")
local Kit=require(script.Parent.StatsPieces)
local View={}
local LEFT,CENTER,RIGHT=Enum.TextXAlignment.Left,Enum.TextXAlignment.Center,Enum.TextXAlignment.Right
local TOP=Enum.TextYAlignment.Top
local AtEnd=Enum.TextTruncate.AtEnd
local FONT=Enum.Font.FredokaOne
local BODY=Enum.Font.GothamMedium

local function commas(n)
 local raw=tostring(math.floor(math.abs(n or 0)+0.5))
 return ((n or 0)<0 and "-" or "")..raw:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
end
local function plural(n,word) return commas(n).." "..word..(n==1 and "" or "s") end
local function pct(rate) return rate and string.format("%.1f%%",rate*100) or "—" end
local function measure(value,size,width,font) return math.ceil(TextService:GetTextSize(value,size,font or FONT,Vector2.new(math.max(1,width-4),10000)).Y*1.12)+8 end
View.Commas=commas

-- Always use the current account, including when an older UI state selected another period.
-- Do not display a previous account's cached packet while a restart is loading.
function View.Resolve(data,state,portfolio)
 local list=data and data.Scopes or {};local scope=list[1]
 state.StatsScope="ALL";state.StatsPeriod="Current"
 local agg=scope and scope.Current
 if data and portfolio and data.Run and portfolio.Run and data.Run~=portfolio.Run then agg=nil end
 return scope,agg,"Current",list
end
function View.OpenFor(scope,pf,agg)return pf and pf.Open or agg and agg.Open or 0 end
function View.Describe(scope,agg,period)
 return "Current account only. Starting money and open profit are excluded."
end
function View.Coverage(agg,signed)
 if agg.Partial then
  local count=agg.UntrackedTrades>0 and (" across "..(agg.CountUnknown and "at least " or "")..plural(agg.UntrackedTrades,"earlier trade"))
   or (agg.CountUnknown and " across an unknown number of earlier trades" or "")
  return "Results without a full breakdown (net "..signed(agg.UntrackedNet)..count..") are included in realized profit. Ratios need a complete trade breakdown."
 elseif agg.Recovered then
  return "Includes earlier trades rebuilt from your saved trade history."
 end
 return nil
end

function View.Draw(ctx,x,y,w,h,mobile)
 local C=ctx.C local s=ctx.State local data=ctx.Data
 local white=Color3.fromHex("F5F8FF") local muted=Color3.fromHex("CEDDFA")
 local sc=ctx.make("ScrollingFrame","Stats",ctx.Canvas,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),CanvasSize=UDim2.new(),
  BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=muted,ScrollingDirection=Enum.ScrollingDirection.Y})
 local cw,inset=ctx.insetScroll(sc) local narrow=cw<620 local gap=narrow and 12 or 18
 local function label(parent,name,value,xx,yy,ww,hh,size,color,body)
  return ctx.make("TextLabel",name,parent,{Position=UDim2.fromOffset(xx,yy),Size=UDim2.fromOffset(ww,hh),BackgroundTransparency=1,
   Text=value,TextColor3=color or white,TextSize=size,Font=body and BODY or FONT,TextXAlignment=LEFT,TextWrapped=true,TextScaled=false,LineHeight=1.12})
 end
 local function box(o,xx,yy,ww,hh)
  o.Position=UDim2.fromOffset(xx,yy) o.Size=UDim2.fromOffset(ww,hh) return o
 end
 local function fit(o,size)
  o.TextScaled=false;o.TextSize=size;o.LineHeight=1.12;o.TextStrokeTransparency=1
  return o
 end
 local function copy(o,xx,yy,ww,size)
  o.Font=BODY;o.TextColor3=muted;fit(o,size)
  return box(o,xx,yy,ww,measure(o.Text,size,ww,BODY)).Size.Y.Offset
 end
 -- Exact numbers keep a stable size. Exceptional values can be panned instead of shrinking.
 local function number(o,xx,yy,ww,size)
  fit(o,size);o.Font=FONT;o.TextWrapped=false;o.TextStrokeColor3=Color3.fromHex("061B48");o.TextStrokeTransparency=.86
  local hh=math.ceil(size*1.3)+8
  local needed=math.ceil(TextService:GetTextSize(o.Text,size,FONT,Vector2.new(100000,1000)).X)+8
  if needed>ww then
   local scroller=ctx.make("ScrollingFrame",o.Name.."Overflow",o.Parent,{Position=UDim2.fromOffset(xx,yy),Size=UDim2.fromOffset(ww,hh+6),
    CanvasSize=UDim2.fromOffset(needed,0),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=muted,ScrollingDirection=Enum.ScrollingDirection.X})
   o.Parent=scroller;box(o,0,0,needed,hh);o.TextXAlignment=LEFT
   return hh+6
  end
  box(o,xx,yy,ww,hh);return hh
 end
 local function piece(name,xx,yy,ww,hh)
  local o=Kit.Create(name,sc) box(o,xx,yy,ww,hh) return o
 end
 local function bind(button,fn) return button.Activated:Connect(fn) end
 local titleH=narrow and 40 or 66
 label(sc,"Title","Your Stats",4,0,cw-8,titleH,narrow and 32 or 52)
 local yy=titleH+12
 local function finish(state)
  for _,o in ipairs(sc:GetDescendants())do if o:IsA("TextLabel")or o:IsA("TextButton")then o.TextScaled=false end end
  sc.CanvasSize=UDim2.fromOffset(0,yy+inset*2+8) sc:SetAttribute("State",state) return sc
 end
 local function stateCard(name,title,body,action,fn)
  local bodyH=measure(body,16,cw-40,BODY)
  local headingH=measure(title,24,cw-40)
  local ch=headingH+bodyH+98
  local c=ctx.card(sc,name,0,yy,cw,ch,Color3.fromHex("093982"),Color3.fromHex("041B49"),Color3.fromHex("0866D6"),false)
  fit(label(c,"Heading",title,20,16,cw-40,headingH,24),24)
  local b=label(c,"Body",body,20,24+headingH,cw-40,bodyH,16,muted,true) b.TextYAlignment=TOP
  ctx.gloss(ctx.button(c,"StateAction",action,20,ch-54,math.min(260,cw-40),44,fn,C.Raised,C.Text,16),"Cyan")
  yy+=ch+gap
 end
 if not data or data.Loading then
  local waiting=ctx.Status and not ctx.CanTrade
  stateCard("StatsLoading",waiting and "Waiting for the exchange" or "Loading your stats…",
   waiting and (tostring(ctx.Status)..". Stats will load when the exchange is ready.") or "Loading closed trades from your current account.","Retry",ctx.retry)
  return finish(waiting and "Waiting" or "Loading")
 end
 if data.Error then stateCard("StatsError","Stats unavailable",data.Error,"Retry",ctx.retry) return finish("Error") end
 local scope,agg,period=View.Resolve(data,s,ctx.Portfolio)
 if data.New or not scope then
  if data.New then
   stateCard("StatsEmpty","No stats yet","Close your first trade to see your current account's results.","Go to Trade",ctx.start)
  else
   stateCard("StatsEmpty","Your stats are loading","Return to Trade while the exchange connects.","Go to Trade",ctx.start)
  end
  return finish("Empty")
 end
 -- All transient UI is confined to the Stats viewport; the terminal owns the sidebar.
 local layer=ctx.make("Frame","StatsOverlays",ctx.Canvas,{Position=UDim2.fromOffset(x+inset,y),Size=UDim2.fromOffset(cw,h),BackgroundTransparency=1,ClipsDescendants=true,ZIndex=50,Visible=not s.Overlay and not s.Sheet})
 local help
 local function closeHelp() if help then help:Destroy() help=nil end end
 local function showHelp(key,title,body,pinned)
  closeHelp()
  if pinned then s.StatsHelp=key end
  local hw=math.min(530,cw-16)
  local bodyH=measure(body,16,hw-44,BODY)
  local headingH=measure(title,24,hw-78)
  local hh=math.min(h-16,bodyH+headingH+40)
  help=ctx.make("Frame","StatsMetricHelp",layer,{Position=UDim2.fromOffset(math.max(8,(cw-hw)/2),math.max(8,(h-hh)/2)),Size=UDim2.fromOffset(hw,hh),BackgroundColor3=Color3.fromHex("062250"),ZIndex=111})
  ctx.round(help,16) ctx.stroke(help,Color3.fromHex("487DDB"))
  fit(label(help,"Title",title,20,12,hw-78,headingH,24),24).ZIndex=112
  local bodyScroll=ctx.make("ScrollingFrame","Copy",help,{Position=UDim2.fromOffset(20,headingH+20),Size=UDim2.fromOffset(hw-40,hh-headingH-32),CanvasSize=UDim2.fromOffset(0,bodyH),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ZIndex=112})
  local copy=label(bodyScroll,"Body",body,0,0,hw-44,bodyH,16,muted,true) copy.TextYAlignment=TOP copy.ZIndex=113
  local close=ctx.button(help,"Close","×",hw-54,8,44,44,function()s.StatsHelp=nil closeHelp()end,false,white,28,114)
 end
 local function helpButton(button,key,title,body)
  bind(button,function()
   if s.StatsHelp==key and help then s.StatsHelp=nil closeHelp() else showHelp(key,title,body,true) end
  end)
  button.MouseEnter:Connect(function()if not s.StatsHelp then showHelp(key,title,body,false)end end)
  button.MouseLeave:Connect(function()if not s.StatsHelp then closeHelp()end end)
  button.SelectionGained:Connect(function()if not s.StatsHelp then showHelp(key,title,body,false)end end)
  button.SelectionLost:Connect(function()if not s.StatsHelp then closeHelp()end end)
  if s.StatsHelp==key then showHelp(key,title,body,true)end
 end
 local input=game:GetService("UserInputService").InputBegan:Connect(function(ev)
  if ev.KeyCode==Enum.KeyCode.Escape or ev.KeyCode==Enum.KeyCode.ButtonB then s.StatsHelp=nil closeHelp()end
 end)
 sc:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
  if not s.StatsHelp then closeHelp()end
 end)
 sc.Destroying:Connect(function()
  input:Disconnect()
  layer:Destroy()
 end)
 if not agg then
  stateCard("StatsLoading","Loading your account stats…","Your current account's results are loading. Retry to fetch the latest stats.","Retry",ctx.retry)
  return finish("Loading")
 end
 -- Build and populate before measuring so every layout uses the actual text.
 local hero=piece("HeroCard",0,0,cw,1)
 local cards={}
 for _,key in ipairs({"Trade","Average","Factor"})do cards[key]=piece(key.."Card",0,0,1,1)end
 local daily=piece("DailyStats",0,0,cw,1)
 local formatted=Kit.ApplyAggregate(sc,agg)
 if (agg.Even or 0)>0 and not agg.Partial and not agg.CountUnknown then cards.Trade.TradeCaption.Text=formatted[2].Caption end
 if (agg.AllTrades or agg.Trades or 0)==0 and not agg.CountUnknown then daily.CoverageCopy.Text="No closed trades in this account yet." end
 local pad=narrow and 18 or 28
 for _,name in ipairs({"AttemptsLabel","ClosedTradesLabel","AttemptsIcon","ClosedTradesIcon","HeroDivider","HeroWatermark"})do
  local part=hero:FindFirstChild(name);if part then part:Destroy()end
 end
 local titleSize=narrow and 25 or 32
 local titleH=measure(hero.TotalTitle.Text,titleSize,cw-pad*2-48)
 fit(box(hero.TotalTitle,pad,18,cw-pad*2-48,titleH),titleSize)
 box(hero.TotalHelp,cw-pad-44,16,44,44)
 local hy=18+titleH+8
 -- An explicit sign reinforces the green/pink treatment without changing the amount.
 if (agg.Net or 0)>0 then hero.TotalValue.Text="+"..hero.TotalValue.Text end
 hy+=number(hero.TotalValue,pad,hy,cw-pad*2,narrow and 40 or 64)+8
 hy+=copy(hero.TotalCaption,pad,hy,cw-pad*2,16)+18
 box(hero,0,yy,cw,hy);yy+=hy+gap
 local cols=cw>=1020 and 3 or cw>=680 and 2 or 1
 local kw=(cw-gap*(cols-1))/cols
 local rowY,rowH=yy,0
 local accents={Trade=Color3.fromHex("76E5FF"),Average=Color3.fromHex("DFC4FF"),Factor=Color3.fromHex("FFE18A")}
 for i,key in ipairs({"Trade","Average","Factor"})do
  local col=(i-1)%cols
  if col==0 and i>1 then rowY+=rowH+gap;rowH=0 end
  local card=cards[key];local p=20
  local heading=card[key.."Title"]
  local headingH=measure(heading.Text,24,kw-p*2-44)
  fit(box(heading,p,18,kw-p*2-44,headingH),24)
  box(card[key.."Help"],kw-p-44,16,44,44)
  local cy=18+math.max(44,headingH)+8
  card[key.."Value"].TextColor3=accents[key]
  cy+=number(card[key.."Value"],p,cy,kw-p*2,44)+8
  box(card[key.."Bar"],p,cy,kw-p*2,14);cy+=30
  if key=="Trade" then
   cy+=copy(card.TradeCaption,p,cy,kw-p*2,16)+18
  else
   local half=(kw-p*2-16)/2
   local longest=0
   for n=0,1 do
    local value=card[key.."Detail"..n]
    if n==0 and value.Text~="—" and value.Text~="$0.00" then value.Text="+"..value.Text end
    longest=math.max(longest,TextService:GetTextSize(value.Text,21,FONT,Vector2.new(100000,1000)).X)
   end
   local stacked=longest>half
   if stacked then
    for n=0,1 do
     local labelH=copy(card[key.."DetailLabel"..n],p,cy,kw-p*2,15)
     card[key.."DetailLabel"..n].TextXAlignment=LEFT
     cy+=labelH
     card[key.."Detail"..n].TextXAlignment=LEFT
     cy+=number(card[key.."Detail"..n],p,cy,kw-p*2,21)+10
    end
   else
    local lh=0;local vh=0
    for n=0,1 do lh=math.max(lh,copy(card[key.."DetailLabel"..n],p+n*(half+16),cy,half,15))end
    cy+=lh+2
    for n=0,1 do vh=math.max(vh,number(card[key.."Detail"..n],p+n*(half+16),cy,half,21))end
    cy+=vh+18
   end
  end
  local ch=math.max(256,cy)
  box(card,col*(kw+gap),rowY,kw,ch);rowH=math.max(rowH,ch)
 end
 yy=rowY+rowH+gap
 fit(box(daily.DailyTitle,20,14,cw-88,42),28);box(daily.DailyHelp,cw-64,12,44,44)
 local stacked=cw<540
 local dw=stacked and cw-40 or (cw-64)/2
 local dy=68;local tallest=0
 for i,key in ipairs({"Day","Best"})do
  local dx=stacked and 20 or 20+(i-1)*(dw+24)
  local ty=stacked and dy or 68
  local lh=copy(daily[key.."Title"],dx,ty,dw,17)
  box(daily[key.."Calendar"],dx,ty+lh+8,37,37)
  local vh=number(daily[key.."Value"],dx+42,ty+lh+2,dw-42,32)
  tallest=math.max(tallest,lh+vh+12)
  if stacked then dy=ty+lh+vh+20 end
 end
 if not stacked then dy=68+tallest+10 end
 daily.DailyDividerA.Visible=not stacked;box(daily.DailyDividerA,cw/2-1,72,1,tallest-8)
 daily.DailyDividerB.Visible=false
 box(daily.DailyInfo,20,dy+4,30,30)
 local coverageH=copy(daily.CoverageCopy,62,dy,cw-82,16)
 daily.DatedButton:Destroy()
 local dailyH=dy+math.max(36,coverageH)+20
 box(daily,0,yy,cw,dailyH);yy+=dailyH+14
 local describe=View.Describe(scope,agg,period)
 local coverage=View.Coverage(agg,ctx.signed)
 if (agg.UndatedTrades or 0)>0 or agg.CountUnknown then
  coverage=(coverage and coverage.." " or "").."Some trades have no saved calendar date. Daily metrics are unavailable until every closed trade in this account has a date."
 end
 if not coverage and agg.AllTrades==0 then coverage="No closed trades in this account yet. Close a trade to add its result." end
 local descriptions={
  Total="Realized profit is the net profit or loss from closed trades in this account. It excludes open profit and starting money. Progress and Leaderboard use lifetime net profit across all accounts, including restarts.",
  Trade="Profitable closed trades divided by all closed trades, including break-even trades. Each closing fill counts as one trade, even when it closes only part of a position. Each has a row in Trade history.",
  Average="Average profit per winning trade divided by average loss per losing trade. Both amounts are shown below. ∞ means wins with no losses. — means there is not enough data to calculate the ratio.",
  Factor="Total profit from winning trades divided by total losses from losing trades. ∞ means profits with no losses. — means there are no profits or losses yet.",
 }
 for _,m in ipairs(formatted)do
  local button=sc:FindFirstChild(m.Key.."Help",true)
  if button then helpButton(button,m.Key,m.Title,(descriptions[m.Key] or m.Help).."\n\n"..m.Caption..(m.Key=="Total" and "\n\n"..describe or "")) end
 end
 helpButton(daily.DailyHelp,"Daily","Daily stats",formatted[4].Help.."\n"..formatted[4].Caption.."\n\n"..formatted[6].Help.."\n"..formatted[6].Caption..(coverage and "\n\n"..coverage or ""))
 sc:SetAttribute("MetricColumns",cols) sc:SetAttribute("Scope",scope.Key) sc:SetAttribute("Period",period)
 sc:SetAttribute("NetRealized",agg.Net) sc:SetAttribute("Trades",agg.AllTrades) sc:SetAttribute("Blown",agg.Blown) sc:SetAttribute("Partial",agg.Partial==true)
 return finish("Ready")
end
-- All six metrics are realized. Server Stats packets rebuild this page through TerminalUI's existing path.
function View.Update(_ctx,_sc) end
return View
