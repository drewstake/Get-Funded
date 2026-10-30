-- Isolated Edit-mode layout audit; no trading, remotes or saved-account access.
assert(not game:GetService("RunService"):IsRunning(),"Run in Edit mode")
local H=game:GetService("HttpService")
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="HelpRedesignValidation";shared.Parent=game.ReplicatedStorage
shared.TerminalUI.Source=H:GetAsync("http://127.0.0.1:8803/source")
local gui=Instance.new("ScreenGui");gui.Name="HelpRedesignPreview";gui.IgnoreGuiInset=true;gui.DisplayOrder=100;gui.Parent=game.StarterGui
local ctl
local report={Layouts={},Issues={},Checks=0,StorageAccessed=false}
local function check(ok,message)
 report.Checks+=1
 if not ok then table.insert(report.Issues,message)end
end
local ok,err=xpcall(function()
 local UI=require(shared.TerminalUI);local C=require(shared.MarketConfig)
 local data={Quotes={},CandlesBySeries={},Time=6000,Step=1}
 for _,key in ipairs(C.ContractOrder)do
  local price=C.Contracts[key].Last
  data.Quotes[key]={Last=price,Open=price,Bid=price,Ask=price}
  for _,tf in ipairs(C.Timeframes)do
   local bars={};for i=1,100 do bars[i]={Time=i*tf[2],Open=price,Close=price,High=price+1,Low=price-1,Volume=50}end
   data.CandlesBySeries[key..":"..tf[1]]=bars
  end
 end
 local holder=Instance.new("Frame");holder.BackgroundTransparency=1;holder.Parent=gui
 for _,size in ipairs({{320,568},{390,844},{568,320},{844,390},{1000,600},{1280,720},{1920,1080}})do
  holder.Size=UDim2.fromOffset(size[1],size[2])
  ctl=UI.Mount(holder,{Preview=true,PreviewData=data});task.wait(.1)
  local s=ctl.State
  local summary=ctl.Root.Canvas.AccountSummary
  for _,name in ipairs({"BalanceCard","UnrealizedCard"})do
   check(summary[name]:IsA("Frame")and not summary[name].Active,"Summary still interactive: "..name)
   check(summary[name]:FindFirstChild(name=="BalanceCard"and"BalanceValue"or"UnrealizedValue")~=nil,"Missing live value: "..name)
  end
  check(summary.ObjectiveCard:IsA("GuiButton"),"Next goal must remain interactive")
  for _,mode in ipairs({"Help","Expanded","Info"})do
   s.Overlay=mode=="Info"and"Info"or"Help";s.HelpDetails=mode=="Expanded"
   s.Info="A stop loss helps limit losses. Fills can differ from the trigger price."
   ctl.Chart.Ctx.refresh();task.wait(.1)
   local label=size[1].."x"..size[2].." "..mode
   local dialog=ctl.Root.Canvas:FindFirstChild("Dialog")
   check(dialog~=nil,label..": missing dialog")
   check(not ctl.Root:GetAttribute("RenderError"),label..": render error")
   if dialog then
    check(dialog.AbsoluteSize.X<=size[1]and dialog.AbsoluteSize.Y<=size[2],label..": dialog exceeds viewport")
    local content=dialog.Content
    check(content.AbsoluteSize.Y>0,label..": no scroll viewport")
    for _,o in ipairs(dialog:GetDescendants())do
     if o:IsA("TextLabel")and o.Text~=""and not o.TextScaled then
      check(o.TextFits,label..": clipped text "..o:GetFullName().." ("..o.Text..")")
     end
    end
    if mode~="Info"then
     local action=dialog.GuideAction.ReplayTutorial
     check(not action:IsDescendantOf(content),label..": guided trade scrolls away")
     check(action.AbsolutePosition.Y>=dialog.AbsolutePosition.Y and action.AbsolutePosition.Y+action.AbsoluteSize.Y<=dialog.AbsolutePosition.Y+dialog.AbsoluteSize.Y,label..": guided trade outside dialog")
     check(content.AbsolutePosition.Y+content.AbsoluteSize.Y<=action.AbsolutePosition.Y,label..": content overlaps action")
     check(content.Step1.Body.TextSize>=18,label..": body too small")
     check((content:FindFirstChild("Detail1")~=nil)==s.HelpDetails,label..": details visibility")
     content.CanvasPosition=Vector2.new(0,content.CanvasSize.Y.Offset);task.wait(.03)
     local last=s.HelpDetails and content.Detail2 or content.HelpDetails
     check(last.AbsolutePosition.Y+last.AbsoluteSize.Y<=content.AbsolutePosition.Y+content.AbsoluteSize.Y+1,label..": last item cannot scroll into view")
    end
    table.insert(report.Layouts,{Width=size[1],Height=size[2],Mode=mode,ScrollHeight=content.CanvasSize.Y.Offset})
   end
  end
  ctl:Destroy();ctl=nil
 end
 holder.Size=UDim2.fromOffset(1280,720)
 ctl=UI.Mount(holder,{Preview=true,PreviewData=data});ctl.State.Overlay="Help";ctl.Chart.Ctx.refresh();task.wait(.1)
 _G.HelpRedesignPreview={Controller=ctl,Holder=holder,Gui=gui,Shared=shared}
end,debug.traceback)
report.Ok=ok and #report.Issues==0;report.Error=err
H:PostAsync("http://127.0.0.1:8803/results",H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
if not ok then if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy();error(err)end
return report
