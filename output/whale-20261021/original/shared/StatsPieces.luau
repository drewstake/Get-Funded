-- Stats-only adaptation of 06 - Polished Stats Pieces. No assembled screen, sidebar, or demo fixtures.
local HttpService=game:GetService("HttpService")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Spec=HttpService:JSONDecode([====[{"colors":{"bg":"#031634","blueTop":"#093982","blueBottom":"#041B49","blueEdge":"#0866D6","purpleTop":"#7531FF","purpleBottom":"#2813A5","purpleEdge":"#A16AFF","text":"#F5F8FF","muted":"#ABC8F6","gain":"#20EDAE","loss":"#FF69A7","gold":"#FFCF36","track":"#28518D"},"templates":{"HeroCard":{"kind":"Frame","name":"HeroCard","x":0,"y":0,"w":1364,"h":214,"top":"#7531FF","bottom":"#2813A5","edge":"#A16AFF","radius":19,"stroke":3,"children":[{"kind":"TextLabel","name":"TotalTitle","x":32,"y":22,"w":190,"h":44,"text":"Realized profit","size":34,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"TextButton","name":"TotalHelp","x":200,"y":19,"w":44,"h":44,"children":[{"kind":"Frame","name":"TotalHelpDisc","x":7,"y":7,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"TotalHelpDiscGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0}]},{"kind":"TextLabel","name":"TotalValue","x":32,"y":74,"w":820,"h":92,"text":"\u2014","size":84,"color":"#FF69A7","font":"display","align":"left"},{"kind":"TextLabel","name":"TotalCaption","x":32,"y":164,"w":640,"h":35,"text":"Current account · closed trades","size":22,"color":"#ABC8F6","font":"body","align":"left"},{"kind":"Frame","name":"HeroDivider","x":852,"y":40,"w":1,"h":134,"bg":"#775BFA"},{"kind":"TextLabel","name":"AttemptsLabel","x":900,"y":56,"w":166,"h":30,"text":"\u2014","size":22,"color":"#F5F8FF","font":"body","align":"left"},{"kind":"TextLabel","name":"ClosedTradesLabel","x":1090,"y":56,"w":250,"h":30,"text":"\u2014","size":22,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"AttemptsIcon","x":940,"y":102,"w":52,"h":52,"children":[{"kind":"Frame","name":"AttemptsIconBody","x":10.4,"y":6.24,"w":31.2,"h":41.6,"top":"#A794FF","bottom":"#674AF0","radius":7},{"kind":"Frame","name":"AttemptsIconClip","x":18.72,"y":0,"w":14.560000000000002,"h":13.52,"bg":"#B5A7FF","radius":5},{"kind":"Frame","name":"AttemptsIcon0","x":17.16,"y":18.72,"w":17.68,"h":3,"bg":"#5B35CF","radius":2},{"kind":"Frame","name":"AttemptsIcon1","x":17.16,"y":27.04,"w":17.68,"h":3,"bg":"#5B35CF","radius":2},{"kind":"Frame","name":"AttemptsIcon2","x":17.16,"y":35.36,"w":17.68,"h":3,"bg":"#5B35CF","radius":2}]},{"kind":"Frame","name":"ClosedTradesIcon","x":1136,"y":94,"w":68,"h":68,"children":[{"kind":"Frame","name":"ClosedTradesIcon0","x":5.44,"y":40.8,"w":15.64,"h":23.799999999999997,"top":"#B38CFF","bottom":"#6031EE","radius":5},{"kind":"Frame","name":"ClosedTradesIcon1","x":25.84,"y":27.2,"w":15.64,"h":37.400000000000006,"top":"#B38CFF","bottom":"#6031EE","radius":5},{"kind":"Frame","name":"ClosedTradesIcon2","x":46.239999999999995,"y":13.599999999999998,"w":15.64,"h":51.0,"top":"#B38CFF","bottom":"#6031EE","radius":5}]},{"kind":"Frame","name":"HeroWatermark","x":1240,"y":106,"w":110,"h":110,"children":[{"kind":"Frame","name":"HeroWatermark0","x":8.8,"y":66.0,"w":25.3,"h":38.5,"top":"#B38CFF","bottom":"#6031EE","radius":5,"transparency":0.8},{"kind":"Frame","name":"HeroWatermark1","x":41.8,"y":43.99999999999999,"w":25.3,"h":60.50000000000001,"top":"#B38CFF","bottom":"#6031EE","radius":5,"transparency":0.8},{"kind":"Frame","name":"HeroWatermark2","x":74.8,"y":21.999999999999996,"w":25.3,"h":82.5,"top":"#B38CFF","bottom":"#6031EE","radius":5,"transparency":0.8}]}]},"TradeCard":{"kind":"Frame","name":"TradeCard","x":0,"y":0,"w":446,"h":265,"top":"#093982","bottom":"#041B49","edge":"#0866D6","radius":19,"stroke":2,"children":[{"kind":"TextLabel","name":"TradeTitle","x":26,"y":22,"w":358,"h":44,"text":"Trade win rate","size":28,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"TextButton","name":"TradeHelp","x":384,"y":16,"w":44,"h":44,"children":[{"kind":"Frame","name":"TradeHelpDisc","x":7,"y":7,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"TradeHelpDiscGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0}]},{"kind":"TextLabel","name":"TradeValue","x":26,"y":82,"w":394,"h":59,"text":"\u2014","size":52,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"TradeBar","x":26,"y":150,"w":394,"h":21,"bg":"#28518D","radius":11,"clip":true,"children":[]},{"kind":"TextLabel","name":"TradeCaption","x":26,"y":210,"w":394,"h":36,"text":"\u2014","size":21,"color":"#ABC8F6","font":"body","align":"left"}]},"AverageCard":{"kind":"Frame","name":"AverageCard","x":0,"y":0,"w":440,"h":265,"top":"#093982","bottom":"#041B49","edge":"#0866D6","radius":19,"stroke":2,"children":[{"kind":"TextLabel","name":"AverageTitle","x":26,"y":22,"w":352,"h":44,"text":"Avg win / avg loss","size":28,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"TextButton","name":"AverageHelp","x":378,"y":16,"w":44,"h":44,"children":[{"kind":"Frame","name":"AverageHelpDisc","x":7,"y":7,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"AverageHelpDiscGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0}]},{"kind":"TextLabel","name":"AverageValue","x":26,"y":82,"w":388,"h":59,"text":"\u2014","size":52,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"AverageBar","x":26,"y":150,"w":388,"h":21,"bg":"#28518D","radius":11,"clip":true,"children":[]},{"kind":"TextLabel","name":"AverageDetailLabel0","x":26,"y":187,"w":194.0,"h":29,"text":"Avg win","size":19,"color":"#ABC8F6","font":"body","align":"left"},{"kind":"TextLabel","name":"AverageDetail0","x":26,"y":216,"w":194.0,"h":29,"text":"\u2014","size":22,"color":"#20EDAE","font":"display","align":"left"},{"kind":"TextLabel","name":"AverageDetailLabel1","x":220.0,"y":187,"w":194.0,"h":29,"text":"Avg loss","size":19,"color":"#ABC8F6","font":"body","align":"right"},{"kind":"TextLabel","name":"AverageDetail1","x":220.0,"y":216,"w":194.0,"h":29,"text":"\u2014","size":22,"color":"#FF69A7","font":"display","align":"right"}]},"FactorCard":{"kind":"Frame","name":"FactorCard","x":0,"y":0,"w":443,"h":265,"top":"#093982","bottom":"#041B49","edge":"#0866D6","radius":19,"stroke":2,"children":[{"kind":"TextLabel","name":"FactorTitle","x":26,"y":22,"w":355,"h":44,"text":"Profit factor","size":28,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"TextButton","name":"FactorHelp","x":381,"y":16,"w":44,"h":44,"children":[{"kind":"Frame","name":"FactorHelpDisc","x":7,"y":7,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"FactorHelpDiscGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0}]},{"kind":"TextLabel","name":"FactorValue","x":26,"y":82,"w":391,"h":59,"text":"\u2014","size":52,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"FactorBar","x":26,"y":150,"w":391,"h":21,"bg":"#28518D","radius":11,"clip":true,"children":[]},{"kind":"TextLabel","name":"FactorDetailLabel0","x":26,"y":187,"w":195.5,"h":29,"text":"Gross wins","size":19,"color":"#ABC8F6","font":"body","align":"left"},{"kind":"TextLabel","name":"FactorDetail0","x":26,"y":216,"w":195.5,"h":29,"text":"\u2014","size":22,"color":"#20EDAE","font":"display","align":"left"},{"kind":"TextLabel","name":"FactorDetailLabel1","x":221.5,"y":187,"w":195.5,"h":29,"text":"Gross losses","size":19,"color":"#ABC8F6","font":"body","align":"right"},{"kind":"TextLabel","name":"FactorDetail1","x":221.5,"y":216,"w":195.5,"h":29,"text":"\u2014","size":22,"color":"#FF69A7","font":"display","align":"right"}]},"DailyStats":{"kind":"Frame","name":"DailyStats","x":0,"y":0,"w":1362,"h":158,"top":"#093982","bottom":"#041B49","edge":"#0866D6","radius":19,"stroke":2,"children":[{"kind":"TextLabel","name":"DailyTitle","x":26,"y":14,"w":230,"h":42,"text":"Daily stats","size":30,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"TextButton","name":"DailyHelp","x":176,"y":12,"w":44,"h":44,"children":[{"kind":"Frame","name":"DailyHelpDisc","x":7,"y":7,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"DailyHelpDiscGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0}]},{"kind":"TextLabel","name":"DayTitle","x":82,"y":63,"w":265,"h":29,"text":"Day win rate","size":21,"color":"#ABC8F6","font":"body","align":"left"},{"kind":"Frame","name":"DayCalendar","x":28,"y":95,"w":37,"h":37,"children":[{"kind":"Frame","name":"DayCalendarBody","x":4.4399999999999995,"y":7.4,"w":28.12,"h":25.9,"bg":"#092D6E","edge":"#80B5FF","stroke":3,"radius":4},{"kind":"Frame","name":"DayCalendarTop","x":5.180000000000001,"y":14.06,"w":26.64,"h":3,"bg":"#80B5FF"},{"kind":"Frame","name":"DayCalendarRing0.3","x":9.1,"y":0,"w":4,"h":11.1,"bg":"#80B5FF","radius":2},{"kind":"Frame","name":"DayCalendarRing0.7","x":23.9,"y":0,"w":4,"h":11.1,"bg":"#80B5FF","radius":2},{"kind":"Frame","name":"DayCalendarDot00","x":9.25,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"DayCalendarDot01","x":16.650000000000002,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"DayCalendarDot02","x":24.05,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"DayCalendarDot10","x":9.25,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"DayCalendarDot11","x":16.650000000000002,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"DayCalendarDot12","x":24.05,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1}]},{"kind":"TextLabel","name":"DayValue","x":82,"y":96,"w":220,"h":37,"text":"\u2014","size":34,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"DailyDividerA","x":376,"y":69,"w":1,"h":66,"bg":"#365DE0"},{"kind":"TextLabel","name":"BestTitle","x":452,"y":63,"w":337,"h":29,"text":"Best day share","size":21,"color":"#ABC8F6","font":"body","align":"left"},{"kind":"Frame","name":"BestCalendar","x":444,"y":95,"w":37,"h":37,"children":[{"kind":"Frame","name":"BestCalendarBody","x":4.4399999999999995,"y":7.4,"w":28.12,"h":25.9,"bg":"#092D6E","edge":"#80B5FF","stroke":3,"radius":4},{"kind":"Frame","name":"BestCalendarTop","x":5.180000000000001,"y":14.06,"w":26.64,"h":3,"bg":"#80B5FF"},{"kind":"Frame","name":"BestCalendarRing0.3","x":9.1,"y":0,"w":4,"h":11.1,"bg":"#80B5FF","radius":2},{"kind":"Frame","name":"BestCalendarRing0.7","x":23.9,"y":0,"w":4,"h":11.1,"bg":"#80B5FF","radius":2},{"kind":"Frame","name":"BestCalendarDot00","x":9.25,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"BestCalendarDot01","x":16.650000000000002,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"BestCalendarDot02","x":24.05,"y":19.240000000000002,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"BestCalendarDot10","x":9.25,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"BestCalendarDot11","x":16.650000000000002,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1},{"kind":"Frame","name":"BestCalendarDot12","x":24.05,"y":26.27,"w":3.7,"h":3.7,"bg":"#80B5FF","radius":1}]},{"kind":"TextLabel","name":"BestValue","x":496,"y":96,"w":245,"h":37,"text":"\u2014","size":34,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"DailyDividerB","x":777,"y":69,"w":1,"h":66,"bg":"#365DE0"},{"kind":"Frame","name":"DailyInfo","x":817,"y":77,"w":30,"h":30,"children":[{"kind":"TextLabel","name":"DailyInfoGlyph","x":0,"y":-1,"w":30,"h":30,"text":"i","size":23,"color":"#123A83","font":"display","align":"center"}],"bg":"#94C9FF","radius":15.0},{"kind":"TextLabel","name":"CoverageCopy","x":864,"y":70,"w":279,"h":66,"text":"\u2014","size":17,"color":"#F5F8FF","font":"body","align":"left"},{"kind":"TextButton","name":"DatedButton","x":1136,"y":71,"w":206,"h":52,"top":"#0A3274","bottom":"#031B4E","edge":"#265DC0","radius":12,"stroke":2,"children":[{"kind":"TextLabel","name":"DatedButtonLabel","x":18,"y":0,"w":164,"h":52,"text":"View dated history","size":18,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"DatedArrow","x":178,"y":16,"w":20,"h":20,"children":[{"kind":"Frame","name":"DatedArrowLeft","x":5.4,"y":8.6,"w":6.6000000000000005,"h":3,"bg":"#FFFFFF","rotation":45,"radius":2},{"kind":"Frame","name":"DatedArrowRight","x":9.6,"y":8.6,"w":6.6000000000000005,"h":3,"bg":"#FFFFFF","rotation":-45,"radius":2}],"rotation":-90}]}]},"FundedDropdown":{"kind":"TextButton","name":"FundedDropdown","x":0,"y":0,"w":393,"h":56,"top":"#0A3274","bottom":"#031B4E","edge":"#265DC0","radius":12,"stroke":2,"children":[{"kind":"TextLabel","name":"FundedDropdownLabel","x":18,"y":0,"w":323,"h":56,"text":"\u2014","size":20,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"FundedDropdownChevron","x":350,"y":16,"w":24,"h":24,"children":[{"kind":"Frame","name":"FundedDropdownChevronLeft","x":6.48,"y":10.32,"w":7.92,"h":3,"bg":"#FFFFFF","rotation":45,"radius":2},{"kind":"Frame","name":"FundedDropdownChevronRight","x":11.52,"y":10.32,"w":7.92,"h":3,"bg":"#FFFFFF","rotation":-45,"radius":2}]}]},"ScopeDropdown":{"kind":"TextButton","name":"ScopeDropdown","x":0,"y":0,"w":282,"h":56,"top":"#0A3274","bottom":"#031B4E","edge":"#265DC0","radius":12,"stroke":2,"children":[{"kind":"TextLabel","name":"ScopeDropdownLabel","x":18,"y":0,"w":212,"h":56,"text":"\u2014","size":20,"color":"#F5F8FF","font":"display","align":"left"},{"kind":"Frame","name":"ScopeDropdownChevron","x":239,"y":16,"w":24,"h":24,"children":[{"kind":"Frame","name":"ScopeDropdownChevronLeft","x":6.48,"y":10.32,"w":7.92,"h":3,"bg":"#FFFFFF","rotation":45,"radius":2},{"kind":"Frame","name":"ScopeDropdownChevronRight","x":11.52,"y":10.32,"w":7.92,"h":3,"bg":"#FFFFFF","rotation":-45,"radius":2}]}]}}}]====])
local Kit={Spec=Spec}
local function color(hex)return Color3.fromHex(hex)end
local T={Text=color(Spec.colors.text),Muted=color(Spec.colors.muted),Gain=color(Spec.colors.gain),Loss=color(Spec.colors.loss)}
local function make(className,name,parent,props)
 local o=Instance.new(className);o.Name=name
 for k,v in pairs(props or {})do o[k]=v end
 o.Parent=parent;return o
end
local function build(n,parent)
 local o=make(n.kind,n.name,nil,{Position=UDim2.fromOffset(n.x,n.y),Size=UDim2.fromOffset(n.w,n.h),BorderSizePixel=0,
  BackgroundTransparency=(n.top or n.bg)and(n.transparency or 0)or 1,BackgroundColor3=n.top and Color3.new(1,1,1)or n.bg and color(n.bg)or Color3.new(),
  Rotation=n.rotation or 0,ClipsDescendants=n.clip or false})
 if o:IsA("TextLabel")or o:IsA("TextButton")then
  o.Text=n.text or "";o.TextColor3=color(n.color or Spec.colors.text);o.TextSize=n.size or 20
  o.Font=Enum.Font.FredokaOne
  o.TextXAlignment=n.align=="right"and Enum.TextXAlignment.Right or n.align=="center"and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
  o.TextWrapped=true;o.TextStrokeTransparency=1
 end
 if o:IsA("TextButton")then o.AutoButtonColor=false;o.Active=true;o.Selectable=true end
 if o:IsA("ImageLabel")then o.Image=n.image;o.ScaleType=Enum.ScaleType.Fit end
 if n.radius then make("UICorner","Corners",o,{CornerRadius=UDim.new(0,n.radius)})end
 if n.edge then make("UIStroke","Border",o,{Color=color(n.edge),Thickness=n.stroke or 1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border})end
 if n.top then make("UIGradient","Gradient",o,{Color=ColorSequence.new(color(n.top),color(n.bottom)),Rotation=90})end
 for _,child in ipairs(n.children or {})do build(child,o)end
 o.Parent=parent;return o
end
function Kit.Create(name,parent)
 assert(Spec.templates[name],"Unknown component: "..tostring(name))
 return build(Spec.templates[name],parent)
end
local function money(v)
 if v==nil then return "—" end
 local sign=v<0 and "-" or ""
 local raw=string.format("%.2f",math.abs(v))
 local whole,fraction=raw:match("^(%d+)%.(%d+)$")
 whole=whole:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
 return sign.."$"..whole.."."..fraction
end
local function percent(v) return v~=nil and string.format("%.2f%%",v*100) or "—" end
local function ratio(v,noLoss) return noLoss and "∞" or v~=nil and string.format("%.2f",v) or "—" end

-- Consumes the same aggregate fields as src/StatsView.luau.
-- Ratios are supplied by the exchange; this adapter only formats them.
function Kit.FromAggregate(a)
 a=a or {}
 local complete=not a.Partial and not a.CountUnknown
 local noLoss=complete and a.NoLosses
 local net=a.Net or 0
 local daily=a.DailyComplete==true
 local best= daily and net>0 and a.BestDayShare or nil
 local unknown="Earlier breakdown unavailable"
 return {
  {Key="Total",Title="Realized profit",Value=money(net),Caption="Current account · closed trades",Color=net<0 and T.Loss or net>0 and T.Gain or T.Text,
   Help="Net profit or loss from closed trades in this account. Excludes open profit and starting money."},
  {Key="Trade",Title="Trade win rate",Value=complete and percent(a.WinRate) or "—",
   Caption=complete and string.format("%d wins / %d trades · %d even",a.Wins or 0,a.Trades or 0,a.Even or 0) or unknown,
   Bars=complete and {a.Wins or 0,a.Losses or 0,a.Even or 0} or nil,
   Help="Profitable closed trades divided by all closed trades, including break-even trades. Each closing fill counts as one trade."},
  {Key="Average",Title="Avg win / avg loss",Value=complete and ratio(a.WinLossRatio,noLoss) or "—",
   Caption=not complete and unknown or noLoss and "No losing trades" or "Average win ÷ absolute average loss",
   Bars=complete and {a.AvgWin or 0,a.AvgLoss or 0,0} or nil,
   Details=complete and {{"Avg win",money(a.AvgWin)},{"Avg loss",a.AvgLoss and money(-a.AvgLoss) or "—"}} or nil,
   Help="Average profit per winning trade divided by average loss per losing trade. ∞ means wins with no losses."},
  {Key="Day",Title="Day win rate",Value=daily and percent(a.DayWinRate) or "—",
   Caption=daily and string.format("%d profitable / %d UTC days",a.WinningDays or 0,a.DayCount or 0) or "Needs complete trade dates",
   Bars=daily and {a.WinningDays or 0,math.max(0,(a.DayCount or 0)-(a.WinningDays or 0)),0} or nil,
   Help="Profitable days divided by days with closed trades in this account. Days run from midnight to midnight UTC. Days without trades do not count."},
  {Key="Factor",Title="Profit factor",Value=complete and ratio(a.ProfitFactor,noLoss) or "—",
   Caption=not complete and unknown or noLoss and "No gross losses" or "Gross wins ÷ absolute gross losses",
   Bars=complete and {a.Gains or 0,a.Loss or 0,0} or nil,
   Details=complete and {{"Gross wins",money(a.Gains or 0)},{"Gross losses",money(-(a.Loss or 0))}} or nil,
   Help="Total profits divided by total losses from closed trades. The bar compares those two totals."},
  {Key="Best",Title="Best day share",Value=percent(best),
   Caption=not daily and "Needs complete trade dates" or net<=0 and "Needs realized profit above $0" or "Best daily net profit ÷ realized profit",
   Help="Your best day's net profit divided by this account's realized profit. Losses on other days can push this above 100%. Needs complete trade dates and realized profit above $0."},
 }
end

local function setText(root,name,value)
 local o=root:FindFirstChild(name,true)
 if o then o.Text=tostring(value)end
 return o
end
local function setBar(root,name,values,complete)
 local bar=root:FindFirstChild(name,true);if not bar then return end
 for _,v in ipairs(bar:GetChildren())do if v:IsA("Frame")then v:Destroy()end end
 local total=0;for _,v in ipairs(values)do total+=math.max(0,v)end
 if not complete or total==0 then return end
 local x=0;local names={"Win","Loss","Even"};local tops={"#29F9BA","#FF85B9","#85A8DB"};local bottoms={"#0AD59E","#F65096","#5977A6"}
 for i,v in ipairs(values)do
  if v>0 then
   local node={kind="Frame",name=name..names[i],x=x*bar.Size.X.Offset,y=0,w=v/total*bar.Size.X.Offset,h=21,top=tops[i],bottom=bottoms[i],radius=10}
   local part=build(node,bar)
   part.Position=UDim2.fromScale(x,0);part.Size=UDim2.fromScale(v/total,1)
   x+=v/total
  end
 end
end
function Kit.ApplyAggregate(root,a)
 local metrics=Kit.FromAggregate(a)
 local names={"Total","Trade","Average","Day","Factor","Best"}
 for i,m in ipairs(metrics)do
  local label=setText(root,names[i].."Value",m.Value)
  if label and i==1 then label.TextColor3=m.Color end
 end
 setText(root,"TradeCaption",string.format("%d wins / %d trades",a.Wins or 0,a.Trades or 0))
 local complete=not a.Partial and not a.CountUnknown
 if not complete then setText(root,"TradeCaption","Earlier breakdown unavailable")end
 for _,pair in ipairs({{"Average",3},{"Factor",5}})do
  local details=metrics[pair[2]].Details
  setText(root,pair[1].."Detail0",details and details[1][2]or"—")
  setText(root,pair[1].."Detail1",details and details[2][2]or"—")
 end
 setText(root,"AttemptsLabel",tostring(a.Attempts or 0).." attempts")
 setText(root,"ClosedTradesLabel",tostring(a.Trades or 0).." closed trades")
 setText(root,"CoverageCopy",not complete and "Trade breakdown incomplete.\nRatios are unavailable."
  or not a.DailyComplete and "Some trades have no dates.\nDaily stats are unavailable."
  or(a.Net or 0)<=0 and "UTC days. Best-day share needs\nrealized profit above $0."
  or "Current account only.\nTrading days use UTC.")
 setBar(root,"TradeBar",{a.Wins or 0,a.Losses or 0,a.Even or 0},complete)
 setBar(root,"AverageBar",{a.AvgWin or 0,a.AvgLoss or 0},complete)
 setBar(root,"FactorBar",{a.Gains or 0,a.Loss or 0},complete)
 return metrics
end
-- Root is the Stats viewport. Popups account for inherited scaling and stay inside it.
function Kit.BindDropdown(root,trigger,items,selectedKey,onChoose)
 local connections={}
 local opened,overlay,selected=false,nil,selectedKey
 local previousSelection
 local api={}
 local function caption()
  for _,item in ipairs(items)do if item.Key==selected then setText(trigger,trigger.Name.."Label",item.Label);return end end
 end
 function api:Close()
  opened=false
  if overlay then overlay:Destroy();overlay=nil end
  if previousSelection and previousSelection.Parent then GuiService.SelectedObject=previousSelection end
  previousSelection=nil
 end
 function api:Set(key)selected=key;caption()end
 function api:Choose(key)
  local exists=false;for _,item in ipairs(items)do if item.Key==key then exists=true end end
  if not exists then return false end
  local accepted=not onChoose or onChoose(key)~=false
  if accepted then self:Set(key)end
  self:Close();return accepted
 end
 function api:Open()
  if self:IsOpen() then self:Close();return end
  -- One menu at a time in the assembled canvas.
  local old=root:FindFirstChild("DropdownOverlay");if old then old:Destroy()end
  opened=true;previousSelection=root:FindFirstAncestorOfClass("PlayerGui")and GuiService.SelectedObject or nil
  overlay=make("TextButton","DropdownOverlay",root,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Text="",AutoButtonColor=false,ZIndex=100,Selectable=false})
  overlay.Activated:Connect(function()self:Close()end)
  local scale=root.Size.X.Offset>0 and root.AbsoluteSize.X/root.Size.X.Offset or 1
  scale=math.max(.01,scale)
  local x=(trigger.AbsolutePosition.X-root.AbsolutePosition.X)/scale
  local y=(trigger.AbsolutePosition.Y-root.AbsolutePosition.Y+trigger.AbsoluteSize.Y)/scale+8
  local w=trigger.AbsoluteSize.X/scale
  if w<1 then w=trigger.Size.X.Offset end
  w=math.min(w,math.max(1,root.Size.X.Offset-16))
  local h=math.min(#items*50+12,312,math.max(56,root.Size.Y.Offset-16))
  x=math.clamp(x,8,math.max(8,root.Size.X.Offset-w-8))
  if y+h>root.Size.Y.Offset-8 then y=math.max(8,y-h-trigger.Size.Y.Offset-16)end
  y=math.clamp(y,8,math.max(8,root.Size.Y.Offset-h-8))
  local menu=build({kind="Frame",name="DropdownMenu",x=x,y=y,w=w,h=h,top="#0A3274",bottom="#031B4E",edge="#487DDB",stroke=2,radius=12},overlay);menu.ZIndex=101
  local list=make("ScrollingFrame","Options",menu,{Position=UDim2.fromOffset(6,6),Size=UDim2.new(1,-12,1,-12),CanvasSize=UDim2.fromOffset(0,#items*50),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ZIndex=102})
  for i,item in ipairs(items)do
   local row=build({kind="TextButton",name="Option"..i,x=0,y=(i-1)*50,w=w-12,h=46,
    top=item.Key==selected and "#863AFF"or"#0A3274",bottom=item.Key==selected and"#491BCD"or"#062250",radius=8,
    text="   "..item.Label,size=18},list);row.ZIndex=103
   row:SetAttribute("Key",item.Key)
   -- A gradient on a TextButton also tints its own text. Keep the label on an un-tinted child.
   row.Text=""
   local label=build({kind="TextLabel",name="Label",x=12,y=0,w=w-36,h=46,text=item.Label,size=w<300 and 14 or 18},row)
   label.ZIndex=104;label.TextScaled=true
   make("UITextSizeConstraint","TypeSize",label,{MinTextSize=10,MaxTextSize=label.TextSize})
   row.Activated:Connect(function()self:Choose(item.Key)end)
   if item.Key==selected and UserInputService.GamepadEnabled and row:FindFirstAncestorOfClass("PlayerGui")then GuiService.SelectedObject=row end
  end
 end
 function api:IsOpen()return opened and overlay~=nil and overlay.Parent~=nil end
 function api:Get()return selected end
 function api:Destroy()self:Close();for _,c in ipairs(connections)do c:Disconnect()end end
 table.insert(connections,trigger.Activated:Connect(function()api:Open()end))
 table.insert(connections,UserInputService.InputBegan:Connect(function(input)
  if api:IsOpen() and (input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB)then api:Close()end
 end))
 caption();return api
end
return Kit