local H=game:GetService('HttpService');local E=require(game.ServerScriptService.MarketReign.MarketEngine)
local original=E.Snapshot;local R=game:GetService('RunService');local d=game.ServerScriptService.MarketReign.StudioDiagnostics
local frames={DtMs={},WorkMs={},Backlog={}};local spikes={};local started=os.clock();local before=d:Invoke('Performance')
E.Snapshot=function(self,...)
 local packet=original(self,...);packet.LatencyProbeSent=workspace:GetServerTimeNow();return packet
end
local connection=R.Heartbeat:Connect(function(dt)
 local p=d:Invoke('Performance');table.insert(frames.DtMs,dt*1000);table.insert(frames.WorkMs,p.LastMs);table.insert(frames.Backlog,p.Backlog)
 if dt>.05 and #spikes<40 then table.insert(spikes,{At=os.clock(),DtMs=dt*1000,WorkMs=p.LastMs,Steps=p.LastSteps,Backlog=p.Backlog})end
end)
task.delay(90,function()
 connection:Disconnect();E.Snapshot=original
 local enabled=H.HttpEnabled;H.HttpEnabled=true
 local stats={};for k,values in pairs(frames)do table.sort(values);local sum=0;for _,v in ipairs(values)do sum+=v end;stats[k]={Count=#values,Mean=sum/#values,P50=values[math.ceil(#values*.5)],P95=values[math.ceil(#values*.95)],P99=values[math.ceil(#values*.99)],Max=values[#values]}end
 local report={Seconds=os.clock()-started,Stats=stats,Spikes=spikes,Before=before,After=d:Invoke('Performance')}
 local ok,err=pcall(function()H:PostAsync('http://127.0.0.1:8818/live-server-baseline.json',H:JSONEncode(report),Enum.HttpContentType.ApplicationJson)end);H.HttpEnabled=enabled;if not ok then warn(err)end
end)
return {ObservingSeconds=90,NoOrdersSubmitted=true}
