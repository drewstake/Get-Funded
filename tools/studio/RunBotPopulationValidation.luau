-- Run in Studio Edit with tools/experiments/bot_population_bridge.py listening. Detached tests only.
assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local Http=game:GetService('HttpService')
assert(not _G.BotAdditionalTests or coroutine.status(_G.BotAdditionalTests)=='dead','Tests already running')
_G.BotAdditionalTests=task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedBotPopulationValidation'
 local ok,err=xpcall(function()
  local bundle=Http:JSONDecode(Http:GetAsync('http://127.0.0.1:8798/proposed'))
  for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root end
  local report={};local failures=0
  for _,name in ipairs({'BotPopulationTests','ProtectiveOrdersTests','ResetLiquidationTests','MarketTests','ExecutionChoiceTests',
   'SharedDepthTests','TradeLimitsTests','ClosedTradePnlTests','TradePreferencesTests','DepthRealismTests','ScalperTests',
   'MakerLiquidityTests','WorldTests','CapacityTests','SingleAccountTests','AccountUpgradeTests','OwnerGiveTests','OwnerResetTests','RankBadgeTests','SecurityTests'})do
   task.wait();local passed,result=pcall(function()return require(root[name]).Run()end)
   local rows=passed and(result.Results or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
   report[name]=rows;for _,row in ipairs(rows)do if not row.Passed then failures+=1 end end
  end
  Http:PostAsync('http://127.0.0.1:8798/native-all-tests.json',Http:JSONEncode({Results=report,Failures=failures}),Enum.HttpContentType.ApplicationJson)
 end,debug.traceback)
 root:Destroy();Http:PostAsync('http://127.0.0.1:8798/native-all-test-status.json',Http:JSONEncode({Finished=true,Success=ok,Error=not ok and tostring(err)or nil}),Enum.HttpContentType.ApplicationJson)
end)
