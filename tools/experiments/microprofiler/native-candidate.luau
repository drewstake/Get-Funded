-- Real native storage operations on a detached copy, in a unique disposable scope.
local H=game.HttpService
local scope='candidate-'..H:GenerateGUID(false)
local store=game.DataStoreService:GetDataStore('MarketReign_ProfilerScratch_v1',scope)
local keys={};local rows={};local complete=false;local fault;local current;local serial=0
local b=Instance.new('BindableFunction');b.Name='MicroProfilerCandidateTest';b.Parent=game.ServerStorage
b.OnInvoke=function(command)
 if command=='Cleanup'then b:Destroy();script.Parent:Destroy();return true end
 return {Scope=scope,Complete=complete,Error=fault,Rows=rows}
end
task.spawn(function()
 local ok,err=pcall(function()
  local real=game.DataStoreService:GetDataStore('MarketReign_Continuous_v1','Studio')
  local options=Instance.new('DataStoreGetOptions');options.UseCache=false
  local manifest=real:GetAsync('primary-exchange',options)
  local blob=real:GetAsync(manifest.CheckpointRef.Key,options);options:Destroy()
  assert(blob.Revision==manifest.CheckpointRef.Revision and blob.WorldId==manifest.WorldId)
  local cp=blob.Checkpoint
  if cp.Codec=='zstd-base64-external'then
   local o=Instance.new('DataStoreGetOptions');o.UseCache=false;local a=real:GetAsync(cp.ArchiveRef.Key,o);o:Destroy()
   assert(a.WorldId==manifest.WorldId and a.Archive.Digest==cp.ArchiveRef.Digest)
   cp=table.clone(cp);cp.Archive=a.Archive;cp.ArchiveRef=nil;cp.Codec='zstd-base64-sections'
  end
  local proxy={}
  function proxy:GetAsync(...)return store:GetAsync(...)end
  function proxy:UpdateAsync(key,callback)
   keys[key]=true;local row={Kind=key:find(':arc:',1,true)and 'archive'or key:find(':cp:',1,true)and 'slot'or 'manifest',Variant=current,Key=key}
   local at=os.clock();local result=store:UpdateAsync(key,function(old)
    local value=callback(old)
    if value then
     row.Bytes=#H:JSONEncode(value)
     if row.Kind~='manifest'then
      serial+=1;debug.profilebegin('ProfilerSave.Detached.'..current..'.'..row.Kind);debug.profileend()
      game.ServerStorage:SetAttribute('MPProbeAt',os.clock());game.ServerStorage:SetAttribute('MPProbe',scope..serial)
     end
    end
    return value
   end)
   row.ElapsedMs=(os.clock()-at)*1000;table.insert(rows,row);return result
  end
  for _,variant in ipairs({'Baseline','Candidate'})do
   current=variant
   local Lease=require(script.Parent[variant]);local settings=table.clone(require(game.ServerScriptService.MarketReign.WorldConfig));settings.WorldKey=variant:lower()
   local lease=Lease.new(proxy,settings,{Token=scope..variant,WorldId=manifest.WorldId,JobId='scratch',PlaceId=game.PlaceId})
   assert(lease:Claim())
   for i=1,3 do lease:Commit(cp,manifest.SavedStep,i==3);task.wait(1)end
   local resumed=Lease.new(proxy,settings,{Token=scope..variant..'restart',WorldId='must-not-replace',JobId='scratch',PlaceId=game.PlaceId})
   assert(resumed:Claim());local restored=resumed:ReadCheckpoint()
   assert(restored.Payload==cp.Payload and restored.Archive.Payload==cp.Archive.Payload and restored.Digest==cp.Digest and restored.Archive.Digest==cp.Archive.Digest)
   resumed:Commit(restored,manifest.SavedStep,true);task.wait(1)
  end
 end)
 for key in pairs(keys)do local removed,message=pcall(store.RemoveAsync,store,key);if not removed then err=tostring(err)..'; cleanup '..key..': '..tostring(message);ok=false end end
 fault=not ok and tostring(err)or nil;complete=true
end)
