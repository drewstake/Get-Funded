-- V3: a small fenced manifest selects one completed checkpoint slot. Never overwrite
-- the selected slot. Reservations survive crashes and pace every slot across owners.
-- Immutable retirement archives are written once, before any checkpoint references them.
local Http=game:GetService("HttpService")
local Lease={} Lease.__index=Lease
local function uncached(store,key)
 local options=Instance.new("DataStoreGetOptions");options.UseCache=false
 local ok,value=pcall(store.GetAsync,store,key,options);options:Destroy()
 if not ok then error(value)end
 return value
end
function Lease.new(store,settings,identity,clock)
 assert(settings.CheckpointSlots-settings.ShutdownSlots>=math.ceil(settings.CheckpointSlotSeconds/settings.SaveSeconds)+1,"Insufficient checkpoint slots for save cadence")
 assert(settings.ShutdownSlots>=1 and settings.CheckpointSlotSeconds>60,"Invalid checkpoint write budget")
 return setmetatable({Store=store,Settings=settings,Identity=identity,Now=clock or os.time,Record=nil,Owned=false,Archives={}},Lease)
end
function Lease:_authority(old,generation,step)
 return old and old.Version==3 and old.Owner==self.Identity.Token and old.Generation==generation
  and old.LeaseUntil>self.Now()and (not step or step>=old.SavedStep)
end
function Lease:StoredBytes(checkpoint)
 -- Keep the complete logical checkpoint bound, including the external archive.
 return #Http:JSONEncode({Revision=(self.Record and self.Record.CheckpointRevision or 0)+1,
  WorldId=self.Record and self.Record.WorldId or self.Identity.WorldId,Checkpoint=checkpoint})
end
local function archiveKey(settings,digest)
 assert(type(digest)=="string"and #digest==64 and not digest:find("[^0-9a-f]"),"Invalid archive digest")
 local key=settings.WorldKey..":arc:"..digest:sub(1,24)
 assert(#key<=50,"Archive key exceeds service limit")
 return key
end
local function sameArchive(a,b)
 return a and b and a.Version==b.Version and a.Codec==b.Codec and a.RawBytes==b.RawBytes
  and a.Digest==b.Digest and a.Payload==b.Payload
end
function Lease:_externalize(checkpoint,worldId)
 if checkpoint.Codec~="zstd-base64-sections"then return checkpoint end
 local archive=checkpoint.Archive
 assert(type(archive)=="table"and archive.Codec=="zstd-base64"and type(archive.Payload)=="string","Invalid retirement archive")
 local key=archiveKey(self.Settings,archive.Digest)
 local cached=self.Archives[key]
 if cached then
  assert(cached.WorldId==worldId and sameArchive(cached.Archive,archive),"Retirement archive changed under its digest")
 else
  local payload={Version=1,WorldId=worldId,Archive=archive}
  local bytes=#Http:JSONEncode(payload)
  assert(bytes+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Archive exceeds saved size limit")
  assert(math.ceil(bytes/1024)*1024<=self.Settings.CheckpointWriteBytesPerMinute,"Archive exceeds per-key write budget")
  local observed
  local result=self.Store:UpdateAsync(key,function(old)
   observed=old
   if old then
    assert(old.Version==1 and old.WorldId==worldId and sameArchive(old.Archive,archive),"Conflicting saved retirement archive")
    return nil -- Immutable: retries and new owners never rewrite this key.
   end
   return payload
  end)
  result=result or observed
  assert(result and result.Version==1 and result.WorldId==worldId and sameArchive(result.Archive,archive),"Retirement archive write was not confirmed")
  cached={WorldId=worldId,Archive=table.freeze(table.clone(archive))};self.Archives[key]=cached
 end
 local stored=table.clone(checkpoint);stored.Codec="zstd-base64-external";stored.Archive=nil
 stored.ArchiveRef={Key=key,Digest=archive.Digest,RawBytes=archive.RawBytes,Version=archive.Version}
 return stored
end
function Lease:_hydrate(checkpoint,worldId)
 if checkpoint.Codec~="zstd-base64-external"then return checkpoint end
 local ref=checkpoint.ArchiveRef
 assert(type(ref)=="table"and ref.Key==archiveKey(self.Settings,ref.Digest),"Invalid retirement archive reference")
 assert(checkpoint.Archive==nil,"Archive appears twice in checkpoint")
 local stored=uncached(self.Store,ref.Key);local archive=stored and stored.Archive
 assert(stored and stored.Version==1 and stored.WorldId==worldId and type(archive)=="table"
  and archive.Codec=="zstd-base64"and archive.Digest==ref.Digest and archive.RawBytes==ref.RawBytes
  and archive.Version==ref.Version and type(archive.Payload)=="string","Saved retirement archive is missing or differs")
 -- Decode still validates both checksums and the core-to-archive binding before use.
 local result=table.clone(checkpoint);result.Codec="zstd-base64-sections";result.ArchiveRef=nil;result.Archive=archive
 self.Archives[ref.Key]={WorldId=worldId,Archive=table.freeze(table.clone(archive))}
 return result
end
function Lease:_put(ref,checkpoint,worldId)
 assert(#ref.Key<=50,"Checkpoint key exceeds service limit")
 local payload={Revision=ref.Revision,WorldId=worldId,Checkpoint=checkpoint}
 local bytes=#Http:JSONEncode(payload)
 assert(bytes+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Checkpoint exceeds saved size limit")
 assert(math.ceil(bytes/1024)*1024<=self.Settings.CheckpointWriteBytesPerMinute,"Checkpoint exceeds per-key write budget")
 payload.Checkpoint=self:_externalize(checkpoint,worldId)
 local observed
 local result=self.Store:UpdateAsync(ref.Key,function(old)
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
function Lease:Claim()
 local observed,migration
 local function claim()
  return self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
   if old then assert(old.Version==1 or old.Version==2 or old.Version==3,"Unsupported exchange ownership record")end
   observed=old
   local now=self.Now()
   -- A competing migration or newer save may have won while exporting the blob.
   if migration and(not old or old.Version~=1 or old.WorldId~=migration.WorldId
    or old.Generation~=migration.Generation or old.SaveSequence~=migration.Sequence)then return nil end
   if old and old.LeaseUntil>now and old.Owner~=self.Identity.Token then return nil end
   -- Export V1's inline checkpoint BEFORE changing its reference. Returning nil
   -- here reads the old record without charging another full-value write.
   if old and old.Version==1 and old.Checkpoint then
    if not migration then return nil end
   end
   local record=old and table.clone(old)or{WorldId=self.Identity.WorldId,Generation=0,SaveSequence=0,SavedStep=0}
   if record.Owner~=self.Identity.Token or record.Version==1 then record.Generation+=1 end
   record.Version=3;record.CheckpointRevision=record.CheckpointRevision or 0
   record.SlotWriteAfter=record.SlotWriteAfter or {}
   if migration then record.CheckpointRef=migration.Ref;record.Checkpoint=nil end
   record.Owner=self.Identity.Token;record.JobId=self.Identity.JobId;record.PlaceId=self.Identity.PlaceId
   record.LeaseUntil=now+self.Settings.LeaseSeconds
   return record
  end)
 end
 local result=claim()
 if not result and observed and observed.Version==1 and observed.Checkpoint
  and(observed.LeaseUntil<=self.Now()or observed.Owner==self.Identity.Token)then
  local ref={Key=self.Settings.WorldKey..":legacy:"..observed.Generation..":"..observed.SaveSequence,Revision=0,Slot=0}
  migration={WorldId=observed.WorldId,Generation=observed.Generation,Sequence=observed.SaveSequence,Ref=ref}
  self:_put(ref,observed.Checkpoint,observed.WorldId)
  result=claim()
 end
 self.Record=result or observed
 self.Owned=result~=nil and result.Owner==self.Identity.Token
 return self.Owned,self.Record
end
function Lease:ReadCheckpoint()
 local record=assert(self.Record,"Missing ownership record")
 if record.Checkpoint then return record.Checkpoint end -- Read-only compatibility.
 local ref=record.CheckpointRef
 if not ref then assert(record.SavedStep==0 and record.SaveSequence==0,"Saved checkpoint is missing");return nil end
 assert(type(ref.Key)=="string"and #ref.Key<=50 and type(ref.Revision)=="number","Invalid checkpoint reference")
 local blob=uncached(self.Store,ref.Key)
 assert(blob and blob.WorldId==record.WorldId and blob.Revision==ref.Revision and type(blob.Checkpoint)=="table","Saved checkpoint is missing or its revision differs")
 return self:_hydrate(blob.Checkpoint,record.WorldId)
end
function Lease:Valid()
 return self.Owned and self.Record~=nil and self.Now()<self.Record.LeaseUntil-self.Settings.SafetySeconds
end
function Lease:Renew()
 assert(self.Owned and self.Record,"This server does not own the exchange")
 local generation=self.Record.Generation
 local result=self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
  if not self:_authority(old,generation)then return nil end
  local record=table.clone(old);record.LeaseUntil=self.Now()+self.Settings.LeaseSeconds;return record
 end)
 if not result then self.Owned=false;error("Exchange ownership changed; lease renewal rejected")end
 self.Record=result;return true
end
function Lease:_slot(record,release)
 local count=self.Settings.CheckpointSlots
 local routine=count-self.Settings.ShutdownSlots
 local ready=math.huge;local now=self.Now()
 -- Final saves try the reserved slots first, then any available routine slot.
 for n=1,(release and count or routine)do
  local slot=release and ((routine+n-1)%count)+1 or n
  local after=(record.SlotWriteAfter or {})[tostring(slot)]or 0
  if not record.CheckpointRef or record.CheckpointRef.Slot~=slot then
   if after<=now then return slot,now end
   ready=math.min(ready,after)
  end
 end
 return nil,ready
end
function Lease:CanCommit(release)
 if not self.Owned or not self.Record or self.Record.LeaseUntil<=self.Now()then return false,math.huge end
 local slot,ready=self:_slot(self.Record,release)
 return slot~=nil,ready
end
function Lease:Commit(checkpoint,step,release)
 assert(self.Owned and self.Record,"This server does not own the exchange")
 assert(type(checkpoint)=="table"and type(step)=="number","A complete checkpoint is required")
 local ready,at=self:CanCommit(release);self.WriteReadyAt=at
 assert(ready,"Checkpoint write budget is cooling down; retry after "..tostring(at))
 local generation=self.Record.Generation
 local result=self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
  if not self:_authority(old,generation,step)then return nil end
  local slot=self:_slot(old,release);if not slot then return nil end
  local record=table.clone(old)
  record.CheckpointRevision+=1
  record.PendingRef={Key=self.Settings.WorldKey..":cp:"..slot,Slot=slot,Revision=record.CheckpointRevision}
  record.SlotWriteAfter=table.clone(old.SlotWriteAfter)
  record.SlotWriteAfter[tostring(slot)]=self.Now()+self.Settings.CheckpointSlotSeconds
  record.LeaseUntil=self.Now()+self.Settings.LeaseSeconds
  return record
 end)
 if not result then self.Owned=false;error("Exchange ownership changed; stale checkpoint rejected")end
 self.Record=result
 local ref=result.PendingRef
 self:_put(ref,checkpoint,result.WorldId)
 -- Only this small atomic publication makes staged data durable/visible. A failed
 -- or delayed staging write cannot change the previous committed reference.
 result=self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
  if not self:_authority(old,generation,step)or not old.PendingRef or old.PendingRef.Revision~=ref.Revision then return nil end
  local record=table.clone(old)
  record.CheckpointRef=ref;record.PendingRef=nil;record.Checkpoint=nil
  record.SavedStep=step;record.SavedAt=self.Now();record.SaveSequence+=1
  record.SlotWriteAfter=table.clone(old.SlotWriteAfter)
  record.SlotWriteAfter[tostring(ref.Slot)]=self.Now()+self.Settings.CheckpointSlotSeconds
  record.LeaseUntil=release and 0 or self.Now()+self.Settings.LeaseSeconds
  if release then record.Owner="";record.JobId=""end
  return record
 end)
 if not result then self.Owned=false;error("Exchange ownership changed; stale checkpoint rejected")end
 self.Record=result;self.Owned=not release
 return result
end
return Lease
