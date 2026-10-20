-- Detached native modules; only reads the captured Studio checkpoint.
local H=game:GetService('HttpService');local base='http://127.0.0.1:8807/'
local function post(name,data)H:PostAsync(base..name,H:JSONEncode(data),Enum.HttpContentType.ApplicationJson)end
local function source(s)return(s:gsub('require%(game%.ReplicatedStorage%.MarketReign%.(%w+)%)','require(script.Parent.%1)'):gsub('require%(game%.ServerScriptService%.MarketReign%.(%w+)%)','require(script.Parent.%1)'))end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' value');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
task.spawn(function()
 local root=Instance.new('Folder');root.Name='DetachedParticipantExpansion'
 local report={Total=0,Failures=0,Suites={},DataStoreWrites=false}
 local ok,err=xpcall(function()
  for _,container in ipairs({game.ServerScriptService.MarketReign,game.ReplicatedStorage.MarketReign})do
   for _,m in ipairs(container:GetChildren())do if m:IsA('ModuleScript')then
    local copy=Instance.new('ModuleScript');copy.Name=m.Name;copy.Source=source(m.Source);copy.Parent=root
   end end;task.wait()
  end
  local release=H:JSONDecode(H:GetAsync(base..'release'))
  for path,item in pairs(release)do
   local name=path:match('[^.]+$');local m=root:FindFirstChild(name)or Instance.new('ModuleScript')
   m.Name=name;m.Source=source(item.Source);m.Parent=root
  end
  local scheduler=require(root.Participants);local step=scheduler.Step;local calls=0
  scheduler.Step=function(self,...)local result=step(self,...);calls+=1;if calls%20==0 then task.wait()end;return result end
  for _,name in ipairs({'OrderFlowMarketTests','BotPublicInformationTests','SharedDepthTests','DepthRealismTests','BotFairnessTests','BotSignalsTests','ScalperTests','BotPopulationTests','ParticipantExpansionTests','LegacyRetirementTests','BotRefreshTests','BotStatsTests','BotExitRetryTests','MakerLiquidityTests','ExecutionIntegrityTests','MarketTests','WorldTests','ProtectiveOrdersTests'})do
   task.wait();local good,rows=pcall(function()return require(root[name]).Run()end)
   rows=good and(rows.Results or rows)or{{Name='Suite',Passed=false,Detail=tostring(rows)}};report.Suites[name]=rows
   for _,row in ipairs(rows)do report.Total+=1;if not row.Passed then report.Failures+=1 end end
   post('studio-release-progress.json',{Suite=name,Total=report.Total,Failures=report.Failures,Results=rows})
  end
  assert(report.Failures==0,'Native regression failures')
  local CP=require(root.WorldCheckpoint);local C=require(root.MarketConfig)
  local record=assert(H:JSONDecode(H:GetAsync(base..'checkpoint')).Record)
  local saved=CP.Decode(record.Checkpoint);local e,p=CP.Restore(saved,C)
  local restored=CP.Capture(e,p);local accounts={};for _,ac in ipairs(restored.Engine.Accounts)do accounts[ac.Id]=ac end
  for _,ac in ipairs(saved.Engine.Accounts)do equal(ac,accounts[ac.Id],'saved account.'..ac.Id)end
  for i,a in ipairs(saved.Population.Agents)do equal(a,p.Agents[i],'saved agent.'..a.Id)end
  assert(e.NextTrade==saved.Engine.NextTrade and e.TotalVolume==saved.Engine.TotalVolume and #p.Agents==1170)
  p:Prepare();local after=CP.Capture(e,p);local encoded=CP.Encode(after)
  local e2,p2=CP.Restore(CP.Decode(encoded),C);equal(after,CP.Capture(e2,p2))
  for i=1,240 do p:Step();p2:Step();if i%20==0 then task.wait()end end
  equal(CP.Capture(e,p),CP.Capture(e2,p2))
  report.SavedWorld={FromVersion=saved.Version,ToVersion=CP.Version,ReplaySteps=240,Accounts=#e.AccountOrder,Participants=#p.Agents,
   Added=#p.Agents-#saved.Population.Agents,RawBytes=encoded.RawBytes,PayloadBytes=#encoded.Payload,Audit=e:Audit(),ExistingAccountsAndAgentsPreserved=true}
 end,debug.traceback)
 root:Destroy();report.Success=ok;report.Error=not ok and tostring(err)or nil
 post('studio-release-validation.json',report)
end)
return 'Detached participant expansion validation started'
