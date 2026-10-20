-- Read-only production snapshot inspection. The transformed copy is never written back.
assert(not game:GetService('RunService'):IsRunning(),'Edit mode required')
local Http=game:GetService('HttpService')
assert(not _G.BotDryRunJob or coroutine.status(_G.BotDryRunJob)=='dead','Dry run already running')
_G.BotDryRunJob=task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedBotMigrationDryRun'
 local ok,err=xpcall(function()
  local bundle=Http:JSONDecode(Http:GetAsync('http://127.0.0.1:8798/proposed'))
  for name,source in pairs(bundle)do local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root end
  local CP=require(root.WorldCheckpoint)
  local record=game:GetService('DataStoreService'):GetDataStore('MarketReign_Continuous_v1','Live'):GetAsync('primary-exchange')
  assert(record and record.Checkpoint,'Missing Live checkpoint')
  local snapshot=CP.Decode(record.Checkpoint);local before=Http:JSONEncode(snapshot)
  local report=require(root.DryRunBotPopulation).Run(snapshot,require(root.MarketConfig),CP)
  assert(before==Http:JSONEncode(snapshot),'Input snapshot mutated')
  report.SavedAt=record.SavedAt;report.ReadAt=os.time();report.AgeSeconds=os.time()-record.SavedAt;report.SourceVersion=snapshot.Version
  Http:PostAsync('http://127.0.0.1:8798/live-migration-dry-run.json',Http:JSONEncode(report),Enum.HttpContentType.ApplicationJson)
 end,debug.traceback)
 root:Destroy();Http:PostAsync('http://127.0.0.1:8798/live-migration-status.json',Http:JSONEncode({Finished=true,Success=ok,Error=not ok and tostring(err)or nil}),Enum.HttpContentType.ApplicationJson)
end)
