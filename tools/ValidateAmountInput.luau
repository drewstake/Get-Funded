-- Disposable Edit-mode UI: invoke the real commit path without remotes or profile writes.
local shared=game.ReplicatedStorage.MarketReign:Clone()
shared.Name="AmountInputUIValidationModules";shared.Parent=game.ReplicatedStorage
local module=shared.TerminalUI:Clone();module.Name="AmountInputUITest"
module.Source=module.Source:gsub("field%.FocusLost:Connect%(function%(%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestCommit";hook.OnInvoke=commit;hook.Parent=field;field.FocusLost:Connect(function()'
end):gsub("b%.Activated:Connect%(function%(%.%.%.%)",function()
 return 'local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)'
end)
module.Parent=shared
local gui=Instance.new("ScreenGui");gui.Name="AmountInputUIValidation";gui.IgnoreGuiInset=true;gui.Parent=game.StarterGui
local ctl
local ok,result=xpcall(function()
 local UI=require(module);local C=require(shared.MarketConfig);local Market=require(shared.MarketClient)
 local quotes,cache={},{}
 for _,key in ipairs(C.ContractOrder)do
  local price=C.Contracts[key].Last
  quotes[key]={Last=price,Open=price,Bid=price-C.Contracts[key].Tick,Ask=price+C.Contracts[key].Tick}
  for _,tf in ipairs(C.Timeframes)do local bars={};for i=1,100 do bars[i]={Time=i*tf[2],Open=price,Close=price,High=price+1,Low=price-1,Volume=50}end;cache[key..":"..tf[1]]=bars end
 end
 local report={Passed=true,Checks=0,Layouts=0}
 local function check(v,message)assert(v,message);report.Checks+=1 end
 for _,size in ipairs({{320,568},{390,844},{844,390},{1280,800}})do
  local host=Instance.new("Frame");host.Size=UDim2.fromOffset(size[1],size[2]);host.Parent=gui
  ctl=UI.Mount(host,{Preview=true,PreviewData={Quotes=quotes,CandlesBySeries=cache,Time=6000,Step=1}})
  local s=ctl.State;local session=ctl.Chart.Ctx.Session
  s.Coach=nil;s.Screen="Trade";s.Sheet=size[1]<1000;s.StopDollars=145;s.StopOn=true;s.TargetOn=true
  ctl.Chart.Ctx.refresh();task.wait(.03)
  for _,key in ipairs({"Stop","Target"})do
   local card=assert(ctl.Root:FindFirstChild(key.."Card",true),"Missing "..key.." card")
   local field=card.Distance.Value
   for _,pair in ipairs({{"145000",145000},{"145k",145000},{"145m",145e6},{"145.4k",145400},{"1B",1e9}})do
    field.Text=pair[1];check(field.TestCommit:Invoke(),"Rejected "..pair[1])
    check(s[key.."Dollars"]==pair[2]and session.ProtectionPreferences[key.."Dollars"]==pair[2],"State/preferences mismatch")
    check(field.Text==Market.Money(pair[2]),"Shorthand did not expand to full amount")
   end
   for _,bad in ipairs({"0","-1k","145kk","1.01b"})do
    field.Text=bad;check(not field.TestCommit:Invoke(),"Accepted invalid "..bad)
    check(s[key.."Dollars"]==1e9 and session.ProtectionPreferences[key.."Dollars"]==1e9,"Invalid input overwrote preferences")
    check(s.Error:find("1,000,000,000",1,true),"Error must describe the actual amount range")
   end
   task.wait(.03);check(field.TextFits,"Expanded amount clips at "..size[1])
  end
  -- Popup edits are drafts until closed; closing commits unfocused text too.
  ctl.Root:FindFirstChild("StopCard",true).Settings.TestActivate:Invoke();task.wait(.03)
  local dialog=assert(ctl.Root:FindFirstChild("ProtectionDialog",true))
  check(dialog.Subtitle.TextFits,"Shorthand hint clips")
  dialog.Fields.StopProtection.Distance.Value.Text="145.4K"
  dialog.Fields.TargetProtection.Distance.Value.Text="145M"
  dialog.Dismiss.TestActivate:Invoke()
  check(s.Overlay==nil and s.StopDollars==145400 and s.TargetDollars==145e6,"Popup failed to save both amounts")
  check(session.ProtectionPreferences.StopDollars==145400 and session.ProtectionPreferences.TargetDollars==145e6,"Popup preferences did not persist")
  s.Sheet=size[1]<1000;s.Type="Limit";ctl.Chart.Ctx.refresh();task.wait(.03)
  local limit=assert(ctl.Root:FindFirstChild("LimitPrice",true)).Value
  limit.Text="5.8k";check(limit.TestCommit:Invoke()and s.Limit==5800,"Limit price did not parse shorthand")
  local quantity=assert(ctl.Root:FindFirstChild("Quantity",true)).Value
  quantity.Text=".001k";check(quantity.TestCommit:Invoke()and s.Qty==1,"Quantity did not parse shorthand")
  quantity.Text=".0015k";check(not quantity.TestCommit:Invoke()and s.Qty==1,"Fractional quantity accepted")
  check(not ctl.Root:GetAttribute("RenderError")and not ctl.Root:GetAttribute("ChartError"),"UI render error")
  report.Layouts+=1;ctl:Destroy();ctl=nil;host:Destroy()
 end
 return report
end,debug.traceback)
if ctl then ctl:Destroy()end;gui:Destroy();shared:Destroy()
if not ok then error(result)end
return result
