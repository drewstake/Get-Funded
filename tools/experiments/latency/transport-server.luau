-- Detached transport fixture: production engine, scheduler, FIFO and client;
-- independent account/world/remotes. No live order or DataStore calls.
local variant=__VARIANT__
local H=game:GetService('HttpService');local enabled=H.HttpEnabled;H.HttpEnabled=true
local bundle=H:JSONDecode(H:GetAsync('http://127.0.0.1:8818/bundle/'..variant))
local export=H:JSONDecode(H:GetAsync('http://127.0.0.1:8818/checkpoint'));H.HttpEnabled=enabled
local server=Instance.new('Folder');server.Name='LatencyTransportServer';server.Parent=game.ServerStorage
local client=Instance.new('Folder');client.Name='LatencyTransport';client.Parent=game.ReplicatedStorage
local shared={MarketClient=true,MarketConfig=true,ChartTimeframes=true,ProgressionConfig=true,TradeProtection=true,ContractLimits=true,ConnectionStatus=true,MarketPacket=true}
local count=0
for name,source in pairs(bundle)do
 local m=Instance.new('ModuleScript');m.Name=name;m.Source=source;m.Parent=server
 if shared[name]then local c=m:Clone();c.Parent=client end
 count+=1;if count%25==0 then task.wait()end
end
local CP=require(server.WorldCheckpoint);local C=require(server.MarketConfig);local F=require(server.FundedAccounts)
local Queue=require(server.RequestQueue);local Scheduler=require(server.SimulationScheduler)
local e,p=CP.Restore(CP.Decode(export.Checkpoint),C)
local id='latency:detached';e:AddAccount(id,200000,200,1,true)
local req=Instance.new('RemoteEvent');req.Name='OrderRequest';req.Parent=client
local update=Instance.new('RemoteEvent');update.Name='MarketUpdate';update.Parent=client
local diagnostic=Instance.new('BindableFunction');diagnostic.Name='Diagnostics';diagnostic.Parent=server
local player=game.Players:GetPlayers()[1];local queue={};local replies={};local subscribed=false;local full=true;local finished=false
local elapsed,broadcast=0,0;local frames={};local bytes=0;local packets=0;local actions={}
local function packet(accountOnly)
 local value=accountOnly and e:AccountSnapshot(id)or e:Snapshot(id,'BX','1m',full)
 value.AccountOnly=accountOnly or nil;value.RequestSession=1;value.AccountToken=id;value.AccountKey=id
 value.CanTrade=true;value.ConnectionStatus='DETACHED LATENCY TEST';value.PersistenceMode='Local';value.Regime=p.Regime.Name;value.Speed=C.SimulationSpeed
 value.DepthAccess={Allowed=true,State='Fixture'};value.Replies=replies;replies={};value.Seed=nil;value.Portfolio={Active=id,Revision=1,Started=true}
 value.TraceSent=workspace:GetServerTimeNow();bytes+=#H:JSONEncode(value);packets+=1;update:FireClient(player,value);full=false
end
local requestConnection=req.OnServerEvent:Connect(function(who,request)
 if who~=player then return end
 if request.Action=='DiagnosticFinish'then finished=true;return end
 if request.Action=='Subscribe'then subscribed=true;full=true;return end
 table.insert(queue,{Request=request,Received=workspace:GetServerTimeNow()})
end)
local heartbeat=game:GetService('RunService').Heartbeat:Connect(function(dt)
 if not subscribed or finished then return end
 local at=os.clock();elapsed+=dt*C.SimulationSpeed;broadcast+=dt
 local steps;elapsed,steps=Scheduler.Advance(elapsed,C,function()
  p:Prepare()
  if #queue>0 then
   local batch;batch,queue=Queue.Take(queue)
   for _,item in ipairs(batch)do
    local start=os.clock();local processed=workspace:GetServerTimeNow();local request=item.Request
    local ok,result=F.Perform(e,id,request);e:ProcessStops()
    local reply={RequestId=request.Id,Ok=ok,Kind=request.Action,Message=type(result)=='string'and result or 'Detached result',Result=type(result)=='table'and result or nil,
     Trace={Received=item.Received,Processed=processed,Completed=workspace:GetServerTimeNow(),WorkMs=(os.clock()-start)*1000,Step=e.Step}}
    table.insert(replies,reply);table.insert(actions,{Action=request.Action,Ok=ok,Filled=reply.Result and reply.Result.Filled,Cancelled=reply.Result and reply.Result.Cancelled})
   end
  end
  p:Step()
 end,os.clock,at)
 if broadcast>=C.BroadcastSeconds then broadcast%=C.BroadcastSeconds;packet(false)
 elseif variant=='candidate'and #replies>0 then packet(true)end
 table.insert(frames,{Ms=(os.clock()-at)*1000,Backlog=elapsed,Steps=steps})
end)
diagnostic.OnInvoke=function(command)
 if command=='Finish'then
  finished=true;requestConnection:Disconnect();heartbeat:Disconnect()
  local metrics={};for _,key in ipairs({'Ms','Backlog','Steps'})do local values={};local total=0;for _,row in ipairs(frames)do table.insert(values,row[key]);total+=row[key]end;table.sort(values)
   metrics[key]={Count=#values,Mean=total/math.max(1,#values),P50=values[math.max(1,math.ceil(#values*.5))],P95=values[math.max(1,math.ceil(#values*.95))],Max=values[#values]}
  end
  local result={Variant=variant,Actions=actions,Frames=metrics,Packets=packets,JSONBytes=bytes,Audit=e:Audit(),Positions=e.Accounts[id].Positions}
  local was=H.HttpEnabled;H.HttpEnabled=true;local ok,err=pcall(function()H:PostAsync('http://127.0.0.1:8818/transport-server-'..variant..'.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)end);H.HttpEnabled=was
  if not ok then error(err)end
  task.defer(function()client:Destroy();server:Destroy()end);return {Finished=true,Actions=#actions,Packets=packets}
 end
 return {Queued=#queue,Step=e.Step,Actions=#actions}
end
return {Ready=true,Variant=variant,Detached=true}
