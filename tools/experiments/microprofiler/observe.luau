-- Read-only live observation; no market writes, orders, or frequency changes.
local H=game.HttpService;local d=game.ServerScriptService.MarketReign.StudioDiagnostics
local samples={Frames={},Work={},Backlog={}};local before=d:Invoke('Performance');local at=os.clock();local spikes={}
local connection=game.RunService.Heartbeat:Connect(function(dt)
 local p=d:Invoke('Performance');table.insert(samples.Frames,dt*1000);table.insert(samples.Work,p.LastMs);table.insert(samples.Backlog,p.Backlog)
 if dt>.024 then table.insert(spikes,{At=os.clock()-at,FrameMs=dt*1000,WorkMs=p.LastMs,Backlog=p.Backlog})end
end)
local b=Instance.new('BindableFunction');b.Name='MicroProfilerObservation';b.Parent=game.ServerStorage
local complete=false;local report
b.OnInvoke=function(command)if command=='Cleanup'then b:Destroy();return true end;return {Complete=complete,Seconds=os.clock()-at,Report=report}end
task.delay(180,function()
 connection:Disconnect();local stats={}
 for k,v in pairs(samples)do table.sort(v);local sum=0;for _,n in ipairs(v)do sum+=n end
  stats[k]={Count=#v,Mean=sum/#v,P50=v[math.ceil(#v*.5)],P95=v[math.ceil(#v*.95)],P99=v[math.ceil(#v*.99)],Max=v[#v]}
 end
 report={Seconds=os.clock()-at,Stats=stats,Spikes=spikes,Before=before,After=d:Invoke('Performance'),Persistence=d:Invoke('PersistencePerformance')}
 report.StepsPerRealSecond=(report.After.Steps-before.Steps)/report.Seconds
 local enabled=H.HttpEnabled;H.HttpEnabled=true
 local ok,err=pcall(function()H:PostAsync('http://127.0.0.1:8820/live-after.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)end)
 H.HttpEnabled=enabled;complete=true;assert(ok,err)
end)
return {ObservingSeconds=180}
