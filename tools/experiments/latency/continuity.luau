local fs=require('@lune/fs');local serde=require('@lune/serde')
local H=require('../../../output/latency-20261027/final/environment').game:GetService('HttpService')
local CP=require('../../../output/latency-20261027/final/candidate/WorldCheckpoint')
local C=require('../../../output/latency-20261027/final/candidate/MarketConfig')
local Old=require('../../../output/latency-20261027/baseline/candidate/WorldCheckpoint')
local OldC=require('../../../output/latency-20261027/baseline/candidate/MarketConfig')
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' types differ')
 if type(a)~='table'then assert(a==b,path..' values differ');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' unexpected '..tostring(k))end
end
local saved=Old.Decode(H:JSONDecode(fs.readFile('output/latency-20261027/saved-checkpoint.json')).Checkpoint)
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
local c=copy(C);c.MakerSafeReprice=false;local new,np=CP.Restore(saved,c)
for i=1,1200 do
 bp:Step();np:Step()
 if i%100==0 then
  local a,b=Old.Capture(baseline,bp),CP.Capture(new,np)
  equal(a.Engine,b.Engine,'performance-only engine '..i);equal(a.Population,b.Population,'performance-only agents '..i)
 end
end
local report={Passed=true,AllSavedAccountsPositionsOrdersHistoryPreserved=true,InputUnchanged=true,Restarts=2,ReplaySteps=1200,PerformanceOnlyReplayIdenticalSteps=1200,Audit=audit,Participants=#p.Agents,Reserves=#e.Books.BX.ReserveProviders,Markets=e.Config.ContractOrder}
fs.writeFile('output/latency-20261027/continuity-final.json',serde.encode('json',report,true));print(serde.encode('json',report))
