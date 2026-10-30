-- Independent random data; unique scratch scope; no exchange state or keys.
local H=game.HttpService;local E=game:GetService('EncodingService');local scope='read-'..H:GenerateGUID(false)
local store=game.DataStoreService:GetDataStore('MarketReign_ProfilerScratch_v1',scope)
local evidence=game.ServerStorage.MicroProfilerEvidence
local b=Instance.new('BindableFunction');b.Name='MicroProfilerReadTest';b.Parent=game.ServerStorage
local rows={};local complete=false;local fault
b.OnInvoke=function(command)if command=='Cleanup'then b:Destroy();return true end;return {Scope=scope,Complete=complete,Error=fault,Results=rows}end
task.spawn(function()
 local ok,err=pcall(function()
  local raw=buffer.create(1762500);local random=Random.new(9081)
  for i=0,buffer.len(raw)-4,4 do buffer.writeu32(raw,i,random:NextInteger(0,2147483647));if i%32768==0 then task.wait()end end
  local large=buffer.tostring(E:Base64Encode(raw))
  local values={large=large,small=large:sub(1,550000),buffer=raw}
  for _,kind in ipairs({'large','small','buffer'})do store:SetAsync(kind,{Payload=values[kind],TestOnly=true})end
  for trial=1,3 do for _,kind in ipairs({'large','small','buffer'})do
   task.wait(1);local options=Instance.new('DataStoreGetOptions');options.UseCache=false
   local at=os.clock();local read=store:GetAsync(kind,options);local ms=(os.clock()-at)*1000;options:Destroy()
   assert(typeof(read.Payload)==typeof(values[kind]))
   assert((kind=='buffer'and buffer.tostring(read.Payload)==buffer.tostring(raw))or(kind~='buffer'and read.Payload==values[kind]))
   task.wait(.02);local index=evidence:Invoke('Snapshot')
   table.insert(rows,{Trial=trial,Kind=kind,ElapsedMs=ms,Capture=index,Bytes=kind=='buffer'and buffer.len(raw)or #values[kind]})
  end end
  for _,kind in ipairs({'large','small','buffer'})do store:RemoveAsync(kind)end
 end)
 fault=not ok and tostring(err)or nil;complete=true
end)
return {Started=true,Scope=scope,RealWorldWrites=false}
