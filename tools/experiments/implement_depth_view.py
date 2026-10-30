from pathlib import Path
r=Path(__file__).resolve().parents[2]
p=r/'src/shared/Level2View.luau';s=p.read_text(encoding='utf-8')
s=s.replace('local View={};View.__index=View','local View={ExpandedHeight=322,RowHeight=22};View.__index=View')
s=s.replace('Rows={Asks={},Bids={}},Tweens={}','Rows={Asks={},Bids={}},Tweens={},Scale=16,LevelCount=ctx.levels or 5')
s=s.replace(' self.Note=label(self.Body,"LiquiditySource","Simulated market liquidity\\nNot other players\' orders",10,4,w-20,32,12,C.Muted)\n',' self.ScaleLabel=label(self.Header,"Scale","",w-156,0,110,40,11,C.Muted,Enum.TextXAlignment.Right)\n')
s=s.replace('Position=UDim2.fromOffset(8,38)','Position=UDim2.fromOffset(8,4)')
s=s.replace(' self:Update();return self',' for _,side in ipairs({"Asks","Bids"})do for i=1,self.LevelCount do self:Row(side,i)end end\n self:Update();return self')
s=s.replace('Size=UDim2.fromOffset(self.Width-16,20)','Size=UDim2.fromOffset(self.Width-16,View.RowHeight)')
s=s.replace('56,20,12,color','56,View.RowHeight,12,color').replace('self.Width-136,20,13','self.Width-136,View.RowHeight,14').replace('56,20,13,C.Text','56,View.RowHeight,14,C.Text')
start=s.index('function View:Update()')
end=s.index('function View:Destroy()',start)
s=s[:start]+'''function View:Update()
 if not self.Root.Parent then return end
 local ctx=self.Context;local expanded=ctx.expanded();local access,quote,fresh=ctx.data()
 self.Root:SetAttribute("Expanded",expanded);self.Body.Visible=expanded
 self.Chevron.Text=expanded and "−"or"+"
 if not expanded then self:SetHeight(40);return end
 -- Geometry never follows the number of levels or a transient data/access state.
 self:SetHeight(40+26+self.LevelCount*View.RowHeight*2+28+8)
 local allowed=access and access.Allowed==true
 local state=access and access.State or "Checking"
 local depth=allowed and fresh and quote and quote.Depth
 local book=type(depth)=="table"
 self.Columns.Visible=book;self.Spread.Visible=book;self.ScaleLabel.Visible=book
 self.Message.Visible=not book;self.Unlock.Visible=not allowed and state~="Checking"
 local asks,bids=book and levels(depth.Asks),book and levels(depth.Bids)
 local maximum=0
 for _,side in ipairs({asks or{},bids or{}})do for i=1,math.min(#side,self.LevelCount)do maximum=math.max(maximum,side[i].Quantity)end end
 -- A shared, labelled high-water scale prevents every bar breathing when one order disappears.
 -- The context retains this per instrument across other UI redraws. No quantity is fabricated.
 local scale=ctx.scale and ctx.scale()or self.Scale
 while scale<maximum do scale*=2 end
 self.Scale=scale;if ctx.scale then ctx.scale(scale)end
 self.ScaleLabel.Text="Bar max "..ctx.quantity(scale)
 local spreadY=26+self.LevelCount*View.RowHeight
 self.Spread.Position=UDim2.fromOffset(10,spreadY)
 local spread=asks and asks[1]and bids and bids[1]and asks[1].Price-bids[1].Price
 self.Spread.Text=spread and ("Spread  "..ctx.number(spread))or "Spread unavailable"
 for _,side in ipairs({"Asks","Bids"})do
  local data=side=="Asks"and asks or bids
  -- Use an explicit branch: a missing ask side must never accidentally borrow bids.
  if side=="Asks"then data=asks else data=bids end
  local empty=self["Empty"..side]
  local top=side=="Asks"and 26 or spreadY+28
  empty.Visible=book and (not data or #data==0)
  empty.Text=not data and (side.." unavailable")or (side=="Asks"and "No resting asks"or "No resting bids")
  empty.Position=UDim2.fromOffset(10,top+(self.LevelCount*View.RowHeight-20)/2)
  for index=1,self.LevelCount do
   local row=self:Row(side,index);local level=data and data[index]
   local slot=side=="Asks"and self.LevelCount-index or index-1
   row.Root.Position=UDim2.fromOffset(8,top+slot*View.RowHeight)
   row.Root.Visible=level~=nil
   if level then
    local changedPrice=row.Root:GetAttribute("Price")~=level.Price
    row.Side.Text=index==1 and (side=="Asks"and "Best ask"or "Best bid")or ""
    row.Root:SetAttribute("Best",index==1);row.Root:SetAttribute("Price",level.Price);row.Root:SetAttribute("Quantity",level.Quantity)
    row.Price.Text=ctx.number(level.Price);row.Quantity.Text=ctx.quantity(level.Quantity)
    local ratio=level.Quantity/scale
    if row.Ratio~=ratio or changedPrice then
     if self.Tweens[row]then self.Tweens[row]:Cancel();self.Tweens[row]=nil end
     if row.Ratio==nil or changedPrice then row.Bar.Size=UDim2.fromScale(ratio,1)
     else local tween=TweenService:Create(row.Bar,TweenInfo.new(.12,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=UDim2.fromScale(ratio,1)});self.Tweens[row]=tween;tween:Play()end
     row.Ratio=ratio
    end
   else
    if self.Tweens[row]then self.Tweens[row]:Cancel();self.Tweens[row]=nil end
    row.Ratio=nil;row.Root:SetAttribute("Price",nil);row.Root:SetAttribute("Quantity",nil)
   end
  end
 end
 if not book then
  self.Message.Text=not allowed and (state=="Checking"and "Checking L2 access…"or state=="Unavailable"and "Access check unavailable"or "Market Depth Pro · Locked")
   or fresh==false and "Depth paused · reconnecting…"or "Loading market depth…"
  if allowed and fresh and quote and quote.Depth==nil then self.Message.Text="Market depth unavailable"end
 end
end
'''+s[end:]
p.write_text(s,encoding='utf-8')
p=r/'src/shared/TerminalUI.luau';s=p.read_text(encoding='utf-8').replace(' local depthViews={}\n',' local depthViews={}\n local depthScales={}\n')
s=s.replace('  local view=Level2View.new({button=button,gloss=glossy,number=Market.Number,','  local view=Level2View.new({button=button,gloss=glossy,number=Market.Number,levels=Market.DepthLevels,\n   scale=function(value)if value then depthScales[s.Contract]=value end;return depthScales[s.Contract]or 16 end,')
p.write_text(s,encoding='utf-8')
p=r/'src/shared/MarketClient.luau';s=p.read_text(encoding='utf-8').replace('local Market={Contracts=Config.Contracts,','local Market={DepthLevels=Config.DepthLevels or 5,Contracts=Config.Contracts,');p.write_text(s,encoding='utf-8')
p=r/'src/server/Participants.luau';s=p.read_text(encoding='utf-8')
s=s.replace(' e:CancelAll(a.Id,a.Key)\n local account=e.Accounts[a.Id] if account.Locked then return end',''' local account=e.Accounts[a.Id] if account.Locked or account.Liquidating then e:CancelAll(a.Id,a.Key);return end
 local policy=self.Config.MakerQuotePolicyVersion or 2
 if a.QuotePolicy~=policy then e:CancelAll(a.Id,a.Key);a.Quotes={};a.ReplenishAt={};a.QuotePolicy=policy end''')
s=s.replace('+r:Noise()*0.7','')
s=s.replace('b.Volatility*0.2+r:Range(0,1.4)','b.Volatility*0.2')
s=s.replace(' if r:Next()>math.min(1,liquidity*1.7) then return end',''' local minRest=self.Config.MakerMinRestSeconds or 18
 local reprice=self.Config.MakerRepriceTicks or 3
 local activeDepth=liquidity<.35 and 1 or liquidity<.7 and 2 or 3''')
start=s.index('   local size=math.max(1,math.floor(a.Size*liquidity*r:Range(0.55,1.25)')
end=s.index('\n  end\n end\nend\nfunction Participants:_trader',start)
s=s[:start]+'''   local slot=tostring(side)..":"..depth
   local held=a.Quotes[slot]and e.Orders[a.Quotes[slot]]
   if a.Quotes[slot]and not held then a.Quotes[slot]=nil;a.ReplenishAt[slot]=e.Time+math.max(4,minRest/3)end
   local tick=math.max(1,math.round(center-side*(spread+(depth-1)*math.max(1,math.floor(stress)))))
   local age=held and e.Time-held.Time or math.huge
   local eligible=depth<=activeDepth
   if held and age>=minRest and (not eligible or math.abs(held.Price-tick)>=reprice)then
    e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil
   end
   if eligible and not held and e.Time>=(a.ReplenishAt[slot]or 0)then
    local size=math.max(1,math.floor(a.Size*liquidity*(1+(depth-1)*.15)*(1-inventory/a.Limit*side*.8)))
    local ok,result=e:Submit(a.Id,{Contract=a.Key,Direction=side,Quantity=size,Type="Limit",Price=tick*c.Tick,Expires=e.Time+minRest*6})
    if ok and result.Remaining>0 then a.Quotes[slot]=result.Id end
   end'''+s[end:]
s=s.replace(' if r:Next()<0.45 then e:CancelAll(a.Id,a.Key) end',''' if r:Next()<0.45 then
  local stale={}
  for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o and e.Time-o.Time>=math.max(12,a.Patience)then table.insert(stale,id)end end
  table.sort(stale);for _,id in ipairs(stale)do e:Cancel(a.Id,id)end
 end''')
p.write_text(s,encoding='utf-8')
print('Stable L2 geometry and retained maker quotes implemented.')
