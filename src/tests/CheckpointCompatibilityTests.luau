-- In-memory compatibility tests. No Roblox DataStore is requested.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local World=require(script.Parent.WorldService)
local Lease=require(script.Parent.WorldLease)
local Settings=require(script.Parent.WorldConfig)
local Fake=require(script.Parent.TestDataStore)
local Tests={}
local function clone(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function equal(a,b)
 assert(type(a)==type(b),'State type differs')
 if type(a)~='table'then assert(a==b,'State value differs: '..tostring(a)..' / '..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end for k in pairs(b)do assert(a[k]~=nil,'Unexpected field '..tostring(k))end
end
local function fixture()
 local c=clone(C);c.BotPopulation=nil;c.MakersPerInstrument=3;c.ParticipantsPerInstrument=5;c.WhalesPerInstrument=1;c.ScalpersPerInstrument=0;c.Reserve.Count=1
 local e=E.new(c,1729);local p=P.new(e)
 for _=1,20 do p:Step()end
 local snapshot=CP.Capture(e,p);snapshot.Version=28
 local record=CP.Encode(snapshot);record.Version=28
 return c,snapshot,record
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(err)})end
 test('Installed V28 retains its complete execution and bot state through V33 and continuation',function()
  local c,snapshot,record=fixture();local before=clone(snapshot)
  local e,p=CP.Restore(CP.Decode(record),c);local restored=CP.Capture(e,p)
  equal(snapshot.Engine,restored.Engine);equal(snapshot.Population,restored.Population);equal(before,snapshot)
  assert(restored.Version==33 and e.Config.MakerQuotePolicyVersion==8 and e.Config.BotMomentum.Version==2 and e.Config.BotWhale.Version==1)
  local r,rp=CP.Restore(CP.Decode(CP.EncodeWorld(e,p)),c)
  for _=1,40 do p:Step();rp:Step()end
  equal(CP.Capture(e,p),CP.Capture(r,rp));e:Audit();r:Audit()
 end)
 test('World Open resumes a V28 checkpoint and commits a restartable V33 without resetting the world',function()
  local c,snapshot,record=fixture();local s=Fake.new()
  local function make(job)return World.new(c,{Studio=true,PlaceId=123,JobId=job,Store=s,Now=function()return 1000 end,CanOwn=true})end
  local seed=make('seed');local lease=Lease.new(s,Settings,seed.Identity,seed.Now);assert(lease:Claim());assert(lease:Commit(record,snapshot.Engine.Step,true))
  local world=make('restore');world._fresh=function()error('Existing world must never be reset')end;world:Open()
  assert(world:CanRun(),world.LastError);assert(world.Engine.Step==snapshot.Engine.Step)
  equal(snapshot.Engine,CP.Capture(world.Engine,world.Population).Engine)
  assert(world.Lease:ReadCheckpoint().Version==33);assert(world:Close())
  local restarted=make('restart');restarted:Open();assert(restarted:CanRun(),restarted.LastError)
  equal(CP.Capture(world.Engine,world.Population),CP.Capture(restarted.Engine,restarted.Population));assert(restarted:Close())
 end)
 test('Unsupported research and future formats fail clearly without replacing the recoverable checkpoint',function()
  local c,snapshot,record=fixture()
  for _,version in ipairs({29,CP.Version+1})do
   local bad=clone(record);bad.Version=version
   local ok,message=pcall(CP.Decode,bad);assert(not ok and tostring(message):find('Unsupported saved market format: '..version,1,true))
   local s=Fake.new();local options={Studio=true,PlaceId=123,JobId='seed',Store=s,Now=function()return 1000 end,CanOwn=true}
   local seed=World.new(c,options);local lease=Lease.new(s,Settings,seed.Identity,seed.Now);assert(lease:Claim());assert(lease:Commit(bad,snapshot.Engine.Step,true))
   local world=World.new(c,options);world._fresh=function()error('Must not replace unsupported data')end;world:Open()
   assert(not world:CanRun() and world.Mode=='Unavailable');equal(bad,world.Lease:ReadCheckpoint())
  end
 end)
 return rows
end
return Tests
