-- Editable native components generated from source/components.json.
local HttpService=game:GetService("HttpService")
local UserInputService=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Spec=HttpService:JSONDecode([====[__SPEC_JSON__]====])
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
  o.Font=n.font=="body"and Enum.Font.Gotham or Enum.Font.FredokaOne
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
__FORMATTERS__
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
 setText(root,"CoverageCopy",not complete and "Earlier breakdown incomplete.\nUse dated history for full ratios."
  or not a.DailyComplete and "Some trades have no dates.\nDaily stats need dated history."
  or(a.Net or 0)<=0 and "UTC days. Best-day share needs\npositive total net profit."
  or "All six stats use the same scope.\nTrading days use UTC.")
 setBar(root,"TradeBar",{a.Wins or 0,a.Losses or 0,a.Even or 0},complete)
 setBar(root,"AverageBar",{a.AvgWin or 0,a.AvgLoss or 0},complete)
 setBar(root,"FactorBar",{a.Gains or 0,a.Loss or 0},complete)
 return metrics
end
-- Root is the fixed 1672x941 coordinate canvas. Menu positions account for UIScale.
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
  local scaler=root:FindFirstChildOfClass("UIScale");local scale=scaler and scaler.Scale or 1
  scale=math.max(.01,scale)
  local x=(trigger.AbsolutePosition.X-root.AbsolutePosition.X)/scale
  local y=(trigger.AbsolutePosition.Y-root.AbsolutePosition.Y+trigger.AbsoluteSize.Y)/scale+8
  local w=trigger.AbsoluteSize.X/scale
  if w<1 then w=trigger.Size.X.Offset end
  local h=math.min(#items*50+12,312)
  x=math.clamp(x,8,math.max(8,Spec.width-w-8))
  if y+h>Spec.height-8 then y=math.max(8,y-h-trigger.Size.Y.Offset-16)end
  local menu=build({kind="Frame",name="DropdownMenu",x=x,y=y,w=w,h=h,top="#0A3274",bottom="#031B4E",edge="#487DDB",stroke=2,radius=12},overlay);menu.ZIndex=101
  local list=make("ScrollingFrame","Options",menu,{Position=UDim2.fromOffset(6,6),Size=UDim2.new(1,-12,1,-12),CanvasSize=UDim2.fromOffset(0,#items*50),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ZIndex=102})
  for i,item in ipairs(items)do
   local row=build({kind="TextButton",name="Option"..i,x=0,y=(i-1)*50,w=w-12,h=46,
    top=item.Key==selected and "#863AFF"or"#0A3274",bottom=item.Key==selected and"#491BCD"or"#062250",radius=8,
    text="   "..item.Label,size=18},list);row.ZIndex=103
   row.Activated:Connect(function()self:Choose(item.Key)end)
   if item.Key==selected and UserInputService.GamepadEnabled and row:FindFirstAncestorOfClass("PlayerGui")then GuiService.SelectedObject=row end
  end
 end
 function api:IsOpen()return opened and overlay~=nil and overlay.Parent~=nil end
 function api:Get()return selected end
 function api:Destroy()self:Close();for _,c in ipairs(connections)do c:Disconnect()end end
 table.insert(connections,trigger.Activated:Connect(function()self:Open()end))
 table.insert(connections,UserInputService.InputBegan:Connect(function(input)
  if opened and (input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB)then api:Close()end
 end))
 caption();return api
end
function Kit.ShowHelp(root,title,body)
 local old=root:FindFirstChild("HelpOverlay");if old then old:Destroy()end
 local overlay=make("TextButton","HelpOverlay",root,{Size=UDim2.fromScale(1,1),Text="",BackgroundColor3=Color3.new(),BackgroundTransparency=.35,AutoButtonColor=false,ZIndex=110})
 local panel=build({kind="Frame",name="HelpPanel",x=566,y=310,w=540,h=285,top="#0A3274",bottom="#031B4E",edge="#487DDB",stroke=2,radius=18},overlay);panel.ZIndex=111
 local heading=build({kind="TextLabel",name="Title",x=24,y=18,w=430,h=56,text=title,size=26},panel);heading.ZIndex=112
 local copy=build({kind="TextLabel",name="Body",x=24,y=84,w=492,h=155,text=body,size=18,font="body",color="#ABC8F6"},panel);copy.ZIndex=112
 local close=build({kind="TextButton",name="Close",x=476,y=18,w=44,h=44,text="×",size=30,align="center"},panel);close.ZIndex=113
 local esc
 local function dismiss()if esc then esc:Disconnect()end;overlay:Destroy()end
 esc=UserInputService.InputBegan:Connect(function(input)if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then dismiss()end end)
 overlay.Destroying:Connect(function()if esc then esc:Disconnect()end end)
 close.Activated:Connect(dismiss);overlay.Activated:Connect(dismiss)
 return overlay
end
function Kit.Mount(parent,aggregate,options)
 options=options or {}
 local screen
 if parent:IsA("PlayerGui")then
  screen=make("ScreenGui","PolishedStatsPiecesPreview",parent,{ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
  parent=screen
 end
 local host=make("Frame","PolishedStatsHost",parent,{Size=UDim2.fromScale(1,1),BackgroundColor3=color(Spec.colors.bg),BorderSizePixel=0})
 local root=Kit.Create("Assembled",host)
 root.AnchorPoint=Vector2.new(.5,.5);root.Position=UDim2.fromScale(.5,.5)
 local scale=make("UIScale","ViewportScale",root,{Scale=1})
 local function fit()if host.AbsoluteSize.X>0 then scale.Scale=math.min(host.AbsoluteSize.X/Spec.width,host.AbsoluteSize.Y/Spec.height)end end
 local connections={host:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)}
 local a=aggregate or {};local currentScope=options.Scope or"All";local currentPeriod=options.Period or"Life"
 local scopes=options.Scopes or{{Key="All",Label="All funded accounts"},{Key="5K",Label="$5K accounts"},{Key="10K",Label="$10K accounts"},{Key="25K",Label="$25K accounts"}}
 local periods={{Key="Life",Label="Lifetime · all attempts"},{Key="Current",Label="Usable accounts"},{Key="Dated",Label="Dated history"}}
 local controller={Root=root,Host=host,ScreenGui=screen,Dropdowns={}}
 local function update()
  Kit.ApplyAggregate(root,a)
  local suffix=currentPeriod=="Life"and"Includes restarts"or currentPeriod=="Dated"and"Dated trades only"or"Usable accounts only"
  setText(root,"ScopeSummary",string.format("%d attempts · %d blown · %s",a.Attempts or 0,a.Blown or 0,suffix))
 end
 local requestId=0
 function controller:Filter(scope,period)
  if not options.OnFilter then
   setText(root,"CoverageCopy","Connect OnFilter to your stats.\nSelection was not applied.")
   return false
  end
  requestId+=1;local thisId=requestId
  local ok,nextAggregate=pcall(options.OnFilter,scope,period)
  if thisId~=requestId or not root.Parent then return false end
  if not ok or type(nextAggregate)~="table"then
   setText(root,"CoverageCopy","Stats could not be loaded.\nYour previous scope is still shown.")
   return false
  end
  a=nextAggregate;currentScope=scope;currentPeriod=period
  self.Dropdowns.Funded:Set(scope);self.Dropdowns.Scope:Set(period);update()
  return true
 end
 controller.Dropdowns.Funded=Kit.BindDropdown(root,root:FindFirstChild("FundedDropdown",true),scopes,currentScope,function(key)return controller:Filter(key,currentPeriod)end)
 controller.Dropdowns.Scope=Kit.BindDropdown(root,root:FindFirstChild("ScopeDropdown",true),periods,currentPeriod,function(key)return controller:Filter(currentScope,key)end)
 table.insert(connections,root:FindFirstChild("DatedButton",true).Activated:Connect(function()controller:Filter(currentScope,"Dated")end))
 local helpDescriptions={Total="Total P&L",Trade="Trade win rate",Average="Avg win / avg loss",Factor="Profit factor"}
 for key in pairs(helpDescriptions)do
  local b=root:FindFirstChild(key.."Help",true)
  table.insert(connections,b.Activated:Connect(function()
   local metrics=Kit.FromAggregate(a)
   for _,metric in ipairs(metrics)do
    if metric.Key==key then
     if options.OnHelp then options.OnHelp(metric.Title,metric.Help)
     else Kit.ShowHelp(root,metric.Title,metric.Help)end
    end
   end
  end))
 end
 table.insert(connections,root:FindFirstChild("DailyHelp",true).Activated:Connect(function()
  Kit.ShowHelp(root,"Daily stats","Day win rate compares profitable UTC days with all trading days. Best-day share compares the highest daily net profit with total net profit. Missing dates make daily metrics unavailable; best-day share also requires positive total net profit.")
 end))
 if options.OnAccountPicker then table.insert(connections,root:FindFirstChild("AccountPicker",true).Activated:Connect(options.OnAccountPicker))end
 for _,name in ipairs({"Trade","Accounts","Shop","Stats","Leaderboard","Positions","Review","Learn"})do
  local b=root:FindFirstChild("Nav"..name,true)
  if options.OnNavigate then table.insert(connections,b.Activated:Connect(function()options.OnNavigate(name)end))end
 end
 function controller:Update(nextAggregate,nextOptions)
  requestId+=1
  a=nextAggregate or a
  if nextOptions then
   currentScope=nextOptions.Scope or currentScope;currentPeriod=nextOptions.Period or currentPeriod
  end
  self.Dropdowns.Funded:Set(currentScope);self.Dropdowns.Scope:Set(currentPeriod);update()
 end
 function controller:Destroy()
  requestId+=1
  for _,d in pairs(self.Dropdowns)do d:Destroy()end
  for _,c in ipairs(connections)do c:Disconnect()end
  if screen then screen:Destroy()else host:Destroy()end
 end
 update();fit();return controller
end
return Kit
