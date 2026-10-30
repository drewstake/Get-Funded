-- Executed from Studio MCP; reads native MicroProfiler data, never market state.
local MP=require('@rbx/LibMP')
MP.Control:SetFrameLimit(256);MP.Control:EnableProfiler(true);MP.Control:EnableCapture(true)
local root=Instance.new('BindableFunction');root.Name='MicroProfilerEvidence';root.Parent=game.ServerStorage
local captures={};local frames={};local started=os.clock();local lastCapture=started;local enabled=true;local busy=false
local function capture(dt)
 if busy then return end;busy=true
 local at=os.clock();MP.Control:EnableCapture(false)
 local buf=MP.Control:CaptureToBufferSync();MP.Control:EnableCapture(true)
 table.insert(captures,{Buffer=buf,Dt=dt,At=os.clock()-started,Start=at-started,CopyMs=(os.clock()-at)*1000,ProbeAt=game.ServerStorage:GetAttribute('MPProbeAt')})
 lastCapture=os.clock();busy=false
end
local lastProbe=game.ServerStorage:GetAttribute("MPProbe")
local heartbeat=game.RunService.Heartbeat:Connect(function(dt)
 if not enabled then return end
 table.insert(frames,dt*1000)
 local probe=game.ServerStorage:GetAttribute("MPProbe")
 if probe~=lastProbe then
  lastProbe=probe;task.delay(.06,function()if enabled then capture(dt)end end)
 elseif dt>=.045 and os.clock()-lastCapture>3 and #captures<8 then
  lastCapture=os.clock();task.delay(.05,function()if enabled then capture(dt)end end)
 end
end)
root.OnInvoke=function(command,index)
 if command=='Status'then
  local rows={};for i,r in ipairs(captures)do table.insert(rows,{Index=i,At=r.At,TriggerMs=r.Dt*1000,Bytes=buffer.len(r.Buffer),Start=r.Start,CopyMs=r.CopyMs,ProbeAt=r.ProbeAt})end
  return {Captures=rows,Seconds=os.clock()-started,Enabled=enabled,Frames=#frames}
 elseif command=='Buffer'then return captures[index].Buffer
 elseif command=='Stop'then enabled=false;heartbeat:Disconnect();return true
 elseif command=='FrameTimes'then return frames
 elseif command=='Snapshot'then capture(0);return #captures
 elseif command=='Cleanup'then enabled=false;heartbeat:Disconnect();table.clear(captures);root:Destroy();return true end
end
return {Capturing=true,TriggerMs=45,MaxCaptures=8,FrameLimit=256}
