-- One durable record owns both the checkpoint and its writer lease. UpdateAsync fences stale servers.
local Lease={} Lease.__index=Lease
function Lease.new(store,settings,identity,clock)
 return setmetatable({Store=store,Settings=settings,Identity=identity,Now=clock or os.time,Record=nil,Owned=false},Lease)
end
function Lease:Claim()
 local observed
 local result=self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
  if old then assert(old.Version==1,"Unsupported exchange ownership record")end
  observed=old
  local now=self.Now()
  if old and old.LeaseUntil>now and old.Owner~=self.Identity.Token then return nil end
  local nextRecord=old and table.clone(old)or{Version=1,WorldId=self.Identity.WorldId,Generation=0,SaveSequence=0,SavedStep=0}
  if nextRecord.Owner~=self.Identity.Token then nextRecord.Generation+=1 end
  nextRecord.Owner=self.Identity.Token nextRecord.JobId=self.Identity.JobId nextRecord.PlaceId=self.Identity.PlaceId
  nextRecord.LeaseUntil=now+self.Settings.LeaseSeconds
  return nextRecord
 end)
 self.Record=result or observed
 self.Owned=result~=nil and result.Owner==self.Identity.Token
 return self.Owned,self.Record
end
function Lease:Valid()
 return self.Owned and self.Record~=nil and self.Now()<self.Record.LeaseUntil-self.Settings.SafetySeconds
end
function Lease:Commit(checkpoint,step,release)
 assert(self.Owned and self.Record,"This server does not own the exchange")
 assert(type(checkpoint)=="table"and type(step)=="number","A complete checkpoint is required")
 local generation=self.Record.Generation
 local result=self.Store:UpdateAsync(self.Settings.WorldKey,function(old)
  local now=self.Now()
  if not old or old.Owner~=self.Identity.Token or old.Generation~=generation or old.LeaseUntil<=now or step<old.SavedStep then return nil end
  local nextRecord=table.clone(old)
  nextRecord.Checkpoint=checkpoint nextRecord.SavedStep=step nextRecord.SavedAt=now nextRecord.SaveSequence+=1
  nextRecord.LeaseUntil=release and 0 or now+self.Settings.LeaseSeconds
  if release then nextRecord.Owner="" nextRecord.JobId=""end
  return nextRecord
 end)
 if not result then self.Owned=false;error("Exchange ownership changed; stale checkpoint rejected")end
 self.Record=result self.Owned=not release
 return result
end
return Lease
