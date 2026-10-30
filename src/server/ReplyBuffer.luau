-- Bounded per-connection acknowledgement queue (server only).
-- Replies wait for the player's next market packet. A client that never subscribes, or stops reading,
-- keeps at most MaxReplies acknowledgements, each for at most MaxAgeSeconds. Every reply path (accepted,
-- rejected, queue-full and paused) goes through Push, so none of them can grow server memory without bound.
-- When anything is dropped the connection is marked Full: its next packet is a complete authoritative
-- snapshot (positions, orders, history, portfolio and stats) and carries RepliesDropped, so the client
-- never depends on an expired acknowledgement to learn the current state.
local ReplyBuffer={MaxReplies=64,MaxAgeSeconds=30}
ReplyBuffer.__index=ReplyBuffer
function ReplyBuffer.new(maxReplies,maxAgeSeconds)
 return setmetatable({MaxReplies=math.max(1,maxReplies or ReplyBuffer.MaxReplies),MaxAgeSeconds=maxAgeSeconds or ReplyBuffer.MaxAgeSeconds},ReplyBuffer)
end
local function drop(state,count)
 if count<=0 then return end
 local replies,times=state.Replies,state.ReplyTimes
 table.move(replies,count+1,#replies+count,1)
 table.move(times,count+1,#times+count,1)
 state.DroppedReplies=(state.DroppedReplies or 0)+count
 state.Full=true
end
function ReplyBuffer:Prune(state,now)
 state.Replies=state.Replies or {} state.ReplyTimes=state.ReplyTimes or {}
 local times,expired=state.ReplyTimes,0
 while times[expired+1] and now-times[expired+1]>self.MaxAgeSeconds do expired+=1 end
 drop(state,expired)
 return expired
end
function ReplyBuffer:Push(state,reply,now)
 self:Prune(state,now)
 drop(state,#state.Replies-self.MaxReplies+1)
 table.insert(state.Replies,reply) table.insert(state.ReplyTimes,now)
end
-- Hands the queued replies to one outgoing packet and clears the queue.
function ReplyBuffer:Take(state)
 local replies,dropped=state.Replies or {},state.DroppedReplies
 state.Replies={} state.ReplyTimes={} state.DroppedReplies=nil
 return replies,dropped
end
return ReplyBuffer
