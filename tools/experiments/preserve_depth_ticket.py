from pathlib import Path
p=Path(__file__).resolve().parents[2]/'src/shared/TerminalUI.luau'
s=p.read_text(encoding='utf-8')
s=s.replace(' local fullRefreshPending=false\n local function refresh()\n  if dirty or not alive then return end',' local fullRefreshPending=false\n local requestedPreserve=false\n local preservedTicket\n local function refresh(keepTicket)\n  if dirty then if not keepTicket then requestedPreserve=false end;return end\n  if not alive then return end')
s=s.replace('  dirty=true;task.defer(function()dirty=false;if alive and root.Parent then render()end end)','  requestedPreserve=keepTicket==true\n  dirty=true;task.defer(function()dirty=false;local keep=requestedPreserve;requestedPreserve=false;if alive and root.Parent then render(keep)end end)')
start=s.index('  if held then\n   local closeW=',s.index(' local function ticket('))
end=s.index('\n  yy+=40',start)
block=s[start:end]
block=block.replace('  if held then','  if held then',1)
helper=''' local function updateTicketPosition(p,w)
  local actionParent=p.OrderActions;local iw=w-32;local yy=68
  for _,name in ipairs({"Position","Pnl","ClosePosition"})do local old=actionParent:FindFirstChild(name);if old then old:Destroy()end end
  local held=session.Positions[s.Contract]
'''+block+'''
 end
 local function retainedQuantity(p)
  local quantity=p:FindFirstChild("Quantity",true)
  if quantity and not quantity.Value:IsFocused()then quantity.Value.Text=tostring(s.Qty)end
 end
'''
s=s[:start]+'  updateTicketPosition(p,w)'+s[end:]
start=s.index(' local function ticket(')
s=s[:start]+helper+s[start:]
s=s.replace(' local function ticket(x,y,w,h)\n',''' local function ticket(x,y,w,h)
  if preservedTicket and preservedTicket.Name=="OrderTicket"then
   updateTicketPosition(preservedTicket,w);retainedQuantity(preservedTicket);return
  end
''')
s=s.replace('  local held=session.Positions[s.Contract];local iw=w-32\n  gameHeading','  p:SetAttribute("TradingEnabled",options.Preview or session.CanTrade)\n  local held=session.Positions[s.Contract];local iw=w-32\n  gameHeading',1)
s=s.replace(' local function mobileDock(x,y,w,h,compact)\n',''' local function mobileDock(x,y,w,h,compact)
  if preservedTicket and preservedTicket.Name=="TradeDock"then retainedQuantity(preservedTicket);return end
''')
s=s.replace('  gameHeading(text(shell,"Title","Place a trade"','  shell:SetAttribute("TradingEnabled",options.Preview or session.CanTrade)\n  gameHeading(text(shell,"Title","Place a trade"',1)
s=s.replace(' local function renderNow()',' local function renderNow(keepTicket)')
old='  local size=root.AbsoluteSize;local w=size.X>0 and size.X or 1440;local h=size.Y>0 and size.Y or 900;lastW=w;lastH=h'
new='''  local size=root.AbsoluteSize;local w=size.X>0 and size.X or 1440;local h=size.Y>0 and size.Y or 900
  preservedTicket=nil
  if keepTicket and w==lastW and h==lastH and currentScreen()=="Trade"and root:GetAttribute("Screen")=="Trade"and root:GetAttribute("SelectedContract")==s.Contract then
   local panel=canvas:FindFirstChild("OrderTicket")or canvas:FindFirstChild("TradeDock")
   if panel and panel:GetAttribute("TradingEnabled")== (options.Preview or session.CanTrade)then preservedTicket=panel end
  end
  lastW=w;lastH=h'''
assert old in s;s=s.replace(old,new)
old='  for _,view in ipairs(depthViews)do view:Destroy()end;table.clear(depthViews)\n  canvas:ClearAllChildren();canvas.Size=UDim2.fromOffset(w,h)'
new='''  for i=#depthViews,1,-1 do local view=depthViews[i]
   if not preservedTicket or not view.Root:IsDescendantOf(preservedTicket)then view:Destroy();table.remove(depthViews,i)end
  end
  for _,child in ipairs(canvas:GetChildren())do if child~=preservedTicket then child:Destroy()end end
  canvas.Size=UDim2.fromOffset(w,h)'''
assert old in s;s=s.replace(old,new)
s=s.replace(' render=function()\n  local ok,err=xpcall(renderNow,debug.traceback)',' render=function(keepTicket)\n  local ok,err=xpcall(function()renderNow(keepTicket)end,debug.traceback)')
s=s.replace('then lastStructure=signature;refresh();return end','then lastStructure=signature;refresh(true);return end')
p.write_text(s,encoding='utf-8');print('Trade fields, L2 rows and Buy/Sell survive market-driven structural updates.')
