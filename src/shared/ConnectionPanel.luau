-- An actionable waiting screen, shared by the terminal and native layout verification.
local Status=require(script.Parent.ConnectionStatus)
local Panel={}
function Panel.Draw(parent,width,height,info,retry,fallback)
 local view=Status.View(info,fallback);local layout=Status.Layout(width,height)
 local area=Instance.new("ScrollingFrame");area.Name="ConnectionPanel";area.Size=UDim2.fromScale(1,1)
 area.BackgroundTransparency=1;area.BorderSizePixel=0;area.ScrollBarThickness=4
 area.ScrollingDirection=Enum.ScrollingDirection.Y;area.CanvasSize=UDim2.fromOffset(0,layout.ContentHeight);area.Parent=parent
 local function label(name,value,y,h,size,color,font)
  local t=Instance.new("TextLabel");t.Name=name;t.BackgroundTransparency=1;t.BorderSizePixel=0
  t.Position=UDim2.fromOffset(layout.X,layout.Top+y);t.Size=UDim2.fromOffset(layout.Width,h)
  t.Text=value;t.TextWrapped=true;t.TextSize=size;t.TextColor3=color;t.Font=font or Enum.Font.Gotham
  t.TextXAlignment=Enum.TextXAlignment.Center;t.TextYAlignment=Enum.TextYAlignment.Center;t.Parent=area
  return t
 end
 local white=Color3.fromRGB(245,249,255)
 local word=label("Wordmark",'Get <font color="#FFD336">Funded!</font>',0,44,width<500 and 32 or 40,white,Enum.Font.FredokaOne);word.RichText=true
 label("Status",view.Title,52,48,layout.TitleSize,white,Enum.Font.GothamBold)
 label("Exchange",view.Message,108,80,layout.MessageSize,Color3.fromRGB(0,220,255))
 label("RetryDetail",view.Detail,196,56,13,Color3.fromRGB(159,210,248))
 local b=Instance.new("TextButton");b.Name="RetryConnection";b.Position=UDim2.fromOffset(layout.X,layout.Top+264)
 b.Size=UDim2.fromOffset(layout.Width,48);b.Text=view.Button;b.TextSize=16;b.Font=Enum.Font.GothamBold;b.TextColor3=white
 b.BackgroundColor3=view.Enabled and Color3.fromRGB(92,59,205)or Color3.fromRGB(50,40,110);b.BorderSizePixel=0
 b.Active=view.Enabled;b.AutoButtonColor=view.Enabled;b.Selectable=view.Enabled;b:SetAttribute("Enabled",view.Enabled);b.Parent=area
 local corner=Instance.new("UICorner");corner.CornerRadius=UDim.new(0,12);corner.Parent=b
 b.Activated:Connect(function()if view.Enabled then retry()end end)
 return area
end
return Panel
