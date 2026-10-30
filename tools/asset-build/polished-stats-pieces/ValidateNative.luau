local checks={}
local resources={}
local function check(name,fn)fn();table.insert(checks,{name=name,passed=true})end
local holder=Instance.new("Folder");table.insert(resources,holder)
local gui=Instance.new("ScreenGui");table.insert(resources,gui)
local controller
local ok,err=xpcall(function()
 check("All 32 templates construct as native GUI hierarchies",function()
  local count=0
  for name in pairs(Kit.Spec.templates)do local o=Kit.Create(name,holder);assert(o:IsA("GuiObject"));count+=1 end
  assert(count==32)
 end)
 check("Exact initial aggregate and incomplete daily state",function()
  local m=Kit.FromAggregate(Fixtures.All.Life)
  assert(m[1].Value=="-$56,808.75" and m[2].Value=="29.27%" and m[3].Value=="0.45" and m[5].Value=="0.18")
  assert(m[4].Value=="—" and m[6].Value=="—")
 end)
 check("Incomplete breakdown suppresses unsupported ratios",function()
  local a=table.clone(Fixtures.All.Life);a.Partial=true
  local m=Kit.FromAggregate(a)
  assert(m[1].Value=="-$56,808.75" and m[2].Value=="—" and m[3].Value=="—" and m[5].Value=="—")
 end)
 check("Infinity and best-day percentages above 100",function()
  local m=Kit.FromAggregate({Net=100,Gains=200,Loss=0,NoLosses=true,DailyComplete=true,BestDayShare=1.5})
  assert(m[3].Value=="∞" and m[5].Value=="∞" and m[6].Value=="150.00%")
 end)
 local fail=false
 controller=Kit.Mount(gui,Fixtures.All.Life,{OnFilter=function(scope,period)
  if fail then return nil end
  return Fixtures[scope] and Fixtures[scope][period]
 end})
 check("Assembled mount applies editable values",function()
  assert(controller.Root:FindFirstChild("TotalValue",true).Text=="-$56,808.75")
  assert(controller.Root:FindFirstChild("FundedDropdown",true):IsA("TextButton"))
 end)
 check("Funded dropdown selection commits matching aggregate",function()
  assert(controller.Dropdowns.Funded:Choose("5K"))
  assert(controller.Dropdowns.Funded:Get()=="5K")
  assert(controller.Root:FindFirstChild("FundedDropdownLabel",true).Text=="$5K accounts")
  local expected=Kit.FromAggregate(Fixtures["5K"].Life)[1].Value
  assert(controller.Root:FindFirstChild("TotalValue",true).Text==expected)
 end)
 check("Scope dropdown is independent and dated updates daily metrics",function()
  assert(controller.Dropdowns.Scope:Choose("Dated"))
  assert(controller.Dropdowns.Funded:Get()=="5K")
  assert(controller.Root:FindFirstChild("DayValue",true).Text~="—")
 end)
 check("Failed data fetch preserves selected scope and values",function()
  local prior=controller.Root:FindFirstChild("TotalValue",true).Text
  fail=true;assert(controller.Dropdowns.Funded:Choose("25K")==false);fail=false
  assert(controller.Dropdowns.Funded:Get()=="5K")
  assert(controller.Root:FindFirstChild("TotalValue",true).Text==prior)
 end)
 check("One popup at a time and reopening a superseded popup",function()
  controller.Dropdowns.Funded:Open();assert(controller.Dropdowns.Funded:IsOpen())
  controller.Dropdowns.Scope:Open();assert(controller.Dropdowns.Scope:IsOpen() and not controller.Dropdowns.Funded:IsOpen())
  controller.Dropdowns.Funded:Open();assert(controller.Dropdowns.Funded:IsOpen() and not controller.Dropdowns.Scope:IsOpen())
  controller.Dropdowns.Funded:Close();assert(not controller.Dropdowns.Funded:IsOpen())
 end)
 check("Update and progress proportions remain consistent",function()
  controller:Update(Fixtures.All.Life,{Scope="All",Period="Life"})
  local bar=controller.Root:FindFirstChild("TradeBar",true)
  assert(math.abs(bar.TradeBarWin.Size.X.Scale-12/41)<.0001)
  local a=table.clone(Fixtures.All.Life);a.CountUnknown=true
  controller:Update(a)
  assert(controller.Root:FindFirstChild("TradeValue",true).Text=="—")
  assert(not bar:FindFirstChild("TradeBarWin"))
 end)
 check("Existing game icon IDs preserved",function()
  assert(controller.Root:FindFirstChild("IconTrade",true).Image=="rbxassetid://135864586704544")
  assert(controller.Root:FindFirstChild("IconStats",true).Image=="rbxassetid://140314319475475")
 end)
 check("Native help popup construction and cleanup",function()
  local h=Kit.ShowHelp(controller.Root,"Metric help","Test description")
  assert(h.HelpPanel.Body.Text=="Test description");h:Destroy()
 end)
 check("Destroy removes owned objects and menu listeners",function()
  controller:Destroy();assert(gui:FindFirstChild("PolishedStatsHost")==nil);controller=nil
 end)
end,debug.traceback)
if controller then controller:Destroy()end
for _,r in ipairs(resources)do r:Destroy()end
assert(ok,err)
return {checks=checks,passed=#checks,temporaryInstancesDestroyed=true,scope="Studio runtime compilation, native hierarchy construction, formatting, data binding and dropdown lifecycle using unparented test objects."}
