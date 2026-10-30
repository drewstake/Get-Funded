-- Run in Studio Server/Play against detached modules and a captured checkpoint only.
-- Does not invoke the real command, Players, diagnostics, or a real DataStore.
local H=game:GetService("HttpService")
task.spawn(function()
 local root=Instance.new("Folder");root.Name="DetachedBotsRefreshValidation"
 local ok,err=xpcall(function()
  local bundle=H:JSONDecode(H:GetAsync("http://127.0.0.1:8799/bundle"))
  local count=0
  for name,source in pairs(bundle)do
   local m=Instance.new("ModuleScript");m.Name=name;m.Source=source;m.Parent=root
   count+=1;if count%25==0 then task.wait()end
  end
  local report={Total=0,Failures=0,Suites={}}
  for _,name in ipairs({"BotRefreshTests","ExecutionIntegrityTests","BotExitRetryTests","RequestJournalTests","ProtectiveOrdersTests","WorldTests","OwnerResetTests","OwnerGiveTests"})do
   task.wait();local passed,result=pcall(function()local m=require(root[name]);return type(m)=="function"and m()or m.Run()end)
   local rows=passed and(result.Results or result)or{{Name="Suite",Passed=false,Detail=tostring(result)}}
   report.Suites[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
  end
  H:PostAsync("http://127.0.0.1:8799/studio-tests.json",H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
  assert(report.Failures==0,"Detached Studio tests failed")
  local saved=H:JSONDecode(H:GetAsync("http://127.0.0.1:8799/checkpoint"))
  local snapshot=require(root.WorldCheckpoint).Decode(saved.Record.Checkpoint)
  local result=require(root.BotRefreshTests).Captured(snapshot,64,task.wait)
  H:PostAsync("http://127.0.0.1:8799/studio-captured-replay.json",H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
 end,debug.traceback)
 root:Destroy()
 H:PostAsync("http://127.0.0.1:8799/studio-status.json",H:JSONEncode({Success=ok,Error=not ok and tostring(err)or nil}),Enum.HttpContentType.ApplicationJson)
end)
