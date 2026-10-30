-- Run in Studio Edit mode. Fixtures never connect to orders, accounts or persistence.
assert(not game:GetService("RunService"):IsRunning(),"Run in Edit mode")
local H=game:GetService("HttpService")
local previous=_G.MarketAlertPreview
if previous then previous.Controller:Destroy();previous.Gui:Destroy();previous.Shared:Destroy();_G.MarketAlertPreview=nil end
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="MarketAlertValidation";shared.Parent=game.ReplicatedStorage
local bundle=H:JSONDecode(H:GetAsync("http://127.0.0.1:8811/bundle"))
for path,item in pairs(bundle)do
 if path:find("^ReplicatedStorage")then
  local name=path:match("[^.]+$");local m=shared:FindFirstChild(name)or Instance.new("ModuleScript")
  m.Name=name;m.Source=item.Source;m.Parent=shared
 end
end
local gui=Instance.new("ScreenGui");gui.Name="MarketAlertPreview";gui.IgnoreGuiInset=true;gui.DisplayOrder=100;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling;gui.Parent=game.StarterGui
local holder=Instance.new("Frame");holder.BackgroundTransparency=1;holder.Parent=gui
local report={Checks=0,Issues={},Layouts={}}
local function check(ok,message)report.Checks+=1;if not ok then table.insert(report.Issues,message)end end
local ctl
local ok,err=xpcall(function()
 local UI=require(shared.TerminalUI);local C=require(shared.MarketConfig)
 local data={Quotes={},CandlesBySeries={},Time=6000,Step=1}
 for _,key in ipairs(C.ContractOrder)do
  local price=C.Contracts[key].Last;data.Quotes[key]={Last=price,Open=price,Bid=price,Ask=price}
  for _,tf in ipairs(C.Timeframes)do
   local bars={};for i=1,100 do local p=price+math.sin(i*.3)*price*.0005;bars[i]={Time=i*tf[2],Open=p,Close=p+price*.00005,High=p+price*.0001,Low=p-price*.0001,Volume=50}end
   data.CandlesBySeries[key..":"..tf[1]]=bars
  end
 end
 for _,size in ipairs({{320,568},{390,844},{568,320},{844,390},{1280,720},{1920,1080}})do
  holder.Size=UDim2.fromOffset(size[1],size[2]);ctl=UI.Mount(holder,{Preview=true,PreviewData=data});task.wait(.12)
  local plot=ctl.Root.Canvas.Chart.CandlestickPlot;local b=ctl.MarketBanner
  for _,direction in ipairs({1,-1})do
   local now=os.clock();local event={Id=size[1]..":"..direction,Direction=direction,ExpiresAt=6020}
   check(b:Update(event,6000,true,now),"New event rejected")
   b:Step(plot,true,false,now+.5);task.wait(.03)
   local name=size[1].."x"..size[2].." "..direction
   check(not ctl.Root:GetAttribute("RenderError"),name..": render failure")
   check(b.Group.Visible,name..": banner hidden")
   check(b.Title.Text==(direction==1 and"MARKET SURGE"or"MARKET SELLOFF"),name..": incorrect direction")
   check(b.Group.AbsolutePosition.X>=0 and b.Group.AbsolutePosition.X+b.Group.AbsoluteSize.X<=size[1]+1,name..": outside viewport horizontally")
   check(b.Group.AbsolutePosition.Y>=plot.AbsolutePosition.Y and b.Group.AbsolutePosition.Y+b.Group.AbsoluteSize.Y<=plot.AbsolutePosition.Y+plot.AbsoluteSize.Y+1,name..": outside plot vertically")
   for _,o in ipairs(b.Group:GetDescendants())do
    if o:IsA("GuiObject")then check(not o.Active and not o:IsA("GuiButton"),name..": captures input "..o.Name)end
    if o:IsA("TextLabel")and o.Visible then check(o.TextFits,name..": clipped text "..o.Name)end
   end
   local start=b.StartedAt;local count=b.Count
   for _=1,20 do b:Update(event,6001,true,now+1)end
   check(b.StartedAt==start and b.Count==count,name..": repeated packets replay banner")
   b:Step(plot,true,true,now+1)
   local calmPos=b.Group.Position;local candlePos=b.Bars[1].Body.Position
   b:Step(plot,true,true,now+2)
   check(b.Group.Position==calmPos and b.Bars[1].Body.Position==candlePos and not b.Sweeps[1].Visible,name..": reduced motion animates")
   b:Step(plot,true,false,now+4.1);check(not b.Group.Visible,name..": notice does not expire")
   check(not b:Update(event,6001,true,now+4.2),name..": expired banner replays from same event")
   check(b:Update({Id=event.Id.."next",Direction=direction,ExpiresAt=6040},6020,true,now+5),name..": consecutive same-direction news is lost")
   b:Step(plot,false,false,now+5.5);check(not b.Group.Visible and not b.StartedAt,name..": dialog does not clear notice")
   local hidden={Id=event.Id.."hidden",Direction=direction,ExpiresAt=6050}
   check(not b:Update(hidden,6030,false,now+6),name..": hidden news announced")
   check(not b:Update(hidden,6031,true,now+7),name..": hidden news replays after dialog")
   check(not b:Update({Id=event.Id.."old",Direction=direction,ExpiresAt=6000},6001,true,now+8),name..": stale news announced")
   table.insert(report.Layouts,{Width=size[1],Height=size[2],Direction=direction,BannerWidth=b.Width,BannerHeight=b.Height})
  end
  ctl:Destroy();ctl=nil;task.wait()
 end
 holder.Size=UDim2.fromOffset(1280,720);ctl=UI.Mount(holder,{Preview=true,PreviewData=data});task.wait(.12)
 ctl.MarketBanner:Update({Id="visual",Direction=1,ExpiresAt=6020},6000,true)
 ctl.MarketBanner:Step(ctl.Root.Canvas.Chart.CandlestickPlot,true,false,os.clock()+.5)
 _G.MarketAlertPreview={Controller=ctl,Gui=gui,Shared=shared,Holder=holder}
end,debug.traceback)
report.Ok=ok and #report.Issues==0;report.Error=err
H:PostAsync("http://127.0.0.1:8811/validation.json",H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
if not ok then if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()end
return H:JSONEncode(report)
