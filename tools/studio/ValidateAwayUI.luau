-- Isolated Edit-mode fixtures. Real TerminalUI/AwayView; all acknowledgement calls are captured.
return function(preview)
 local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="AwayUIQA";shared.Parent=game.ReplicatedStorage
 local gui=Instance.new("ScreenGui");gui.Name="AwayUIQA";gui.DisplayOrder=100;gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
 local ctl
 local ok,result=xpcall(function()
  local config=require(shared.MarketConfig)
  local candles={};for i=1,120 do local o=5820+math.sin(i*.2)*8;candles[i]={Time=i*60,Open=o,High=o+2,Low=o-2,Close=o+1,Volume=50}end
  local quotes,cache={},{};for _,key in ipairs(config.ContractOrder)do
   quotes[key]={Last=5820,Open=5820,Bid=5819.75,Ask=5820.25}
   for _,tf in ipairs(config.Timeframes)do cache[key..":"..tf[1]]=candles end
  end
  local summary={Id="away-qa",Seconds=8040,Total=287.5,RealizedChange=225,UnrealizedChange=62.5,Realized=275,Unrealized=162.5,CarriedIn=50,
   Coverage="Exits use actual exchange trades while the server runs. The market pauses when no server is running.",
   Rows={
    {Contract="BX",Direction=1,Quantity=2,Remaining=0,RealizedChange=225,UnrealizedChange=0,Exits={{Reason="Take profit",Quantity=2,Notional=11640,Change=225,Realized=275}}},
    {Contract="BT",Direction=-1,Quantity=1,Remaining=1,RealizedChange=0,UnrealizedChange=75,Exits={}},
    {Contract="BG",Direction=1,Quantity=1,Remaining=1,RealizedChange=0,UnrealizedChange=-12.5,Exits={}},
   }}
  local pf={Active="qa",Started=true,Tutorial="Done",RankId="Rookie",Rank="Market Rookie",RankBadge=1,RankLevel=1,StartingBalance=10000,StartingBonus=0,
   Earned=0,Trades=0,Wins=0,Titles={},Milestones={},Ranks={},Accounts={},AwaySummary=summary}
  local callbacks={}
  local away=require(shared.AwayView);local draw=away.Draw
  away.Draw=function(ctx,...)
   local button=ctx.button
   ctx.button=function(parent,name,value,x,y,w,h,fn,...)
    local b=button(parent,name,value,x,y,w,h,fn,...);callbacks[b]=fn;return b
   end
   return draw(ctx,...)
  end
  local holder=Instance.new("Frame");holder.Name="Phone";holder.Size=UDim2.fromOffset(390,844);holder.Position=UDim2.new(.5,-195,.5,-422);holder.Parent=gui
  ctl=require(shared.TerminalUI).Mount(holder,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=7200,Step=1},PortfolioData=pf})
  local requests={};local allowAck=true
  ctl.Chart.Ctx.Session.AcknowledgeAway=function(_,id)table.insert(requests,id);return allowAck,"Fixture acknowledgement"end
  local report={Passed=true,Checks=0,Layouts={},Issues={}}
  local function check(v,message)assert(v,message);report.Checks+=1 end
  local function refresh(width,height)
   if width then holder.Size=UDim2.fromOffset(width,height);holder.Position=UDim2.new(.5,-width/2,.5,-height/2)end
   ctl.Chart.Ctx.refresh();task.wait(.08)
   check(not ctl.Root:GetAttribute("RenderError"),"No render errors")
   return ctl.Root.Canvas:FindFirstChild("AwayDialog")
  end
  local function visible(o,root)
   while o~=root do if o:IsA("GuiObject")and not o.Visible then return false end;o=o.Parent end
   return true
  end
  local function audit(panel,width,height)
   check(panel~=nil,"Away panel exists")
   check(panel.Position.X.Offset>=0 and panel.Position.Y.Offset>=0 and panel.Position.X.Offset+panel.Size.X.Offset<=width+1 and panel.Position.Y.Offset+panel.Size.Y.Offset<=height+1,"Panel stays inside viewport")
   check(panel.Continue.Size.Y.Offset>=44,"Continue has a 44px touch target")
   check(panel.Continue.Position.Y.Offset+panel.Continue.Size.Y.Offset<=panel.Size.Y.Offset,"Continue stays visible")
   check(panel.Results.Position.Y.Offset+panel.Results.Size.Y.Offset<panel.Continue.Position.Y.Offset,"Scrolling content cannot overlap Continue")
   for _,o in ipairs(panel:GetDescendants())do
    if o:IsA("TextLabel")and visible(o,panel)and not o.TextFits then table.insert(report.Issues,width.."x"..height.." "..o.Name.." overflow: "..o.Text)end
   end
   check(not panel:FindFirstChild("ToggleDetails",true),"No disclosure button is required")
   check(not panel:FindFirstChild("Booked",true) and not panel:FindFirstChild("Coverage",true),"Accounting and coverage footnotes are removed")
   check(panel.Results.TradesHeading.Text=="Trades" and panel.Results.TradeDetails.Visible,"Trades are always shown")
   local first=panel.Results.TradeDetails:FindFirstChild("Trade1")or panel.Results.TradeDetails:FindFirstChild("Empty")
   check(first and panel.Results.TradeDetails.Position.Y.Offset+first.Position.Y.Offset+first.Size.Y.Offset<=panel.Results.Size.Y.Offset,"First trade is visible immediately at "..width.."x"..height)
   table.insert(report.Layouts,{Width=width,Height=height})
  end
  if not preview then
   for _,size in ipairs({{320,568},{390,844},{650,360},{844,390},{1280,800},{1920,1080}})do
    local panel=refresh(size[1],size[2]);audit(panel,size[1],size[2])
    check(panel.Results.Total.Text=="+$437.50","Full trade P&L includes gains carried in before departure")
    check(panel.Results.NetChange.Text=="Total P&L" and panel.Results.SinceLeft.Text=="At your return","Labels describe full P&L at return")
    check(not panel.Results:FindFirstChild("RealizedChange") and not panel.Results:FindFirstChild("UnrealizedChange"),"No separate P&L breakdown")
    check(panel.Results.TradeDetails.Exit1_1.Text=="Take profit · 2 closed","Exit details retain status without extra amounts")
    check(panel.Results.TradeDetails.Exit1_1.Text:find("Take profit",1,true)~=nil,"Trades retain actual exit details")
    check(#requests==0,"Showing trades never acknowledges the summary")
    panel=refresh();check(panel.Results.TradeDetails.Visible,"Trades remain visible after a full refresh")
   end
   for _,value in ipairs({-275,0,123456789.25})do
    summary.Total=value;summary.RealizedChange=value;summary.UnrealizedChange=0;summary.Realized=value;summary.Unrealized=0
    local panel=refresh(320,568);audit(panel,320,568)
    check(panel.Results.Total.Text==require(shared.MarketClient).Signed(value),"Loss, zero, and large values stay live")
    check(value~=0 or panel.Results.Total.TextColor3==Color3.fromRGB(159,210,248),"Zero uses neutral color")
   end
   summary.Total=0;summary.Realized=0;summary.RealizedChange=0;summary.UnrealizedChange=0
   for _,value in ipairs({800,-800,0})do
    summary.Unrealized=value
    local panel=refresh(320,568)
    check(panel.Results.Total.Text==require(shared.MarketClient).Signed(value),"Paused market displays full open P&L: "..value)
   end
   summary.Unrealized=800
   summary.Rows={summary.Rows[1]};summary.Seconds=183840
   local panel=refresh()
   check(panel:GetAttribute("TradeCount")==1 and panel.TimeAway.Text=="Away for 2d 3h","Single trade and long absence")
   summary.Id="new-absence";panel=refresh()
   check(panel.Results.TradeDetails.Visible,"New absence trades are immediately shown")
   summary.Rows={};panel=refresh()
   check(panel.Results.TradeDetails.Empty~=nil,"Empty trade state is immediately shown")
   allowAck=false;callbacks[panel.Continue]();panel=refresh()
   check(panel~=nil and #requests==1,"Rejected acknowledgement preserves the summary")
   allowAck=true;callbacks[panel.Continue]();task.wait(.08)
   check(not ctl.Root.Canvas:FindFirstChild("AwayDialog") and #requests==2 and requests[2]=="new-absence","Continue acknowledges exactly the displayed summary")
   check(#report.Issues==0,table.concat(report.Issues,"\n"))
   return report
  end
  local hook=Instance.new("BindableFunction");hook.Name="Diagnostics";hook.Parent=gui
  hook.OnInvoke=function(command,a,b)
   if command=="Resize"then refresh(a,b);return true
   elseif command=="State"then local p=ctl.Root.Canvas.AwayDialog;return{TradesVisible=p.Results.TradeDetails.Visible,Width=p.Size.X.Offset,Height=p.Size.Y.Offset}
   elseif command=="Cleanup"then ctl:Destroy();shared:Destroy();gui:Destroy();return true end
  end
  refresh(390,844)
  return {Preview=true,Diagnostics=hook:GetFullName()}
 end,debug.traceback)
 if not ok or not preview then if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()end
 if not ok then error(result)end
 return result
end
