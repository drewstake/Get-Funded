local fs=require('@lune/fs');local serde=require('@lune/serde')
local H=require('../../../output/microprofiler-20261027/unit-v2/environment').game:GetService('HttpService')
local CP=require('../../../output/microprofiler-20261027/unit-v2/candidate/WorldCheckpoint')
local C=require('../../../output/microprofiler-20261027/unit-v2/candidate/MarketConfig')
local Old=require('../../../output/latency-20261027/final/candidate/WorldCheckpoint')
local OldC=require('../../../output/latency-20261027/final/candidate/MarketConfig')
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' types differ')
 if type(a)~='table'then assert(a==b,path..' values differ');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' unexpected '..tostring(k))end
end
local saved=Old.Decode(H:JSONDecode(fs.readFile('output/microprofiler-20261027/saved-checkpoint.json')).Checkpoint)
local untouched=copy(saved);local e,p=CP.Restore(saved,C);local before=CP.Capture(e,p)
local baseline,bp=Old.Restore(saved,OldC);local prior=Old.Capture(baseline,bp)
equal(prior.Engine,before.Engine,'preserved saved engine');equal(prior.Population,before.Population,'preserved saved population');equal(untouched,saved,'read-only input')
assert(#e.Config.ContractOrder==1 and e.Config.ContractOrder[1]=='BX'and #p.Agents==1170 and #e.Books.BX.ReserveProviders==54)
local r,rp=CP.Restore(CP.Decode(CP.EncodeWorld(e,p)),C)
for i=1,1200 do
 p:Step();rp:Step()
 if i%100==0 then equal(CP.Capture(e,p),CP.Capture(r,rp),'restart '..i)end
 if i==600 then r,rp=CP.Restore(CP.Decode(CP.EncodeWorld(r,rp)),C)end
end
local audit=e:Audit();r:Audit()
local c=copy(C);local new,np=CP.Restore(saved,c)
for i=1,1200 do
 bp:Step();np:Step()
 if i%100==0 then
  local a,b=Old.Capture(baseline,bp),CP.Capture(new,np)
  equal(a.Engine,b.Engine,'performance-only engine '..i);equal(a.Population,b.Population,'performance-only agents '..i)
 end
end
local World=require('../../../output/microprofiler-20261027/unit-v2/candidate/WorldService')
local Fake=require('../../../output/microprofiler-20261027/unit-v2/candidate/TestDataStore')
local Lease=require('../../../output/microprofiler-20261027/unit-v2/candidate/WorldLease')
local Settings=require('../../../output/microprofiler-20261027/unit-v2/candidate/WorldConfig')
local store=Fake.new();local now=1000
local function make(id)
 local w=World.new(C,{Studio=false,PlaceId=123,JobId=id,Store=store,Now=function()return now end,YieldEncoding=function()end})
 w._fresh=function()error('Saved world must never reset')end
 return w
end
-- Seed only this in-memory fake with the saved V33 checkpoint.
local seed=make('seed');local lease=Lease.new(store,Settings,seed.Identity,seed.Now);assert(lease:Claim())
lease:Commit(H:JSONDecode(fs.readFile('output/microprofiler-20261027/saved-checkpoint.json')).Checkpoint,saved.Engine.Step,true)
local archiveKeys={};local expected=CP.Capture(new,np)
local world=make('first');world:Open();assert(world:CanRun(),world.LastError)
equal(CP.Capture(world.Engine,world.Population).Engine,prior.Engine,'World open preserved engine')
equal(CP.Capture(world.Engine,world.Population).Population,prior.Population,'World open preserved agents')
for i=1,6 do now+=15;assert(world:Save(false),world.LastError)end
local settled=CP.Capture(world.Engine,world.Population);assert(world:Close())
local resume=make('second');resume:Open();assert(resume:CanRun(),resume.LastError)
equal(CP.Capture(resume.Engine,resume.Population),settled,'WorldService restart')
assert(resume:Close());for _,write in ipairs(store.Writes)do if write.Key:find(':arc:',1,true)then archiveKeys[write.Key]=(archiveKeys[write.Key]or 0)+1 end end
local archiveCount=0;for _,count in pairs(archiveKeys)do assert(count==1);archiveCount+=1 end;assert(archiveCount==1)
local report={WorldServiceRestarts=2,ArchiveWrites=archiveCount,Passed=true,AllSavedAccountsPositionsOrdersHistoryPreserved=true,InputUnchanged=true,Restarts=2,ReplaySteps=1200,PerformanceOnlyReplayIdenticalSteps=1200,Audit=audit,Participants=#p.Agents,Reserves=#e.Books.BX.ReserveProviders,Markets=e.Config.ContractOrder}
fs.writeFile('output/microprofiler-20261027/continuity-restart.json',serde.encode('json',report,true));print(serde.encode('json',report))
