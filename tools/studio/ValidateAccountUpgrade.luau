-- Fresh graphs, disposable engines and fake stores only.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="UpgradeQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="UpgradeQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,root in ipairs({shared,server})do for _,m in ipairs(root:GetDescendants())do if m:IsA("LuaSourceContainer")then
 m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.UpgradeQA"):gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.UpgradeQA")
end end end
local report={Suites={},Cases=0,Failures={}}
for _,name in ipairs({"MarketTests","SingleAccountTests","WorldTests","TradeAmendmentTests","TradePreferencesTests","RankBadgeTests","OwnerResetTests","TradeLimitsTests","SharedDepthTests","SecurityTests","AccountUpgradeTests","ChartToolsTests","ChartViewportTests","ChartPaintPoolTests"})do
 local ok,rows=xpcall(function()local t=require(server:FindFirstChild(name)or shared[name]);return type(t)=="function"and t()or t.Run()end,debug.traceback)
 report.Suites[name]=ok and rows or tostring(rows)
 if ok and type(rows)=="table"then
  if rows.Passed~=nil then report.Cases+=rows.Cases or 1;if not rows.Passed then table.insert(report.Failures,{Suite=name,Result=rows})end
  else for _,r in ipairs(rows)do report.Cases+=1;if not r.Passed then table.insert(report.Failures,{Suite=name,Result=r})end end end
 else table.insert(report.Failures,{Suite=name,Error=tostring(rows)})end
end
shared:Destroy();server:Destroy();return report
