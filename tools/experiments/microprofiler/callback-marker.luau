local Http=game.HttpService
local root=script.Parent;local L=require(root.WorldLease);local original=L._put
function L:_put(ref,checkpoint,worldId)
 assert(#ref.Key<=50,"Checkpoint key exceeds service limit")
 local payload={Revision=ref.Revision,WorldId=worldId,Checkpoint=checkpoint}
 local bytes=#Http:JSONEncode(payload)
 assert(bytes+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Checkpoint exceeds saved size limit")
 assert(math.ceil(bytes/1024)*1024<=self.Settings.CheckpointWriteBytesPerMinute,"Checkpoint exceeds per-key write budget")
 payload.Checkpoint=self:_externalize(checkpoint,worldId)
 local observed
 local result=self.Store:UpdateAsync(ref.Key,function(old)
  debug.profilebegin('ProfilerSave.SlotTransform');debug.profileend();game.ServerStorage:SetAttribute('MPProbe',tostring(os.clock()))
  observed=old
  -- Fences a delayed write after another owner has reused this slot. Migration
  -- retries at revision zero are read-only when the identical revision exists.
  if old then
   assert(old.WorldId==worldId,"Checkpoint slot belongs to a different world")
   if old.Revision>=ref.Revision then return nil end
  end
  return payload
 end)
 result=result or observed
 assert(result and result.Revision==ref.Revision and result.WorldId==worldId,"Stale checkpoint-slot write rejected")
end
local b=Instance.new('BindableFunction');b.Name='MicroProfilerCallbackMarker';b.Parent=root;b.OnInvoke=function()L._put=original;b:Destroy();script:Destroy();return true end
