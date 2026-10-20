-- Native detached fixtures and saved-world migration. Never writes a DataStore.
local H=game:GetService('HttpService');local base='http://127.0.0.1:8796/'
local function post(name,value)H:PostAsync(base..name,H:JSONEncode(value),Enum.HttpContentType.ApplicationJson)end
task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedLegacyRetirementValidation'
 local ok,err=xpcall(function()
  local bundle=H:JSONDecode(H:GetAsync(base..'bundle'));local n=0
  for name,source in pairs(bundle)do
   local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root
   n+=1;if n%25==0 then task.wait()end
  end
  local report={Total=0,Failures=0,Suites={}}
  for _,name in ipairs({'LegacyRetirementTests','BotSignalsTests','ScalperTests','BotPopulationTests','BotRefreshTests','WorldTests','BotExitRetryTests','MarketTests','ExecutionIntegrityTests','ProtectiveOrdersTests'})do
   task.wait();local passed,result=pcall(function()return require(root[name]).Run()end)
   local rows=passed and(result.Results or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
   report.Suites[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
   post('studio-test-progress.json',{Suite=name,Total=report.Total,Failures=report.Failures})
  end
  post('studio-tests.json',report);assert(report.Failures==0,'Studio regression tests failed')
  for _,scope in ipairs({'live','studio'})do
   local saved=H:JSONDecode(H:GetAsync(base..scope..'-checkpoint'))
   local CP=require(root.WorldCheckpoint)
   local result=require(root.LegacyRetirementTests).Captured(CP.Decode(saved.Record.Checkpoint),240,task.wait)
   post('studio-'..scope..'-migration.json',result);task.wait()
  end
 end,debug.traceback)
 root:Destroy();post('studio-validation-status.json',{Finished=true,Success=ok,Error=not ok and tostring(err)or nil})
end)
return 'Detached retirement validation started'
