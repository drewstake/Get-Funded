-- Detached validation against a backup; never writes to a Roblox DataStore.
local H=game:GetService('HttpService')
local base='http://127.0.0.1:8798/'
local function post(name,value)H:PostAsync(base..name,H:JSONEncode(value),Enum.HttpContentType.ApplicationJson)end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type differs')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' added '..tostring(k))end
end
task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedBotStrategyValidation'
 local ok,err=xpcall(function()
  local bundle=H:JSONDecode(H:GetAsync(base..'bundle'));local n=0
  for name,source in pairs(bundle)do
   local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=root
   n+=1;if n%25==0 then task.wait()end
  end
  local report={Total=0,Failures=0,Suites={}}
  for _,name in ipairs({'BotSignalsTests','ScalperTests','BotPopulationTests','BotRefreshTests','WorldTests','BotExitRetryTests','MarketTests','ExecutionIntegrityTests','ProtectiveOrdersTests'})do
   task.wait();local passed,result=pcall(function()return require(root[name]).Run()end)
   local rows=passed and(result.Results or result)or{{Name='Suite',Passed=false,Detail=tostring(result)}}
   report.Suites[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
   post('studio-test-progress.json',{Suite=name,Total=report.Total,Failures=report.Failures})
  end
  post('studio-tests.json',report);assert(report.Failures==0,'Studio regression tests failed')
  local saved=H:JSONDecode(H:GetAsync(base..'checkpoint'))
  local CP=require(root.WorldCheckpoint);local C=require(root.MarketConfig)
  local snapshot=CP.Decode(saved.Record.Checkpoint)
  local engine,population=CP.Restore(snapshot,C)
  local restored=CP.Capture(engine,population)
  equal(snapshot.Engine,restored.Engine,'engine')
  equal(snapshot.Population,restored.Population,'population')
  assert(restored.Config.BotSignals.Version==1 and restored.Version==18,'Strategy migration missing')
  local encoded=CP.EncodeWorld(engine,population)
  local e2,p2=CP.Restore(CP.Decode(encoded),C)
  equal(restored,CP.Capture(e2,p2),'roundtrip')
  local initialStats=require(root.BotStats).Capture(engine,population)
  for i=1,240 do population:Step();p2:Step();if i%40==0 then task.wait()end end
  equal(CP.Capture(engine,population),CP.Capture(e2,p2),'resumed replay')
  local result={Success=true,SourceVersion=snapshot.Version,Version=18,SignalsVersion=1,InitialStep=snapshot.Engine.Step,FinalStep=engine.Step,
   ExactEnginePreserved=true,ExactPopulationPreserved=true,ExactRoundtrip=true,ReplaySteps=240,ExactReplay=true,Audit=engine:Audit(),
   Participants=#population.Agents,InitialBots=initialStats.Total,FinalBots=require(root.BotStats).Capture(engine,population).Total,Scope=saved.Scope}
  post('studio-saved-migration.json',result)
 end,debug.traceback)
 root:Destroy();post('studio-validation-status.json',{Finished=true,Success=ok,Error=not ok and tostring(err)or nil})
end)
return 'Detached validation started'
