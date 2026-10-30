-- No real DataStores, player data, purchases or running Studio worlds.
local Lease=require(script.Parent.WorldLease)
local Settings=require(script.Parent.WorldConfig)
local Fake=require(script.Parent.TestDataStore)
local World=require(script.Parent.WorldService)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local F=require(script.Parent.FundedAccounts)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function same(a,b)
 assert(type(a)==type(b),"Different types")
 if type(a)~="table"then assert(a==b,"Different values");return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Extra key")end
end
local function fixture()
 local clock={Now=1000};local now=function()return clock.Now end;local s=Fake.new(now);s.EnforceBudget=true
 local function owner(id)return Lease.new(s,Settings,{Token=id,WorldId=id,JobId=id,PlaceId=1},now)end
 return clock,s,owner
end
local function large(n)return {Payload=string.rep("x",n or 3500000),Version=24,Marker="preserved"}end
local function sectioned()
 local archive=CP.Encode({History={{Price=123.25}},Accounts={{Balance=23456.75,Position=-7}}})
 local cp=CP.Encode({Engine={},ArchiveDigest=archive.Digest,ArchiveRawBytes=archive.RawBytes})
 cp.Codec="zstd-base64-sections";cp.CoreRawBytes=cp.RawBytes
 cp.RawBytes+=archive.RawBytes+#',"MarketRetirement":';cp.Archive=archive
 return cp
end
local function worldFixture()
 local t,s=fixture();local c=clone(C);c.BotPopulation=nil;c.WarmupSeconds=0
 local function make(id)
  local w=World.new(c,{Studio=false,PlaceId=1,JobId=id,Store=s,Now=function()return t.Now end,CanOwn=true})
  w._fresh=function()
   local e=E.new(c,541);local f=F.new(e,L,c);f:Start("101");f:Start("102")
   return e,setmetatable({Engine=e,Config=c,Random=P.RNG.new(541),Agents={}},P)
  end
  return w
 end
 return t,s,make
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(r)})end
 test("Near-limit checkpoints save every 15 seconds for five minutes without exceeding per-key bytes",function()
  local t,s,owner=fixture();local a=owner("a");assert(a:Claim());local cp=large()
  for step=1,21 do a:Commit(cp,step,false);assert(a:Valid());t.Now+=15 end
  same(a:ReadCheckpoint(),cp);assert(s.ReadUncached,"Restore used a potentially stale slot cache")
  local keys=0;for _ in pairs(s.Values)do keys+=1 end
  assert(keys<=Settings.CheckpointSlots+1,"Storage grows without bound")
  assert(s.Value.Checkpoint==nil and s.Value.CheckpointRef and s.Value.Version==3)
 end)
 test("Immutable archives are staged once, fully restored, and reused across owners",function()
  local t,s,owner=fixture();local a=owner("a");assert(a:Claim());local cp=sectioned()
  local original=clone(cp)
  for step=1,12 do a:Commit(cp,step,false);t.Now+=15 end
  same(cp,original);same(a:ReadCheckpoint(),cp);same(CP.Decode(a:ReadCheckpoint()),CP.Decode(cp))
  local stored=s.Values[a.Record.CheckpointRef.Key].Checkpoint
  assert(stored.Codec=="zstd-base64-external"and not stored.Archive and stored.ArchiveRef)
  local key=stored.ArchiveRef.Key;local writes=0
  for _,w in ipairs(s.Writes)do if w.Key==key then writes+=1 end end;assert(writes==1)
  a:Commit(cp,13,true);local b=owner("b");assert(b:Claim());local read=b:ReadCheckpoint();same(read,cp)
  b:Commit(read,14,false)
  writes=0;for _,w in ipairs(s.Writes)do if w.Key==key then writes+=1 end end;assert(writes==1)
 end)
 test("Archive write failures and lost acknowledgements retain the old committed checkpoint",function()
  for _,lost in ipairs({false,true})do
   local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="kept"},1,false)
   local cp=sectioned();local archiveKey
   local function fail(key)
    if key:find(":arc:",1,true)then archiveKey=key;error("Injected archive failure")end
   end
   if lost then s.AfterCommit=fail else s.BeforeCommit=fail end
   assert(not pcall(function()a:Commit(cp,2,false)end))
   s.AfterCommit=nil;s.BeforeCommit=nil;assert(a:Claim());assert(a:ReadCheckpoint().Marker=="kept")
   a:Commit(cp,3,false);same(a:ReadCheckpoint(),cp)
   local writes=0;for _,w in ipairs(s.Writes)do if w.Key==archiveKey then writes+=1 end end;assert(writes==1)
  end
 end)
 test("Missing, foreign and corrupt external archives fail closed without replacing their data",function()
  for _,bad in ipairs({"missing","world","digest","length","payload","binding","key"})do
   local _,s,owner=fixture();local a=owner("a");assert(a:Claim());local cp=sectioned();a:Commit(cp,1,true)
   local stored=s.Values[s.Value.CheckpointRef.Key].Checkpoint;local key=stored.ArchiveRef.Key
   if bad=="missing"then s.Values[key]=nil
   elseif bad=="world"then s.Values[key].WorldId="foreign"
   elseif bad=="digest"then s.Values[key].Archive.Digest=string.rep("0",64)
   elseif bad=="length"then s.Values[key].Archive.RawBytes+=1
   elseif bad=="payload"then s.Values[key].Archive.Payload="bad"
   elseif bad=="binding"then stored.Digest=string.rep("0",64)
   else stored.ArchiveRef.Key="unexpected"end
   local b=owner("b");assert(b:Claim());local writes=#s.Writes
   assert(not pcall(function()CP.Decode(b:ReadCheckpoint())end));assert(#s.Writes==writes)
  end
 end)
 test("Archive digest collisions cannot overwrite another immutable value or publish a new reference",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());local cp=sectioned();a:Commit(cp,1,false)
  local bad=clone(cp);bad.Archive.Payload="different bytes";local previous=clone(a.Record.CheckpointRef)
  assert(not pcall(function()a:Commit(bad,2,false)end));same(s.Value.CheckpointRef,previous);same(a:ReadCheckpoint(),cp)
  -- A fresh lease must enforce the same rule against storage, without a local cache.
  a.Archives={};assert(not pcall(function()a:Commit(bad,3,false)end));same(s.Value.CheckpointRef,previous)
 end)
 test("Externalizing an archive does not bypass the combined saved-record size limit",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="kept"},1,false)
  local cp=sectioned();cp.Archive.Payload=string.rep("a",Settings.MaxEncodedBytes)
  assert(not pcall(function()a:Commit(cp,2,false)end));assert(a:ReadCheckpoint().Marker=="kept")
  for key in pairs(s.Values)do assert(not key:find(":arc:",1,true))end
 end)
 test("V2 ownership upgrades preserve the selected checkpoint, lease fencing and save counters",function()
  local t,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="legacy"},18,true)
  s.Value.Version=2;local before=clone(s.Value);local b=owner("b");assert(b:Claim())
  assert(b.Record.Version==3 and b.Record.WorldId==before.WorldId and b.Record.SaveSequence==before.SaveSequence
   and b.Record.SavedStep==before.SavedStep and b.Record.Generation==before.Generation+1)
  same(b.Record.CheckpointRef,before.CheckpointRef);same(b:ReadCheckpoint(),{Marker="legacy"})
  assert(not pcall(function()a:Commit({Marker="stale"},19,false)end))
 end)
 test("Lease claims and renewal never rewrite the full checkpoint; stale owners cannot publish",function()
  local t,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit(large(),1,false)
  local before=#s.Writes;local b=owner("b");assert(not b:Claim());assert(#s.Writes==before)
  t.Now+=30;assert(a:Renew());assert(s.Writes[#s.Writes].Bytes<16384)
  t.Now=a.Record.LeaseUntil+1;assert(b:Claim());same(b:ReadCheckpoint(),large())
  before=#s.Writes;assert(not pcall(function()a:Commit(large(),2,false)end));assert(#s.Writes==before)
 end)
 test("Shutdown has reserved slots even after normal writes exhaust their budget",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());local cp=large()
  local writes=0
  while a:CanCommit(false)do a:Commit(cp,writes,false);writes+=1;assert(writes<=Settings.CheckpointSlots)end
  local before=#s.Writes;assert(not pcall(function()a:Commit(cp,99,false)end));assert(#s.Writes==before)
  a:Commit(cp,100,true);assert(not a.Owned and s.Value.Owner=="")
  local b=owner("b");assert(b:Claim());same(b:ReadCheckpoint(),cp)
 end)
 test("Failed staging and failed publication preserve the previous completed checkpoint",function()
  for _,phase in ipairs({"payload","publish"})do
   local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="old"},1,false)
   s.BeforeCommit=function(key,value)
    if phase=="payload"and key~=Settings.WorldKey or phase=="publish"and value.SaveSequence==2 then error("Injected "..phase.." failure")end
   end
   assert(not pcall(function()a:Commit({Marker="new"},2,false)end));s.BeforeCommit=nil
   assert(a:Claim());assert(a:ReadCheckpoint().Marker=="old"and a.Record.SavedStep==1)
   a:Commit({Marker="retry"},3,false);assert(a:ReadCheckpoint().Marker=="retry")
  end
 end)
 test("Lost publication acknowledgement reloads the committed checkpoint exactly once",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="old"},1,false)
  s.LostReply=true;assert(not pcall(function()a:Commit({Marker="new"},2,false)end));s.LostReply=false
  assert(a:Claim());assert(a:ReadCheckpoint().Marker=="new"and a.Record.SaveSequence==2)
 end)
 test("Large V1 ownership records migrate without another multi-megabyte write to the primary key",function()
  local t,s,owner=fixture();local cp=large()
  s.Values[Settings.WorldKey]={Version=1,Owner="old",WorldId="stable",JobId="old",PlaceId=1,Generation=4,
   SaveSequence=7,SavedStep=9,LeaseUntil=t.Now-1,Checkpoint=cp}
  s.PrimaryKey=Settings.WorldKey;s.Value=s.Values[Settings.WorldKey]
  table.insert(s.Writes,{Key=Settings.WorldKey,At=t.Now-1,Bytes=3501000})
  local a=owner("a");assert(a:Claim());same(a:ReadCheckpoint(),cp)
  assert(a.Record.WorldId=="stable"and a.Record.SaveSequence==7 and a.Record.SavedStep==9 and a.Record.Generation==5)
  for i=2,#s.Writes do if s.Writes[i].Key==Settings.WorldKey then assert(s.Writes[i].Bytes<16384)end end
  a:Commit(cp,10,false);same(a:ReadCheckpoint(),cp)
 end)
 test("A missing or mismatched referenced checkpoint fails closed instead of starting a new world",function()
  for _,bad in ipairs({"missing","revision"})do
   local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="old"},1,true)
   local ref=s.Value.CheckpointRef
   if bad=="missing"then s.Values[ref.Key]=nil else s.Values[ref.Key].Revision+=1 end
   local b=owner("b");assert(b:Claim());assert(not pcall(function()b:ReadCheckpoint()end))
  end
 end)
 test("Repeated UpdateAsync callbacks reserve one revision and publish one save",function()
  local _,s,owner=fixture();s.ReplayCallback=true;local a=owner("a");assert(a:Claim())
  a:Commit({Marker="one"},1,false)
  assert(a.Record.CheckpointRevision==1 and a.Record.SaveSequence==1 and #s.Writes==4)
  assert(a:ReadCheckpoint().Marker=="one")
 end)
 test("A takeover between staging and publication fences both stale manifests and stale slot writes",function()
  local t,s,owner=fixture();local a,b=owner("a"),owner("b");assert(a:Claim());a:Commit({Marker="old"},1,false)
  local stale
  s.AfterCommit=function(key)
   if key==Settings.WorldKey then return end
   s.AfterCommit=nil;stale=clone(a.Record.PendingRef)
   t.Now=a.Record.LeaseUntil+1;assert(b:Claim());assert(b:ReadCheckpoint().Marker=="old")
   b:Commit({Marker="successor"},3,false)
  end
  assert(not pcall(function()a:Commit({Marker="stale"},2,false)end))
  assert(b:ReadCheckpoint().Marker=="successor")
  local writes=#s.Writes
  assert(not pcall(function()a:_put(stale,{Marker="late stale payload"},a.Record.WorldId)end))
  assert(#s.Writes==writes and b:ReadCheckpoint().Marker=="successor")
 end)
 test("Lost reservation acknowledgements retain cooldowns and leave the committed checkpoint intact",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="old"},1,false)
  local reserved
  s.AfterCommit=function(key,value)
   if key==Settings.WorldKey and value.PendingRef then
    s.AfterCommit=nil;reserved=clone(value.PendingRef);error("Injected lost reservation reply")
   end
  end
  assert(not pcall(function()a:Commit({Marker="unpublished"},2,false)end))
  assert(a:Claim());assert(a:ReadCheckpoint().Marker=="old")
  a:Commit({Marker="retry"},3,false)
  assert(a.Record.CheckpointRef.Slot~=reserved.Slot and a:ReadCheckpoint().Marker=="retry")
 end)
 test("A competing V1 migration cannot overwrite the winner's newer checkpoint",function()
  local t,s,owner=fixture()
  s.Values[Settings.WorldKey]={Version=1,Owner="old",WorldId="stable",JobId="old",PlaceId=1,Generation=4,
   SaveSequence=7,SavedStep=9,LeaseUntil=t.Now-1,Checkpoint={Marker="legacy"}}
  local a,b=owner("a"),owner("b")
  s.AfterCommit=function(key)
   if key==Settings.WorldKey then return end
   s.AfterCommit=nil;assert(b:Claim());b:Commit({Marker="newer"},10,false)
   t.Now=b.Record.LeaseUntil+1
  end
  assert(not a:Claim());assert(s.Values[Settings.WorldKey].SavedStep==10)
  assert(a:Claim());assert(a:ReadCheckpoint().Marker=="newer")
 end)
 test("Oversized slot payloads cannot replace the previous checkpoint",function()
  local _,s,owner=fixture();local a=owner("a");assert(a:Claim());a:Commit({Marker="kept"},1,false)
  local ref=clone(a.Record.CheckpointRef)
  assert(not pcall(function()a:Commit(large(Settings.MaxEncodedBytes),2,false)end))
  same(s.Value.CheckpointRef,ref);assert(a:ReadCheckpoint().Marker=="kept")
 end)
 test("World pacing pauses safely, renews the lease, and resumes the same unsaved engine",function()
  local t,s,make=worldFixture();local w=make("a");w:Open();assert(w:CanRun(),w.LastError)
  while w.Lease:CanCommit(false)do assert(w:Save(false))end
  local e=w.Engine;F.new(e,L,e.Config):GrantMoney("101",123,1,"unsaved")
  local writes=#s.Writes;local called=false
  assert(not w:TransformSaved(function()called=true end)and not called and w:CanRun())
  assert(not w:Save(false)and not w:CanRun()and #s.Writes==writes and w.Engine==e)
  local deadline=w.NextSave;t.Now=w.Lease.Record.LeaseUntil-Settings.SafetySeconds-Settings.RetrySeconds
  s.Fail=true;w:Maintain();assert(not w:CanRun()and w.Engine==e)
  s.Fail=false;t.Now=math.max(t.Now+1,deadline);w:Maintain()
  assert(w:CanRun()and w.Engine==e and w.Lease:Valid())
  local saved=CP.Restore(CP.Decode(w.Lease:ReadCheckpoint()),e.Config)
  assert(saved.Accounts[saved.Profiles["101"].Account].Balance==10123)
  assert(saved.Accounts[saved.Profiles["102"].Account].Balance==10000)
  assert(w:Close())
 end)
 test("Near-limit world checkpoints survive save, shutdown and restart with identical accounts",function()
  local t,s,make=worldFixture();local w=make("a");w:Open();assert(w:CanRun(),w.LastError)
  local encode=w._encode
  w._encode=function(self,...)
   local cp,step,projection=encode(self,...)
   -- Transport padding exercises the real persistence boundary at large encoded
   -- sizes without inventing or modifying production accounts/history.
   cp.TestPadding=string.rep("x",3400000)
   return cp,step,projection
  end
  for _=1,6 do t.Now+=15;assert(w:Save(false))end
  local expected=CP.Capture(w.Engine,w.Population);assert(w:Close())
  local resumed=make("b");resumed:Open();assert(resumed:CanRun(),resumed.LastError)
  same(expected,CP.Capture(resumed.Engine,resumed.Population));assert(resumed:Close())
 end)
 test("World restore rejects missing step-zero checkpoints instead of silently resetting accounts",function()
  local _,s,make=worldFixture();local w=make("a");w:Open();assert(w:CanRun());assert(w:Close())
  s.Value.CheckpointRef=nil;assert(s.Value.SavedStep==0 and s.Value.SaveSequence>0)
  local resumed=make("b");resumed._fresh=function()error("Must not reseed")end;resumed:Open()
  assert(not resumed:CanRun()and resumed.Mode=="Unavailable"and resumed.LastError:find("checkpoint is missing",1,true))
 end)
 return rows
end
return Tests
