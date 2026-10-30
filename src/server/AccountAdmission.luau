-- Per-connection admission; rejected joins never create a journal or a replacement account.
local Admission={}
function Admission.Resolve(funded,state,now,settings)
 local profile=funded:Profile(state.Uid)
 if profile then state.Admission=nil;return profile end
 local a=state.Admission or {Attempts=0,NextAt=0};state.Admission=a
 if now<a.NextAt or a.Attempts>=settings.ConnectionAttempts then return nil end
 a.Attempts+=1
 local ok,p,reason=pcall(funded.Join,funded,state.Uid)
 if ok and p then state.Admission=nil;return p end
 a.Code=ok and "AccountCapacity"or "AccountUnavailable"
 a.Reason=ok and reason or "Your account could not be opened. Please retry shortly."
 a.NextAt=now+math.min(settings.ConnectionMaxRetrySeconds,settings.ConnectionRetrySeconds*2^(a.Attempts-1))
 if not ok then warn("[Get Funded!] Account admission failed: "..tostring(p))end
 return nil
end
function Admission.Retry(state,now,settings)
 local a=state.Admission
 if not a then return true end
 if now<a.NextAt then return false,"Please wait before checking again."end
 a.Attempts=0;a.NextAt=now
 return true
end
function Admission.Status(state,now,settings)
 local a=state.Admission;if not a then return nil end
 local after=math.max(0,math.ceil(a.NextAt-now));local automatic=a.Attempts<settings.ConnectionAttempts
 return {Code=a.Code,Title=a.Code=="AccountCapacity"and "New accounts are temporarily full"or "Account temporarily unavailable",
  Message=a.Reason or "Please try again shortly.",RetryAfter=after,CanRetry=after==0,AutoRetry=automatic,Attention=true,
  Detail=automatic and "We will check again automatically. No account has been created."or "Automatic checks have stopped. Retry when you are ready; no account has been created."}
end
return Admission
