-- This game persists EVERY funded profile in one fenced shared-exchange checkpoint.
-- Publish a complete top-100 projection, atomically, instead of racing per-user ordered writes.
-- A lower score can evict a previous winner correctly; ties at the cutoff are deterministic.
local Ranking=require(script.Parent.LeaderboardRanking)
local Service={} Service.__index=Service
Service.RefreshSeconds=45
function Service.Scope(studio) return studio and "Studio" or "Live" end
function Service.new(options)
 options=options or {}
 return setmetatable({Store=options.Store,Studio=options.Studio,Now=options.Now or os.time,
  Cache=nil,ReadAt=0,NextRead=0,NextWrite=0,Pending=nil,Reading=false,Writing=false,Failures=0},Service)
end
function Service:_store()
 if not self.Store then self.Store=game:GetService("DataStoreService"):GetDataStore("GetFunded_BalanceLeaderboard_v1",Service.Scope(self.Studio)) end
 return self.Store
end
function Service:Queue(projection)
 if not projection or self.LastProjection==projection then return end
 self.LastProjection=projection
 if not self.Pending or projection.WorldId~=self.Pending.WorldId or projection.Sequence>self.Pending.Sequence then self.Pending=projection end
end
function Service:UseDurableProjection(projection)
 if not projection then return end
 self:Queue(projection)
 -- Already committed in the exchange. Keep the live read model correct even if its store is retrying.
 self.Cache={Version=1,WorldId=projection.WorldId,Sequence=projection.Sequence,SavedAt=projection.SavedAt,Rows=projection.Rows}
 self.ReadAt=self.Now();self.NextRead=self.Now()+Service.RefreshSeconds
end
function Service:Flush()
 local pending=self.Pending
 if self.Writing or not pending or self.Now()<self.NextWrite then return false end
 self.Writing=true
 local ok,result=pcall(function()
  return self:_store():UpdateAsync("top100",function(old)
   if old then
    assert(old.Version==1 and old.WorldId==pending.WorldId,"Leaderboard belongs to another exchange")
    if old.Sequence>=pending.Sequence then return nil end -- fences delayed/stale writers, including losses
   end
   return {Version=1,WorldId=pending.WorldId,Sequence=pending.Sequence,SavedAt=pending.SavedAt,Rows=pending.Rows}
  end)
 end)
 self.Writing=false
 if ok then
  self.Failures=0;self.WriteError=nil;self.NextWrite=self.Now()+Service.RefreshSeconds
  if self.Pending==pending then self.Pending=nil end
  if result then
   -- An overlapping read may already have seen the next owner's newer snapshot.
   if not self.Cache or (result.WorldId==self.Cache.WorldId and result.Sequence>=self.Cache.Sequence)then
    self.Cache=result;self.ReadAt=self.Now();self.NextRead=self.Now()+Service.RefreshSeconds;self.ReadError=nil
   end
  else self.NextRead=0 end
 else
  self.Failures+=1;self.WriteError=tostring(result)
  self.NextWrite=self.Now()+math.min(45,5*2^math.min(self.Failures-1,4))
 end
 return ok
end
function Service:Read()
 local now=self.Now()
 if self.Reading or now<self.NextRead then return self.Cache end
 self.Reading=true;self.NextRead=now+Service.RefreshSeconds
 local ok,record=pcall(function()return self:_store():GetAsync("top100")end)
 self.Reading=false
 if ok and record and (record.Version~=1 or type(record.Rows)~="table" or type(record.SavedAt)~="number" or type(record.Sequence)~="number") then ok=false;record="Invalid leaderboard snapshot" end
 if ok then
  -- Do not regress a cache if a read overlaps a newer successful publish.
  if not record then if not self.Cache then self.ReadAt=now end
  elseif not self.Cache or (record.WorldId==self.Cache.WorldId and record.Sequence>=self.Cache.Sequence) then self.Cache=record;self.ReadAt=now end
  self.ReadError=nil
 else self.ReadError=tostring(record);self.NextRead=now+10 end
 return self.Cache
end
function Service:Names(rows)
 self.NameCache=self.NameCache or {};self.NameRetry=self.NameRetry or 0
 local missing={}
 for _,row in ipairs(rows) do
  local cached=self.NameCache[row.UserId]
  if cached then row.Name=cached.Name;row.DisplayName=cached.DisplayName
  elseif not row.Name and row.UserId>0 then table.insert(missing,row.UserId) end
 end
 if #missing==0 or self.Now()<self.NameRetry then return end
 self.NameRetry=self.Now()+60
 local ok,infos=pcall(function()return game:GetService("UserService"):GetUserInfosByUserIdsAsync(missing)end)
 if ok then
  for _,info in ipairs(infos) do self.NameCache[info.Id]={Name=info.Username,DisplayName=info.DisplayName} end
  for _,row in ipairs(rows)do local info=self.NameCache[row.UserId];if info then row.Name=info.Name;row.DisplayName=info.DisplayName end end
 end
end
function Service:Global(own)
 self:Read()
 local record=self.Cache
 local stale=record and (self.Now()-record.SavedAt>120 or self.ReadError~=nil or self.WriteError~=nil)
 local rows={}
 for _,r in ipairs(record and record.Rows or {}) do
  local row=table.clone(r);if stale then row.Rank=nil end;table.insert(rows,row)
 end
 self:Names(rows)
 local state=not record and (self.ReadError and "Error" or "Loading") or stale and "Stale" or #rows==0 and "Empty" or "Ready"
 return {Tab="Global",State=state,Rows=rows,Your=Ranking.Standing(own,rows,record~=nil and not stale),
  SavedAt=record and record.SavedAt,RefreshSeconds=Service.RefreshSeconds,Studio=self.Studio==true}
end
function Service:Server(funded,players,player)
 local rows={}
 for _,p in ipairs(players) do table.insert(rows,Ranking.Row(funded,tostring(p.UserId),p)) end
 rows=Ranking.Sort(rows)
 local own=Ranking.Standing(Ranking.Row(funded,tostring(player.UserId),player),rows,true)
 return {Tab="Server",State=#rows==0 and "Empty" or "Ready",Rows=rows,Your=own,RefreshSeconds=10,Studio=self.Studio==true}
end
return Service
