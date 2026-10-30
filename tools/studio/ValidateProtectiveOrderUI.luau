-- Disposable Edit-mode fixtures. No remotes, live account changes or storage writes.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="ProtectiveOrderUIValidation";shared.Parent=game.ReplicatedStorage
local H=game:GetService("HttpService")
for _,name in ipairs({"ChartView","TerminalUI"})do shared[name].Source=H:GetAsync("http://127.0.0.1:8791/src/shared/"..name..".luau")end
local gui=Instance.new("ScreenGui");gui.Name="ProtectiveOrderUIValidation";gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(shared.TerminalUI);local C=require(shared.MarketConfig);local Text=game:GetService("TextService")
 local quotes,cache={},{}
 for _,key in ipairs(C.ContractOrder)do
  quotes[key]={Last=5820,Bid=5819.75,Ask=5820.25}
  for _,tf in ipairs(C.Timeframes)do local bars={};for i=1,100 do bars[i]={Time=i*tf[2],Open=5820,Close=5821,High=5822,Low=5819,Volume=50}end;cache[key..":"..tf[1]]=bars end
 end
 local report={Passed=true,Cases=0,Labels={}}
 local function check(v,message)assert(v,message);report.Cases+=1 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1280,800}})do
  local holder=Instance.new("Frame");holder.Size=UDim2.fromOffset(size[1],size[2]);holder.Parent=gui
  ctl=UI.Mount(holder,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=6000,Step=1}})
  local chart,s=ctl.Chart,ctl.State;local session=chart.Ctx.Session
  local held={Id=123,Contract=s.Contract,Entry=5820,Stop=5810,Target=5830,Quantity=257,Direction=1,Triggered="Take profit",TargetFilled=50}
  session.Positions={[s.Contract]=held};session.AccountKey="fixture"
  local status="50 filled · 257 remaining · Waiting for liquidity at target"
  session.Orders={{Id=123,Contract=s.Contract,Quantity=257,Filled=50,Price=5830,Protection="Target",Closing=true,Kind="Take profit · closing long",Status=status},
   {Id=123,Contract=s.Contract,Quantity=257,Price=5810,Protection="Stop",Kind="Stop loss",Status="Armed"}}
  s.Levels=true;s.Coach=nil
  local state=chart.Geometry.State;state.Low=5800;state.High=5840;state.ShowLow=5800;state.ShowHigh=5840;state.AutoY=false
  chart.Dirty=true;chart:Paint(0,0,size[1],size[2],size[1]<1000,false,true);task.wait(.03)
  local found=false;local stop=false
  for _,label in ipairs(chart.Geometry.Plot:GetDescendants())do if label:IsA("TextLabel")then
   if label.Text:find("50 filled",1,true)then
    found=true;check(label.Text:find("257 left",1,true),"Missing residual quantity")
    local measured=Text:GetTextSize(label.Text,label.TextSize,label.Font,Vector2.new(2000,100))
    check(measured.X<=label.AbsoluteSize.X+1,"Partial-fill chart label clips")
    table.insert(report.Labels,{Width=size[1],Text=label.Text,TextWidth=measured.X,Available=label.AbsoluteSize.X})
   end
   if label.Parent:GetAttribute("Price")==5810 then stop=true end
  end end
  check(found and stop,"Chart must retain both partial TP status and stop")
  if size[1]<1000 then
   s.Sheet="Activity";s.Tab="Orders";chart.Ctx.refresh();task.wait(.03)
   local foundStatus=false
   for _,label in ipairs(ctl.Root:GetDescendants())do if label:IsA("TextLabel")and label.Text==status then
    foundStatus=true;check(label.TextWrapped,"Closing reason must wrap")
    check(label.TextBounds.Y<=label.AbsoluteSize.Y+1 and label.TextBounds.X<=label.AbsoluteSize.X+1,"Closing reason clips")
   end end
   check(foundStatus,"Orders sheet omitted closing reason")
  end
  check(not ctl.Root:GetAttribute("ChartError")and not ctl.Root:GetAttribute("RenderError"),"UI render error")
  ctl:Destroy();ctl=nil;holder:Destroy()
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result
