-- Edit-mode layout fixture for the phone "Arcade Clean" Trade screen. Disposable: builds private
-- in-memory engines (no remotes, DataStores or player profiles) and mounts Preview workspaces in
-- fixed-size host frames under StarterGui (delete MobileArcadeQA before saving), so several device sizes can be inspected side by side.
-- Usage (Edit context): loadstring(source)()(CASES) with CASES={{Name,W,H,Position(-1/0/1),Screen,StateOverrides}}
return function(CASES,keep)
 local core=game:GetService("StarterGui") -- CoreGui is not included in Studio screen captures
 local old=core:FindFirstChild("MobileArcadeQA");if old then old:Destroy()end
 if CASES=="clear"then return "cleared"end
 local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="MAQAShared";shared.Parent=game.ReplicatedStorage
 local server=game.ServerScriptService.MarketReign:Clone();server.Name="MAQAServer";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
 for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do
  if m:IsA("LuaSourceContainer")then
   m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.MAQAShared"):gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.MAQAServer")
  end
 end end
 local gui=Instance.new("ScreenGui");gui.Name="MobileArcadeQA";gui.IgnoreGuiInset=true;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.DisplayOrder=50
 local backdrop=Instance.new("Frame");backdrop.Name="Backdrop";backdrop.Size=UDim2.fromScale(1,1);backdrop.BackgroundColor3=Color3.fromRGB(24,24,28);backdrop.BorderSizePixel=0;backdrop.Parent=gui
 local results={}
 local ok,err=pcall(function()
  local Config=require(shared.MarketConfig)
  local Engine=require(server.MarketEngine)
  local Participants=require(server.Participants)
  local T=require(server.TestLiquidity)
  local UI=require(shared.TerminalUI)
  local x=10
  for _,case in ipairs(CASES)do
   local name,w,h,position,screen=case[1],case[2],case[3],case[4],case[5]
   local engine=Engine.new(Config,73521);local population=Participants.new(engine)
   for _=1,math.floor(Config.WarmupSeconds/Config.StepSeconds)do population:Step()end
   local funded=require(server.FundedAccounts).new(engine,require(shared.ProgressionConfig),Config)
   funded:Start("preview");funded:Flag("preview","TutorialDone")
   local owner=funded:Owner("preview")
   if position~=0 then
    assert(T.Submit(engine,owner,{Contract="BX",Type="Market",Direction=position,Quantity=2}))
    for _=1,60 do population:Step()end
   end
   local snapshot=engine:Snapshot(owner,"BX","1m",true)
   snapshot.CandlesBySeries={}
   for _,key in ipairs(Config.ContractOrder)do for _,tf in ipairs(Config.Timeframes)do snapshot.CandlesBySeries[key..":"..tf[1]]=engine:Snapshot(owner,key,tf[1],true).Candles end end
   local label=Instance.new("TextLabel");label.Text=name;label.Size=UDim2.fromOffset(w,18);label.Position=UDim2.fromOffset(x,4);label.BackgroundTransparency=1
   label.TextColor3=Color3.new(1,1,1);label.Font=Enum.Font.GothamBold;label.TextSize=14;label.Parent=gui
   local host=Instance.new("Frame");host.Name=name;host.Size=UDim2.fromOffset(w,h);host.Position=UDim2.fromOffset(x,24);host.BackgroundTransparency=1;host.Parent=gui
   gui.Parent=core
   local state=case[6]or{}
   local controller=UI.Mount(host,{Preview=true,PreviewData=snapshot,PortfolioData=funded:View("preview")})
   -- Preview sessions ignore account data; copy the fixture engine's positions/summary in.
   local sess=controller.Chart.Ctx.Session
   if next(snapshot.Positions or{})then sess.Positions=snapshot.Positions;if snapshot.Summary then sess.SummaryData=snapshot.Summary end end
   if state.Orders then sess.Orders=state.Orders end
   for k,v in pairs(state)do if k~="Orders"then controller.State[k]=v end end
   if screen and screen~="Trade"then controller.State.Screen=screen;controller.State.Nav=screen end
   -- Preview workspaces have no diagnostics hook; a one-pixel resize forces a rebuild from State.
   host.Size=UDim2.fromOffset(w,h+5);task.wait();task.wait();host.Size=UDim2.fromOffset(w,h);task.wait()
   results[name]={Controller=controller,Host=host}
   x+=w+16
  end
 end)
 task.wait(0.4)
 local out={}
 for name,r in pairs(results)do
  local root=r.Controller.Root
  local function rect(path)
   local node=root.Canvas;for part in path:gmatch("[^%.]+")do node=node and node:FindFirstChild(part)end
   if not node then return nil end
   return string.format("%d,%d %dx%d",node.AbsolutePosition.X-root.AbsolutePosition.X,node.AbsolutePosition.Y-root.AbsolutePosition.Y,node.AbsoluteSize.X,node.AbsoluteSize.Y)
  end
  -- Audit: text that does not fit, visible objects outside the workspace, undersized buttons.
  local overflow,outside,small={}, {}, {}
  local rp,rs=root.AbsolutePosition,root.AbsoluteSize
  for _,o in ipairs(root:GetDescendants())do
   if o:IsA("GuiObject")and o.Visible and o.AbsoluteSize.X>0 then
    local hidden=false;local a=o.Parent
    while a and a~=root do if a:IsA("GuiObject")and not a.Visible then hidden=true break end;a=a.Parent end
    if not hidden then
     if (o:IsA("TextLabel")or o:IsA("TextButton")or o:IsA("TextBox"))and o.Text~=""and o.TextTransparency<1 and not o.TextFits then table.insert(overflow,(o:GetFullName():gsub("^.-Canvas%.","")).." ["..o.Text.."]")end
     local p,s=o.AbsolutePosition,o.AbsoluteSize
     if (p.X<rp.X-1 or p.Y<rp.Y-1 or p.X+s.X>rp.X+rs.X+1 or p.Y+s.Y>rp.Y+rs.Y+1)and not o:FindFirstAncestorWhichIsA("ScrollingFrame")then table.insert(outside,(o:GetFullName():gsub("^.-Canvas%.","")))end
     if o:IsA("GuiButton")and o.Active and(s.X<40 or s.Y<32)and not o:FindFirstAncestor("CandlestickPlot")then table.insert(small,o.Name.." "..s.X.."x"..s.Y)end
    end
   end
  end
  out[name]={Root=tostring(root.AbsoluteSize),Layout=root:GetAttribute("Layout"),Screen=root:GetAttribute("Screen"),RenderError=root:GetAttribute("RenderError"),ChartError=root:GetAttribute("ChartError"),
   Header=rect("TopNavigation"),Strip=rect("AccountSummary"),Chart=rect("Chart"),Plot=rect("Chart.CandlestickPlot"),Dock=rect("TradeDock"),Buy=rect("TradeDock.BuyLong"),Sell=rect("TradeDock.SellShort"),
   Qty=rect("TradeDock.QuantityCard.Quantity")or rect("TradeDock.Fields.Quantity"),Risk=rect("TradeDock.RiskControls")or rect("TradeDock.Fields.RiskControls"),
   Position=rect("TradeDock.PositionBar")or rect("TradeDock.Fields.PositionBar"),Nav=rect("MobileNavigation"),Candles=root:GetAttribute("VisibleCandles"),
   PriceLabels=#(function()local t={}for _,o in ipairs(root.Canvas:FindFirstChild("Chart")and root.Canvas.Chart.CandlestickPlot:GetChildren()or{})do if o.Name=="PriceAxis"then table.insert(t,o)end end return t end)(),
   Overflow=overflow,Outside=outside,SmallButtons=small}
 end
 shared:Destroy();server:Destroy()
 if not ok then error(err)end
 return game:GetService("HttpService"):JSONEncode(out)
end
