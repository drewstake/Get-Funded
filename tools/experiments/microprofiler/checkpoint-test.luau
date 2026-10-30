-- Only unique, disposable scratch keys; exercises the actual gameplay Script VM.
local H=game.HttpService;local E=game:GetService('EncodingService')
local scope='checkpoint-'..H:GenerateGUID(false)
local store=game.DataStoreService:GetDataStore('MarketReign_ProfilerScratch_v1',scope)
local evidence=game.ServerStorage.MicroProfilerEvidence
local b=Instance.new('BindableFunction');b.Name='MicroProfilerUpdateTest';b.Parent=game.ServerStorage
local rows={};local complete=false;local fault;local keys={}
b.OnInvoke=function(command)if command=='Cleanup'then b:Destroy();script:Destroy();return true end;return {Scope=scope,Complete=complete,Error=fault,Results=rows}end
task.spawn(function()
 local ok,err=pcall(function()
  local real=game.DataStoreService:GetDataStore('MarketReign_Continuous_v1','Studio')
  local opts=Instance.new('DataStoreGetOptions');opts.UseCache=false
  local manifest=real:GetAsync('primary-exchange',opts)
  local slot=real:GetAsync(manifest.CheckpointRef.Key,opts);opts:Destroy()
  assert(slot.Revision==manifest.CheckpointRef.Revision and slot.WorldId==manifest.WorldId)
  local cp=slot.Checkpoint
  if cp.Codec=='zstd-base64-external'then
   local o=Instance.new('DataStoreGetOptions');o.UseCache=false;local a=real:GetAsync(cp.ArchiveRef.Key,o);o:Destroy()
   assert(a.WorldId==manifest.WorldId and a.Archive.Digest==cp.ArchiveRef.Digest)
   cp=table.clone(cp);cp.Archive=a.Archive;cp.ArchiveRef=nil;cp.Codec='zstd-base64-sections'
  end
 local binary=table.clone(cp);binary.Payload=E:Base64Decode(buffer.fromstring(cp.Payload));binary.Archive=table.clone(cp.Archive);binary.Archive.Payload=E:Base64Decode(buffer.fromstring(cp.Archive.Payload))
  local values={large=cp,small={Payload=cp.Payload},buffer=binary}
  for trial=1,3 do for _,kind in ipairs({'large','small','buffer'})do
   local key=kind..trial;table.insert(keys,key)
   store:SetAsync(key,{Small=true,TestOnly=true});task.wait(.5)
   local at=os.clock();local calls=0
   local read=store:UpdateAsync(key,function(old)
    calls+=1;debug.profilebegin('ProfilerSave.Probe.'..kind);debug.profileend()
    assert(old.Small)
    game.ServerStorage:SetAttribute('MPProbeAt',os.clock());game.ServerStorage:SetAttribute('MPProbe',scope..key)
    -- Initial value is tiny; the only large write fits the per-key budget.
    return {TestOnly=true,Finished=true,Payload=values[kind]}
   end)
   assert(read.Finished);task.wait(.1)
   table.insert(rows,{Trial=trial,Kind=kind,ElapsedMs=(os.clock()-at)*1000,Calls=calls,Bytes=#H:JSONEncode(values[kind])})
  end end
 end)
 for _,key in ipairs(keys)do pcall(store.RemoveAsync,store,key)end
 fault=not ok and tostring(err)or nil;complete=true
end)

