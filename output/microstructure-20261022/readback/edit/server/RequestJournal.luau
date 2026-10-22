-- Persisted per-player request session/high-water mark. Evicting old replies never
-- makes an old id executable again. Reconnect retires the previous session.
local Journal={MaxReplies=128}
function Journal.Open(e,uid)
 e.RequestJournal=e.RequestJournal or {}
 local old=e.RequestJournal[uid]
 local state={Session=(old and old.Session or 0)+1,High=0,Replies={},Order={}}
 e.RequestJournal[uid]=state
 return state.Session
end
function Journal.Begin(e,uid,session,id)
 local state=e.RequestJournal and e.RequestJournal[uid]
 if not state or session~=state.Session then return false,nil,'Connection changed. Refresh the account before submitting a new request.'end
 local cached=state.Replies[tostring(id)]
 if cached then return false,cached end
 if id<=state.High then return false,nil,'Request already processed. Check the authoritative account snapshot.'end
 state.High=id -- consumed before any mutation; a retry cannot repeat a partial failure
 return true
end
function Journal.Finish(e,uid,session,id,result)
 local state=e.RequestJournal and e.RequestJournal[uid]
 if not state or state.Session~=session then return end
 local key=tostring(id)
 if not state.Replies[key]then table.insert(state.Order,key)end
 state.Replies[key]=result
 if #state.Order>Journal.MaxReplies then state.Replies[table.remove(state.Order,1)]=nil end
end
function Journal.Cached(e,uid,session,id)
 local state=e and e.RequestJournal and e.RequestJournal[uid]
 return state and state.Session==session and state.Replies[tostring(id)]or nil
end
return Journal
