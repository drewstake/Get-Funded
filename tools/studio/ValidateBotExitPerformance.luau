-- Detached validation and replay of the backed-up Studio state; no datastore writes.
assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local H=game:GetService('HttpService')
_G.BotExitValidation=task.spawn(function()
 local roots={}
 local ok,err=xpcall(function()
  for _,variant in ipairs({'baseline','bundle'})do
   local root=Instance.new('Folder');root.Name='DetachedExitPerformance'..variant;roots[variant]=root
   local bundle=H:JSONDecode(H:GetAsync('http://127.0.0.1:8797/'..variant))
   local count=0
   for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root;count+=1;if count%50==0 then task.wait()end end
  end
  local report={Results={},Failures=0,Total=0}
  for _,name in ipairs({'BotExitRetryTests','BotPopulationTests','ProtectiveOrdersTests','ResetLiquidationTests','MarketTests','ExecutionChoiceTests',
   'SharedDepthTests','TradeLimitsTests','ClosedTradePnlTests','TradePreferencesTests','DepthRealismTests','ScalperTests',
   'MakerLiquidityTests','WorldTests','CapacityTests','SingleAccountTests','AccountUpgradeTests','OwnerGiveTests','OwnerResetTests','RankBadgeTests','SecurityTests'})do
   task.wait();local passed,result=pcall(function()return require(roots.bundle[name]).Run()end)
   local rows=passed and(result.Results or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
   report.Results[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
   H:PostAsync('http://127.0.0.1:8797/test-progress.json',H:JSONEncode({Suite=name,Total=report.Total,Failures=report.Failures}),Enum.HttpContentType.ApplicationJson)
  end
  H:PostAsync('http://127.0.0.1:8797/native-tests.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
  assert(report.Failures==0,tostring(report.Failures)..' validation tests failed')
  local saved=H:JSONDecode(H:GetAsync('http://127.0.0.1:8797/checkpoint'))
  local bench={Source='Backed-up Studio checkpoint',SavedAt=saved.Record.SavedAt,Variants={}}
  for _,variant in ipairs({'baseline','bundle'})do
   local root=roots[variant];local CP=require(root.WorldCheckpoint)
   local snapshot=CP.Decode(saved.Record.Checkpoint)
   local e,p=CP.Restore(snapshot,require(root.MarketConfig))
   local scans,submits=0,0;local oldPrune=e._pruneBook;local oldSubmit=e.Submit
   e._pruneBook=function(self,b)scans+=1;return oldPrune(self,b)end
   e.Submit=function(self,...)submits+=1;return oldSubmit(self,...)end
   local costs={};local total=0;local first=e.NextOrder
   for i=1,128 do
    local started=os.clock();p:Step();local cost=(os.clock()-started)*1000
    table.insert(costs,cost);total+=cost;task.wait()
   end
   table.sort(costs)
   bench.Variants[variant]={Steps=#costs,TotalMs=total,MeanStepMs=total/#costs,P95StepMs=costs[math.ceil(#costs*.95)],MaxStepMs=costs[#costs],
    BookScans=scans,SubmitCalls=submits,NewOrders=e.NextOrder-first,Audit=e:Audit()}
  end
  H:PostAsync('http://127.0.0.1:8797/native-studio-benchmark.json',H:JSONEncode(bench),Enum.HttpContentType.ApplicationJson)
 end,debug.traceback)
 for _,root in pairs(roots)do root:Destroy()end
 H:PostAsync('http://127.0.0.1:8797/validation-status.json',H:JSONEncode({Finished=true,Success=ok,Error=not ok and tostring(err)or nil}),Enum.HttpContentType.ApplicationJson)
end)
