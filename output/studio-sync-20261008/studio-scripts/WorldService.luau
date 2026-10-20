-- A single shared exchange. Follower servers route players to its owner instead of creating another tape.
local RunService=game:GetService("RunService")
local Http=game:GetService("HttpService")
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Lease=require(script.Parent.WorldLease)
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Settings=require(script.Parent.WorldConfig)
local World={} World.__index=World
function World.new(config,options)
 options=options or {}
 local studio=options.Studio if studio==nil then studio=RunService:IsStudio()end
 local self=setmetatable({Config=config,Settings=options.Settings or Settings,Studio=studio,
  PlaceId=options.PlaceId or game.PlaceId,JobId=options.JobId or game.JobId,Now=options.Now or os.time,
  Mode="Connecting",Status="Connecting to the shared exchange",Busy=false,Closing=false,
  Healthy=false,NextSave=0,NextAttempt=0,Epoch=0,Store=options.Store},World)
 self.Identity={Token=Http:GenerateGUID(false),WorldId=Http:GenerateGUID(false),JobId=self.JobId,PlaceId=self.PlaceId}
 -- Private servers cannot be public teleport destinations. They only act as entry lobbies.
 self.CanOwn=options.CanOwn if self.CanOwn==nil then self.CanOwn=studio or game.PrivateServerId==""end
 return self
end
function World:_fresh()
 local seed=self.Studio and self.Settings.StudioReplaySeed or 0
 seed=seed or 0
 if seed==0 then seed=tonumber(Http:GenerateGUID(false):sub(1,8),16)%2147483646+1 end
 local engine=Engine.new(self.Config,seed) local population=Participants.new(engine)
 for i=1,math.floor(self.Config.WarmupSeconds/self.Config.StepSeconds)do
  population:Step() if i%200==0 then task.wait()end
 end
 return engine,population
end
function World:_encode(engine,population)
 engine=engine or self.Engine;population=population or self.Population
 local projection
 if self.CaptureProjection then
  -- Optional read model failures must never prevent an exchange save or trading.
  local ok,result=pcall(self.CaptureProjection,engine)
  if ok then projection=result else warn("[Get Funded!] Leaderboard projection unavailable: "..tostring(result)) end
 end
 -- Raw size is refused by Encode (before compression) with exactly the bound the reader enforces.
 local record=Checkpoint.Encode(Checkpoint.Capture(engine,population),Checkpoint.MaxDecodedBytes)
 -- Measure the complete value UpdateAsync will store: lease fields plus this checkpoint, with headroom.
 local stored=self:_storedBytes(record,engine.Step)
 assert(stored+(self.Settings.RecordHeadroomBytes or 0)<=self.Settings.MaxEncodedBytes,"Exchange checkpoint is too large; trading paused to protect saved state")
 self.LastRawBytes=record.RawBytes self.LastStoredBytes=stored
 return record,engine.Step,projection
end
function World:_storedBytes(record,step)
 local lease=self.Lease and self.Lease.Record
 local shell=lease and table.clone(lease) or {Version=1,WorldId=self.Identity.WorldId,Generation=1,SaveSequence=0}
 local now=self.Now()
 shell.Owner=self.Identity.Token shell.JobId=self.Identity.JobId shell.PlaceId=self.Identity.PlaceId
 shell.Checkpoint=record shell.SavedStep=step or self.Engine.Step shell.SavedAt=now
 shell.SaveSequence=(shell.SaveSequence or 0)+1 shell.LeaseUntil=now+self.Settings.LeaseSeconds
 return #Http:JSONEncode(shell)
end
-- False once the last saved checkpoint used the configured fraction of either size limit. Only new accounts
-- wait; trading and saving continue, and the unused room absorbs growth of the accounts that already exist.
-- kind "Start"/"Activate" (a first account or an earned tier) may use the band up to NewAccountCapacityFraction.
function World:HasCapacity(kind)
 local fraction=self.Settings.CapacityFraction or 0.8
 if kind=="Start" then fraction=math.max(fraction,self.Settings.NewAccountCapacityFraction or fraction) end
 if (self.LastRawBytes or 0)>=Checkpoint.MaxDecodedBytes*fraction then return false end
 if (self.LastStoredBytes or 0)>=self.Settings.MaxEncodedBytes*fraction then return false end
 return true
end
function World:_committed(rows)
 if not rows then return end
 local r=self.Lease.Record
 self.DurableProjection={Rows=rows,WorldId=r.WorldId,Sequence=r.SaveSequence,SavedAt=r.SavedAt}
end
function World:_sandbox(reason)
 self.Engine,self.Population=self:_fresh()
 self.Mode="Local" self.Status="LOCAL · NOT SAVED" self.Healthy=true self.Epoch+=1
 warn("[Get Funded!] Unsaved Studio sandbox: "..reason.." Publish a test experience and enable Studio API access for restart continuity.")
end
function World:Open()
 if self.Closing or self.Busy then return end
 self.Busy=true
 local ok,err=pcall(function()
  if not self.Settings.Enabled or self.PlaceId==0 then
   assert(self.Studio and self.Settings.AllowUnsavedStudio,"Persistent storage is required for the live exchange")
   self:_sandbox(self.PlaceId==0 and "This place is unpublished." or "Persistence is disabled.") return
  end
  if not self.Store then
   self.Store=game:GetService("DataStoreService"):GetDataStore(self.Settings.StoreName,self.Studio and "Studio" or "Live")
  end
  self.Lease=self.Lease or Lease.new(self.Store,self.Settings,self.Identity,self.Now)
  local owned,record
  if self.CanOwn then owned,record=self.Lease:Claim()
  else owned=false record=self.Store:GetAsync(self.Settings.WorldKey)end
  if not owned then
   self.Owner=record self.Mode="Following" self.Healthy=false
   self.Status=self.Studio and "Shared Studio exchange is active in another test; stop it before restarting here" or "Joining the shared exchange"
   return
  end
  self.Mode="Loading" self.Status="Restoring the saved exchange"
  -- Everything restored from the store is durable; no in-memory receipt or transaction from a previous engine survives.
  if record.Checkpoint then
   self.Engine,self.Population=Checkpoint.Restore(Checkpoint.Decode(record.Checkpoint),self.Config)
   assert(self.Engine.Step==record.SavedStep,"Checkpoint step does not match ownership record")
  else
   assert(record.SavedStep==0,"Saved exchange checkpoint is missing")
   self.Engine,self.Population=self:_fresh()
  end
  -- No client trades until the initial/loaded state has a confirmed durable checkpoint.
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,false)
  self:_committed(projection)
  self.Mode="Shared" self.Status="SHARED · SAVED" self.Healthy=true self.Epoch+=1
  self.NextSave=self.Now()+self.Settings.SaveSeconds
 end)
 self.Busy=false self.NextAttempt=self.Now()+self.Settings.RetrySeconds
 if not ok then
  -- Transient storage failures or corrupt checkpoints must never silently reset an existing market.
  self.Healthy=false self.Mode="Unavailable" self.Status="Saved exchange unavailable · retrying safely"
  self.LastError=tostring(err) warn("[Get Funded!] "..self.LastError)
 end
end
function World:CanRun()
 if self.Closing or self.Transaction or not self.Healthy or not self.Engine then return false end
 return self.Mode=="Local" or (self.Mode=="Shared" and self.Lease:Valid())
end
function World:Label()
 if self.Mode=="Shared" and not self:CanRun()then return "PAUSED · WAITING FOR SAVED EXCHANGE"end
 return self.Status
end
function World:Save(release)
 if self.Busy or not self.Engine or self.Mode~="Shared" then return false end
 self.Busy=true
 local ok,err=pcall(function()
  local encoded,step,projection=self:_encode()
  self.Lease:Commit(encoded,step,release)
  self:_committed(projection)
 end)
 self.Busy=false self.NextSave=self.Now()+(ok and self.Settings.SaveSeconds or self.Settings.RetrySeconds)
 self.Healthy=ok and not release
 if not ok then self.LastError=tostring(err) warn("[Get Funded!] Save failed; exchange paused: "..self.LastError)end
 return ok
end
-- Freeze execution, transform a detached copy, then swap only after the fenced save confirms it.
-- A timed-out write may have committed: reload durable storage instead of overwriting it with old data.
function World:TransformSaved(transform)
 if self.Busy or self.Mode~="Shared" or not self:CanRun()then return false,"Exchange is not ready."end
 self.Busy=true;self.Transaction=true
 local rawBytes,storedBytes=self.LastRawBytes,self.LastStoredBytes
 local attemptedCommit=false local result
 local ok,err=pcall(function()
  local engine,population=Checkpoint.Restore(Checkpoint.Capture(self.Engine,self.Population),self.Config)
  result=transform(engine,population);engine:Audit()
  local encoded,step,projection=self:_encode(engine,population)
  assert(not self.CaptureProjection or projection,"Cannot transform saved data without its leaderboard projection")
  attemptedCommit=true;self.Lease:Commit(encoded,step,false)
  self.Engine=engine;self.Population=population;self.Epoch+=1
  self:_committed(projection)
 end)
 self.Busy=false;self.Transaction=false
 self.NextSave=self.Now()+self.Settings.SaveSeconds
 if not ok then
  self.LastRawBytes=rawBytes;self.LastStoredBytes=storedBytes
  self.LastError=tostring(err)
  if attemptedCommit then
   self.Healthy=false;self.Mode="Unavailable";self.Status="Verifying the saved exchange"
   self.Engine=nil;self.Population=nil;self.Epoch+=1
   self.NextAttempt=self.Now()+self.Settings.RetrySeconds
  end
  warn("[Get Funded!] Saved transformation failed: "..self.LastError)
 end
 return ok,ok and result or tostring(err)
end
function World:Maintain()
 if self.Closing or self.Busy or self.Mode=="Local"then return end
 local now=self.Now()
 if self.Mode=="Shared"then
  if not self.Lease.Owned or now>=self.Lease.Record.LeaseUntil then
   -- Discard unsaved state after loss of authority. Reacquire and restore the durable record.
   self.Healthy=false self.Mode="Unavailable" self.Status="Reconnecting to the saved exchange"
   self.Engine=nil self.Population=nil self.Epoch+=1 self.NextAttempt=now
  elseif now>=self.NextSave then self:Save(false) return end
 end
 if self.Mode~="Shared" and now>=self.NextAttempt then self:Open()end
end
function World:Close()
 self.Closing=true
 -- A save already in flight finishes before the final frozen checkpoint and lease release.
 local deadline=os.clock()+24
 while self.Busy and os.clock()<deadline do task.wait(0.05)end
 if not self.Busy and self.Mode=="Shared" and self.Lease.Owned then
  repeat
   if self:Save(true)then return true end
   if not self.Lease.Owned or self.Now()>=self.Lease.Record.LeaseUntil then break end
   task.wait(1)
  until os.clock()>=deadline
 end
 return self.Mode=="Local"
end
return World
