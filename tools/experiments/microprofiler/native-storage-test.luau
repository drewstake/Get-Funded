-- Inert payloads in a unique test-only DataStore scope. No trading or world data.
local H=game.HttpService;local scope='probe-'..H:GenerateGUID(false)
local store=game.DataStoreService:GetDataStore('MarketReign_ProfilerScratch_v1',scope)
local evidence=game.ServerStorage.MicroProfilerEvidence
local b=Instance.new('BindableFunction');b.Name='MicroProfilerStorageTest';b.Parent=game.ServerStorage
local results={};local complete=false;local fault
b.OnInvoke=function(command)
 if command=='Cleanup'then b:Destroy();return true end
 return {Scope=scope,Complete=complete,Error=fault,Results=results}
end
task.spawn(function()
 local ok,err=pcall(function()
  for index,bytes in ipairs({2350000,550000,2350000,550000,2350000,550000})do
   task.wait(1);local captured
   local payload={Payload=string.rep('Az+0/xY',math.floor(bytes/7)),TestOnly=true}
   local started=os.clock()
   store:UpdateAsync('size-'..index,function()
    debug.profilebegin('ProfilerSave.Probe'..index);debug.profileend()
    task.delay(.04,function()captured=evidence:Invoke('Snapshot')end)
    return payload
   end)
   table.insert(results,{Trial=index,Bytes=#payload.Payload,ElapsedMs=(os.clock()-started)*1000,Capture=captured})
   -- Remove only the key created above in this unique scratch scope.
   store:RemoveAsync('size-'..index)
  end
 end)
 fault=not ok and tostring(err)or nil;complete=true
end)
return {Started=true,Scope=scope,RealWorldWrites=false}
