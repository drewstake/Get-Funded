-- Clone every dependency to avoid cached modules, live accounts and saved data.
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="ProtectionBandQA";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone();server.Name="ProtectionBandQA";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,root in ipairs({shared,server})do for _,m in ipairs(root:GetDescendants())do if m:IsA("LuaSourceContainer")then
 m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.ProtectionBandQA"):gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.ProtectionBandQA")
end end end
local report={Suites={},Cases=0,Passed=0,Failures={}}
for _,name in ipairs({"MarketTests","TradeAmendmentTests","TradeLimitsTests","AccountUpgradeTests","SecurityTests"})do
 local ok,result=xpcall(function()
  local suite=require(server:FindFirstChild(name)or shared[name])
  return type(suite)=="function"and suite()or suite.Run()
 end,debug.traceback)
 local summary={Cases=0,Passed=0}
 if not ok then table.insert(report.Failures,{Suite=name,Error=tostring(result)})
 elseif type(result.Passed)=="boolean"then
  summary.Cases=result.Cases or 1;summary.Passed=result.Passed and summary.Cases or 0
  if not result.Passed then table.insert(report.Failures,{Suite=name,Result=result})end
 else
  for _,row in ipairs(result.Results or result)do
   summary.Cases+=1
   if row.Passed then summary.Passed+=1 else table.insert(report.Failures,{Suite=name,Result=row})end
  end
  if summary.Cases==0 then table.insert(report.Failures,{Suite=name,Error="No test cases were reported",Result=result})end
 end
 report.Suites[name]=summary;report.Cases+=summary.Cases;report.Passed+=summary.Passed
end
shared:Destroy();server:Destroy()
return report
