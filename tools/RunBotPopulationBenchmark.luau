-- Read one Live checkpoint, benchmark two detached copies; never claim a lease or save.
assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local Http=game:GetService('HttpService')
assert(not _G.BotPopulationJob or coroutine.status(_G.BotPopulationJob)=='dead','Another comparison is running')
_G.BotPopulationJob=task.spawn(function()
 local roots={}
 local ok,err=xpcall(function()
  for _,variant in ipairs({'baseline','proposed'})do
   local root=Instance.new('Folder');root.Name='DetachedBenchmark'..variant;roots[variant]=root
   local bundle=Http:JSONDecode(Http:GetAsync('http://127.0.0.1:8798/'..variant))
   for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root end
  end
  local CP=require(roots.proposed.WorldCheckpoint)
  local record=game:GetService('DataStoreService'):GetDataStore('MarketReign_Continuous_v1','Live'):GetAsync('primary-exchange')
  assert(record and record.Checkpoint,'Missing Live checkpoint')
  local snapshot=CP.Decode(record.Checkpoint)
  local report={SavedAt=record.SavedAt,ReadAt=os.time(),SourceVersion=snapshot.Version}
  for _,variant in ipairs({'baseline','proposed'})do
   local root=roots[variant];local cp=require(root.WorldCheckpoint)
   local e,p=cp.Restore(snapshot,require(root.MarketConfig))
   report[variant=='baseline'and 'Before'or 'After']=require(root.BenchmarkBotPopulation).Run(e,p,cp,1800,function()task.wait()end)
  end
  Http:PostAsync('http://127.0.0.1:8798/native-live-benchmark.json',Http:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
 end,debug.traceback)
 for _,root in pairs(roots)do root:Destroy()end
 Http:PostAsync('http://127.0.0.1:8798/native-benchmark-status.json',Http:JSONEncode({Finished=true,Success=ok,Error=not ok and tostring(err)or nil}),Enum.HttpContentType.ApplicationJson)
end)
