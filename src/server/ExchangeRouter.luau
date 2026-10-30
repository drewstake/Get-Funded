-- Limited-launch transfer state machine. No storage, player accounts, or destinations from clients.
-- TeleportInitFailed supplies a NEW TeleportOptions object; correlate its server-set attempt data.
local Router={} Router.__index=Router
function Router.new(settings,options)
 return setmetatable({Settings=settings,Options=options,States={},Sequence=0},Router)
end
function Router:_target()
 local o=self.Options;local owner=o.Owner()
 if o.Studio or o.Mode()~="Following"or type(owner)~="table"then return nil end
 if type(owner.LeaseUntil)~="number"or owner.LeaseUntil~=owner.LeaseUntil or owner.LeaseUntil==math.huge or owner.LeaseUntil<=o.WallTime()+self.Settings.SafetySeconds
  or type(owner.PlaceId)~="number"or owner.PlaceId<1 or owner.PlaceId%1~=0
  or type(owner.JobId)~="string"or owner.JobId==""or owner.JobId==o.JobId
  or type(owner.WorldId)~="string"or type(owner.Owner)~="string"or type(owner.Generation)~="number"or owner.Generation%1~=0 then return nil end
 return {PlaceId=owner.PlaceId,JobId=owner.JobId,
  Key=table.concat({owner.WorldId or "",owner.Generation or 0,owner.Owner or "",owner.PlaceId,owner.JobId},":")}
end
function Router:_state(player)
 local s=self.States[player]
 if not s then s={Attempts=0,NextAt=0,ManualAt=0,Code="WaitingOwner"};self.States[player]=s end
 return s
end
function Router:Forget(player)self.States[player]=nil end
function Router:_failure(player,pending,code)
 local s=self.States[player]
 if not s or s.Pending~=pending then return end
 -- A failure event can arrive while TeleportAsync is still yielding. Keep its
 -- guard until that call returns, then start the normal failure backoff.
 if pending.Running then pending.FailureCode=code;return end
 s.Pending=nil;s.Code=code
 local base=code=="ServerFull"and self.Settings.ConnectionFullRetrySeconds or self.Settings.ConnectionRetrySeconds
 s.NextAt=self.Options.Now()+math.min(self.Settings.ConnectionMaxRetrySeconds,base*2^(s.Attempts-1))
 -- Access/invalid-destination errors need an explicit retry or a new owner, not a loop.
 if code=="TransferUnavailable"then s.Attempts=self.Settings.ConnectionAttempts end
end
function Router:Failed(player,result,placeId,jobId,attempt)
 local s=self.States[player];local p=s and s.Pending
 if not p or p.Id~=attempt or p.Target.PlaceId~=placeId or p.Target.JobId~=jobId then return false end
 local target=self:_target()
 if not target or target.Key~=p.Target.Key then return false end
 if result=="IsTeleporting"then return true end -- Preserve the in-flight transfer until completion/watchdog.
 local code=result=="GameFull"and "ServerFull"or(result=="Unauthorized"or result=="GameNotFound")and "TransferUnavailable"or "TransferFailed"
 self:_failure(player,p,code);return true
end
function Router:Step(player)
 local o=self.Options
 if not o.Connected(player)then self:Forget(player);return end
 -- Do not start a second API call while the first is still yielding. Once it
 -- returns, an absent failure/removal event is recovered by the watchdog.
 -- Temporary world-mode changes must also retain this physical-call guard.
 local s=self.States[player]
 if s and s.Pending and s.Pending.Running then return end
 if o.Mode()~="Following"then self:Forget(player);return end
 s=s or self:_state(player);local now=o.Now();local target=self:_target()
 if not target then s.Pending=nil;s.Target=nil;s.Code=o.Studio and "StudioTransfer"or "WaitingOwner";return end
 if s.Target~=target.Key then
  s.Target=target.Key;s.Attempts=0;s.NextAt=now;s.Pending=nil;s.Code="Connecting"
 end
 if s.Pending then
  if now-s.Pending.At>=self.Settings.ConnectionAttemptSeconds then self:_failure(player,s.Pending,"TransferDelayed")end
  return
 end
 if now<s.NextAt or s.Attempts>=self.Settings.ConnectionAttempts then return end
 if now<(self.NextDispatch or 0)then return end
 self.NextDispatch=now+self.Settings.ConnectionRouteSpacingSeconds
 self.Sequence+=1;s.Attempts+=1
 local pending={Id=tostring(self.Sequence),At=now,Target=target,Running=true}
 s.Pending=pending;s.Code="Transferring"
 o.Spawn(function()
  local current=self:_target()
  if self.States[player]~=s or s.Pending~=pending or not o.Connected(player)or not current or current.Key~=target.Key then
   if self.States[player]==s and s.Pending==pending then s.Pending=nil end
   return
  end
  local ok,err=pcall(o.Teleport,player,target,pending.Id)
  pending.Running=false
  if pending.FailureCode then self:_failure(player,pending,pending.FailureCode)
  elseif not ok then
   self:_failure(player,pending,"TransferFailed")
  end
  if not ok then
   if o.Warn then o.Warn(tostring(err))end
  end
 end)
end
function Router:Retry(player)
 local s=self:_state(player);local now=self.Options.Now()
 if s.Pending or now<s.NextAt or now<s.ManualAt then return false,"Please wait before checking again."end
 s.Attempts=0;s.NextAt=now;s.ManualAt=now+self.Settings.ConnectionManualRetrySeconds
 self:Step(player);return true,"Checking the shared exchange."
end
function Router:Status(player)
 local s=self:_state(player);local now=self.Options.Now();local code=s.Code
 local titles={WaitingOwner="Waiting for the shared exchange",StudioTransfer="Another Studio test owns the exchange",
  Connecting="Connecting to the shared exchange",Transferring="Joining the trading server",ServerFull="The trading server is full",
  TransferFailed="Could not join the trading server",TransferDelayed="The transfer is taking too long",TransferUnavailable="The trading server is unavailable"}
 local messages={WaitingOwner="The trading server is restarting or unavailable. Your saved progress stays on the shared exchange.",
  StudioTransfer="Stop the other Studio test before connecting here. Studio cannot teleport players.",
  Transferring="A transfer is in progress. Your saved account will open on the shared trading server.",
  ServerFull="This launch has one trading server with room for "..self.Settings.LaunchMaxPlayers.." players. Please wait for a space or try again later.",
  TransferFailed="The transfer failed. Your saved account has not changed.",
  TransferDelayed="Roblox has not completed the transfer. Your saved account has not changed.",
  TransferUnavailable="The destination could not be joined. Try again later or rejoin the experience."}
 if s.Pending and s.Pending.Running and now-s.Pending.At>=self.Settings.ConnectionAttemptSeconds then code="TransferDelayed"end
 local waiting=code=="WaitingOwner"or code=="StudioTransfer"
 local after=math.max(0,math.ceil(math.max(s.NextAt,s.ManualAt)-now))
 local automatic=not waiting and not s.Pending and s.Attempts<self.Settings.ConnectionAttempts
 return {Code=code,Title=titles[code]or "Connecting to the shared exchange",Message=messages[code]or "Preparing your connection.",
  Attention=code~="Connecting"and code~="Transferring",RetryAfter=after,CanRetry=not waiting and not s.Pending and after==0,
  AutoRetry=automatic,Detail=code=="ServerFull"and(automatic and "We will check again automatically. Waiting does not reserve a place."or "Automatic retries stopped. Use Retry; waiting does not reserve a place.")
   or s.Pending and(code=="TransferDelayed"and "The transfer is still pending. You can leave and rejoin if it does not finish."or "Please wait for this transfer to finish.")or waiting and "We are checking for an available owner."
   or automatic and "We will retry automatically."or "Automatic retries have stopped. Use Retry to check again."}
end
return Router
