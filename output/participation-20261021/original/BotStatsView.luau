-- Roblox exposes manual text selection/copy, not an experience clipboard-write API.
local View={MaxBytes=180000}
local function make(class,name,parent,properties)
 local item=Instance.new(class);item.Name=name
 for k,v in pairs(properties)do item[k]=v end
 item.Parent=parent;return item
end
function View.Mount(parent)
 local gui=make("ScreenGui","OwnerBotStats",parent,{ResetOnSpawn=false,DisplayOrder=100,Enabled=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
 local shade=make("Frame","Backdrop",gui,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.25,Active=true})
 local panel=make("Frame","Panel",shade,{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(1,-24,1,-40),BackgroundColor3=Color3.fromRGB(5,24,57),BorderSizePixel=0})
 make("UISizeConstraint","SizeLimit",panel,{MaxSize=Vector2.new(1080,760)})
 make("UICorner","Corner",panel,{CornerRadius=UDim.new(0,14)})
 make("TextLabel","Title",panel,{Position=UDim2.fromOffset(18,12),Size=UDim2.new(1,-84,0,30),BackgroundTransparency=1,Text="Bot stats",Font=Enum.Font.GothamBold,TextSize=22,TextColor3=Color3.new(1,1,1),TextXAlignment=Enum.TextXAlignment.Left})
 local function button(name,text,position,size)
  local b=make("TextButton",name,panel,{Position=position,Size=size,BackgroundColor3=Color3.fromRGB(36,89,183),BorderSizePixel=0,Text=text,Font=Enum.Font.GothamMedium,TextSize=14,TextColor3=Color3.new(1,1,1)})
  make("UICorner","Corner",b,{CornerRadius=UDim.new(0,8)});return b
 end
 local close=button("Close","X",UDim2.new(1,-50,0,12),UDim2.fromOffset(34,30))
 make("TextLabel","Instructions",panel,{Position=UDim2.fromOffset(18,48),Size=UDim2.new(1,-36,0,56),BackgroundTransparency=1,Text="Press Ctrl+C / Cmd+C to copy the selected report.\nOn mobile, touch and hold the text, then choose Copy.",TextWrapped=true,TextSize=12,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(198,215,244),TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top})
 local scroll=make("ScrollingFrame","ReportScroll",panel,{Position=UDim2.fromOffset(18,112),Size=UDim2.new(1,-36,1,-174),BackgroundColor3=Color3.fromRGB(2,14,35),BorderSizePixel=0,ScrollBarThickness=8,CanvasSize=UDim2.fromOffset(1600,1000),ClipsDescendants=true})
 local box=make("TextBox","Report",scroll,{Position=UDim2.fromOffset(10,10),Size=UDim2.fromOffset(1580,980),BackgroundTransparency=1,
  Text="",TextEditable=false,ClearTextOnFocus=false,MultiLine=true,TextWrapped=false,RichText=false,Font=Enum.Font.Code,TextSize=14,
  TextColor3=Color3.fromRGB(220,235,255),TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top})
 local select=button("SelectAll","Select report",UDim2.new(0,18,1,-48),UDim2.fromOffset(130,32))
 make("TextLabel","Privacy",panel,{Position=UDim2.new(0,160,1,-48),Size=UDim2.new(1,-178,0,32),BackgroundTransparency=1,Text="Only visible to you",TextSize=12,Font=Enum.Font.Gotham,TextWrapped=true,TextColor3=Color3.fromRGB(165,187,219),TextXAlignment=Enum.TextXAlignment.Right})
 local controller={Gui=gui,Box=box,Scroll=scroll}
 function controller:Select()
  if not gui.Enabled then return end
  box:CaptureFocus()
  -- Focus may complete on the next task turn; byte offsets select the entire payload.
  task.defer(function()if gui.Parent and gui.Enabled then box.CursorPosition=1;box.SelectionStart=#box.Text+1 end end)
 end
 function controller:Hide()box:ReleaseFocus();gui.Enabled=false end
 function controller:Show(report)
  if type(report)~="string"or #report==0 or #report>View.MaxBytes then return false end
  box.Text=report
  local lines,longest=0,0;for line in (report.."\n"):gmatch("(.-)\n")do lines+=1;longest=math.max(longest,#line)end
  local width=math.max(1200,longest*8+24);local height=math.max(300,lines*18+24)
  box.Size=UDim2.fromOffset(width,height);scroll.CanvasSize=UDim2.fromOffset(width+20,height+20);scroll.CanvasPosition=Vector2.zero
  gui.Enabled=true;self:Select();return true
 end
 function controller:Destroy()gui:Destroy()end
 close.Activated:Connect(function()controller:Hide()end)
 select.Activated:Connect(function()controller:Select()end)
 return controller
end
return View

