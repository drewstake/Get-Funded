-- Analyze immutable MicroProfiler buffers, yielding between batches of entries.
local MP=require('@rbx/LibMP');MP.Control:SetFrameLimit(256)
local storage=game.ServerStorage.MicroProfilerEvidence
local H=game.HttpService
local results={}
for captureIndex=1,__COUNT__ do
 local s=MP.Session.OpenFromBuffer(storage:Invoke('Buffer',captureIndex));local iter
 local ok,report=pcall(function()
  local scale=s:FetchGlobalDesc();local minimum,maximum=s:GetFrameIdMin(),s:GetFrameIdMax();local fs={};local timers,threads={},{}
  local function name(id)if not timers[id]then timers[id]=s:FetchTimerDesc(id).TimerName end;return timers[id]end
  for _,id in ipairs(s:FetchThreadIds())do threads[id]=s:FetchThreadDesc(id)end
  for i=minimum,maximum do local f=s:FetchFrameDesc(i);if f and not f.IsIncomplete then f.Ms=(f.TickEndCpu-f.TickStartCpu)*scale.TickToMsCpu;table.insert(fs,f)end end
  table.sort(fs,function(a,b)return a.Ms>b.Ms end)
  local f=assert(fs[1]);local spans={};local totals={}
  iter=s:CreateLogIterator();iter:Configure({StartFrameId=math.max(minimum,f.FrameId-1),EndFrameId=f.FrameId,SkipEvents=true,EmitThreadFrameEnd=true})
  local st=iter:GetState();local count=0
  local function append(timer,depth,first,last)
   if st:FrameId()~=f.FrameId then return end
   local gpu=st:IsGpuThread();local factor=gpu and scale.TickToMsGpu or scale.TickToMsCpu
   first=math.max(first,gpu and f.TickStartGpu or f.TickStartCpu);last=math.min(last,gpu and f.TickEndGpu or f.TickEndCpu)
   local ms=math.max(0,last-first)*factor;local tid=st:ThreadId();local key=tid..':'..timer
   local row=totals[key];if not row then row={Timer=name(timer),Thread=threads[tid].ThreadName,ThreadId=tid,Gpu=gpu,InclusiveMs=0,Calls=0,MaxMs=0};totals[key]=row end
   row.InclusiveMs+=ms;row.Calls+=1;row.MaxMs=math.max(row.MaxMs,ms)
   if ms>=.25 then
    local parents={};for d=0,depth-1 do local el=iter:GetCurrentThreadStackElement(d);if el then table.insert(parents,name(el:EnterTimerId()))end end
    table.insert(spans,{Timer=name(timer),Thread=row.Thread,ThreadId=tid,Gpu=gpu,Ms=ms,StartMs=(first-(gpu and f.TickStartGpu or f.TickStartCpu))*factor,Depth=depth,Parents=parents})
   end
  end
  while iter:Step()do
   if st:IsThreadFrameEnd()then
    for depth=st:ThreadStackDepth()-1,0,-1 do local el=iter:GetCurrentThreadStackElement(depth);if el then append(el:EnterTimerId(),depth,el:EnterTimestampFrameLocal(),st:Timestamp())end end
   elseif st:IsExit()and not st:ThreadStackWasOverflowed()then
    local depth=st:ThreadStackDepth();local first
    if st:ThreadStackIsUnderflowed()then local d=s:FetchFrameDesc(st:FrameId());first=st:IsGpuThread()and d.TickStartGpu or d.TickStartCpu
    else first=iter:GetCurrentThreadStackElement(depth):EnterTimestampFrameLocal()end
    append(st:TimerId(),depth,first,st:Timestamp())
   end
   count+=1;if count%3000==0 then task.wait()end
  end
  local rows={};for _,r in pairs(totals)do table.insert(rows,r)end;table.sort(rows,function(a,b)return a.InclusiveMs>b.InclusiveMs end)
  table.sort(spans,function(a,b)return a.Ms>b.Ms end)
  local top={};for i=1,math.min(40,#rows)do table.insert(top,rows[i])end
  local counters={};for _,id in ipairs(s:FindCounterIds('**/Luau/**|**/*gc*|**/*DataStore*'))do
   local samples=s:FetchCounterSamples(id);local selected={};for _,v in ipairs(samples)do if math.abs(v.FrameId-f.FrameId)<=1 then table.insert(selected,v)end end
   if #selected>0 then table.insert(counters,{Name=s:FetchCounterDesc(id).CounterName,Id=id,Samples=selected})end
  end
  local markers={};local ids=s:FindTimerIds('ProfilerSave*')
  if #ids>0 then
   iter:Dispose();iter=s:CreateLogIterator();iter:Configure({StartFrameId=minimum,EndFrameId=maximum,TimerIds=ids,SkipEvents=true})
   local state=iter:GetState()
   while iter:Step()do if state:IsEnter()then table.insert(markers,{Name=name(state:TimerId()),Frame=state:FrameId(),AbsoluteFrame=state:FrameAbsoluteId(),RelativeMs=(state:Timestamp()-f.TickStartCpu)*scale.TickToMsCpu})end end
  end
  return {Capture=captureIndex,Frame=f.FrameId,AbsoluteFrame=f.FrameAbsoluteId,FrameMs=f.Ms,Min=minimum,Max=maximum,Entries=count,Top=top,Spans=spans,Counters=counters,Markers=markers}
 end)
 if iter then iter:Dispose()end;s:Dispose();assert(ok,report)
 table.insert(results,report)
end
local raw=H:JSONEncode(results);local was=H.HttpEnabled;H.HttpEnabled=true
local ok,err=pcall(function()H:PostAsync('http://127.0.0.1:8820/__NAME__.json',raw,Enum.HttpContentType.ApplicationJson)end);H.HttpEnabled=was;assert(ok,err)
local compact={};for _,r in ipairs(results)do table.insert(compact,{Capture=r.Capture,Frame=r.Frame,AbsoluteFrame=r.AbsoluteFrame,FrameMs=r.FrameMs,Top={table.unpack(r.Top,1,math.min(15,#r.Top))}})end
return compact
