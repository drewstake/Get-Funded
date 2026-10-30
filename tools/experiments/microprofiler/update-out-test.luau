-- Only unique, disposable scratch keys; exercises the actual gameplay Script VM.
local H=game.HttpService;local E=game:GetService('EncodingService')
local scope='out-'..H:GenerateGUID(false)
local store=game.DataStoreService:GetDataStore('MarketReign_ProfilerScratch_v1',scope)
local evidence=game.ServerStorage.MicroProfilerEvidence
local b=Instance.new('BindableFunction');b.Name='MicroProfilerUpdateTest';b.Parent=game.ServerStorage
local rows={};local complete=false;local fault;local keys={}
b.OnInvoke=function(command)if command=='Cleanup'then b:Destroy();script:Destroy();return true end;return {Scope=scope,Complete=complete,Error=fault,Results=rows}end
task.spawn(function()
 local ok,err=pcall(function()
  local raw=buffer.create(1762500);local random=Random.new(9081)
  for i=0,buffer.len(raw)-4,4 do buffer.writeu32(raw,i,random:NextInteger(0,2147483647));if i%32768==0 then task.wait()end end
  local large=buffer.tostring(E:Base64Encode(raw))
  local values={large=large,small=large:sub(1,550000),buffer=raw}
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
   table.insert(rows,{Trial=trial,Kind=kind,ElapsedMs=(os.clock()-at)*1000,Calls=calls,Bytes=kind=='buffer'and buffer.len(raw)or #values[kind]})
  end end
 end)
 for _,key in ipairs(keys)do pcall(store.RemoveAsync,store,key)end
 fault=not ok and tostring(err)or nil;complete=true
end)

