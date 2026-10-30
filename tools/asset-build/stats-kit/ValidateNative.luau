-- Run after binding the kit module to a local variable named Kit.
local checks={}
local function check(name,fn) fn();table.insert(checks,name) end
local a={Net=-56808.75,Gains=12881,Loss=69689.75,Wins=12,Losses=29,Even=0,Trades=41,AvgWin=12881/12,AvgLoss=69689.75/29,WinRate=12/41,WinLossRatio=(12881/12)/(69689.75/29),ProfitFactor=12881/69689.75,DailyComplete=false,Attempts=7,Blown=6}
local initial=Kit.FromAggregate(a)
check("Original six metric values",function()
 assert(#initial==6 and initial[1].Value=="-$56,808.75" and initial[2].Value=="29.27%" and initial[3].Value=="0.45" and initial[5].Value=="0.18")
end)
check("Missing dates",function()assert(initial[4].Value=="—" and initial[6].Value=="—")end)
check("Partial history",function()
 a.Partial=true;local m=Kit.FromAggregate(a);assert(m[1].Value==initial[1].Value and m[2].Value=="—" and m[3].Value=="—" and m[5].Value=="—");a.Partial=false
end)
check("Unknown count",function()a.CountUnknown=true;assert(Kit.FromAggregate(a)[2].Value=="—");a.CountUnknown=false end)
check("Negative best day unavailable",function()a.DailyComplete=true;a.BestDayShare=2;assert(Kit.FromAggregate(a)[6].Value=="—")end)
check("Infinity and share above 100%",function()a.Net=100;a.NoLosses=true;local m=Kit.FromAggregate(a);assert(m[3].Value=="∞" and m[5].Value=="∞" and m[6].Value=="200.00%")end)
local holder=Instance.new("Frame")
local gui=Instance.new("ScreenGui")
local ok,err=xpcall(function()
 check("Native metric construction",function()
  for i,m in ipairs(initial) do local card=Kit.Metric(holder,m,UDim2.fromOffset(0,(i-1)*270),UDim2.fromOffset(340,262),function()end)
   assert(card.Value.Text==m.Value and card.Help.Active)
  end
 end)
 check("Disabled controls",function()
  local b=Kit.Button(holder,"Disabled","Disabled",UDim2.new(),UDim2.fromOffset(100,44),nil);assert(not b.Active and not b.Selectable)
 end)
 check("Progress proportions",function()
  local b=Kit.Progress(holder,"Bar",UDim2.new(),UDim2.fromOffset(200,10),1,2,1)
  assert(b.Segment1.Size.X.Scale==.25 and b.Segment2.Size.X.Scale==.5 and b.Segment3.Size.X.Scale==.25)
 end)
 check("Mount update and cleanup",function()
  local c=Kit.Mount(gui,a);assert(c.Root.Name=="StatsKit");c:Update(a,{State="Error"});c:Destroy()
 end)
end,debug.traceback)
holder:Destroy();gui:Destroy()
assert(ok,err)
return {theme=Kit.Theme.Layout,passed=#checks,checks=checks,temporaryInstancesDestroyed=true,scope="Compilation, aggregate formatting and unparented component construction. Full in-game visual integration is not included."}

