local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local CP=require(script.Parent.WorldCheckpoint)
local Packet=require(game.ReplicatedStorage.MarketReign.MarketPacket)
local World=require(script.Parent.WorldService)
local Fake=require(script.Parent.TestDataStore)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function equal(a,b)
 assert(type(a)==type(b),'Different types');if type(a)~='table'then assert(a==b,'Different values');return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra key '..tostring(k))end
end
local function small()
 local c=copy(C);c.BotPopulation=nil;c.BotInventory=nil;c.MarketRetirementVersion=nil;c.WarmupSeconds=0
 c.MakersPerInstrument=1;c.ParticipantsPerInstrument=1;c.WhalesPerInstrument=0;c.ScalpersPerInstrument=0;c.Reserve.Count=0
 local e=E.new(c,7251);local p=P.new(e);return e,p,c
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(err)})end
 test('Account responses match full snapshots without refreshing quote freshness',function()
  local e=small();local a=e:AddAccount('player',100000,100,.8,true)
  local full=e:Snapshot(a.Id,'BX','1m',false);local account=e:AccountSnapshot(a.Id)
  for k,v in pairs(account)do equal(v,full[k])end
  local s={Ready=true,AccountToken=a.Id,RequestSession=7,Quotes={Exact=true},DepthReceivedAt=19,DepthLive=false,Time=55,Step=9}
  account.AccountToken=a.Id;account.RequestSession=7;assert(Packet.AcceptAccount(s,account))
  Packet.ApplyAccount(s,account);assert(s.DepthReceivedAt==19 and not s.DepthLive and s.Quotes.Exact and s.Time==55 and s.Step==9)
  account.AccountToken='old';assert(not Packet.AcceptAccount(s,account));account.AccountToken=a.Id;account.RequestSession=6;assert(not Packet.AcceptAccount(s,account))
 end)
 test('Portfolio deltas preserve metadata, clear dynamic fields, and reject a missing baseline',function()
  local a={Active='player',Revision=4,Equity=10,Milestones={{Progress=1}},Ranks={{Name='Rookie'}},Awards={a=true},AwaySummary={Old=true}}
  local b=copy(a);b.Equity=9;b.AwaySummary=nil
  local value,delta=Packet.Portfolio(b,'key','key',false);assert(delta and not value.Milestones)
  equal(Packet.ApplyPortfolio(a,value,delta),b);assert(not Packet.ApplyPortfolio(nil,value,delta))
  local other=copy(a);other.Revision=3;assert(not Packet.ApplyPortfolio(other,value,delta))
  local all,isDelta=Packet.Portfolio(b,'old','new',false);assert(not isDelta);equal(all,b)
 end)
 test('Sectioned saves retain every archived value, reject corruption and bind the archive to its core',function()
  local e,p=small();e.MarketRetirement={Version=2,Markets={BT={History={{Close=33.25}}}},Accounts={{Balance=125}}}
  local expected=CP.Capture(e,p);local one=CP.EncodeWorld(e,p);assert(not CP.EncodingMetrics(e).ArchiveCacheHit)
  local two=CP.EncodeWorld(e,p);assert(CP.EncodingMetrics(e).ArchiveCacheHit and one.Archive==two.Archive)
  equal(expected,CP.Decode(two));assert(not pcall(function()e.MarketRetirement.Accounts[1].Balance=0 end))
  assert(not pcall(function()two.Archive.Digest='bad'end))
  local bad=copy(two);bad.Archive.Digest='bad';assert(not pcall(CP.Decode,bad))
  bad=copy(two);bad.CoreRawBytes+=1;assert(not pcall(CP.Decode,bad))
  bad=copy(two);bad.RawBytes+=1;assert(not pcall(CP.Decode,bad))
  bad=copy(two);bad.Archive=CP.Encode({Another='world'});bad.RawBytes=bad.CoreRawBytes+bad.Archive.RawBytes+#',"MarketRetirement":';assert(not pcall(CP.Decode,bad))
  assert(not pcall(CP.EncodeWorld,e,p,two.RawBytes-1));equal(expected,CP.Capture(e,p))
 end)
 test('Yielding save publishes the frozen step and immutable pre-yield state while trading continues',function()
  local e,p,c=small();local store=Fake.new();local advance=false;local yields=0
  local w=World.new(c,{Studio=false,PlaceId=123,JobId='latency',Store=store,Now=function()return 1000 end,YieldEncoding=function()
   if advance then yields+=1;p:Step()end
  end})
  w._fresh=function()return e,p end;w:Open();assert(w:CanRun(),w.LastError)
  local expected=CP.Capture(e,p);advance=true;assert(w:Save(false));advance=false
  assert(yields==3 and e.Step==expected.Engine.Step+3 and w.Lease.Record.SavedStep==expected.Engine.Step)
  equal(CP.Decode(w.Lease:ReadCheckpoint()),expected);assert(w:Close())
  local resumed=World.new(c,{Studio=false,PlaceId=123,JobId='resume',Store=store,Now=function()return 1000 end,YieldEncoding=function()end})
  resumed._fresh=function()error('Must restore')end;resumed:Open();assert(resumed:CanRun(),resumed.LastError)
  equal(CP.Capture(e,p),CP.Capture(resumed.Engine,resumed.Population));assert(resumed:Close())
 end)
 test('Restart reuses verified archive bytes and refuses an incorrect archive cache hint',function()
  local e,p=small();e.Config.MarketRetirementVersion=2;e.MarketRetirement={Version=2,Markets={},Accounts={},AuditSample={Balance=125}}
  local one=CP.EncodeWorld(e,p);local decoded=CP.Decode(one);local r,rp=CP.Restore(decoded,e.Config)
  assert(CP.RememberArchive(r,one.Archive));local two=CP.EncodeWorld(r,rp)
  assert(CP.EncodingMetrics(r).ArchiveCacheHit and two.Archive.Payload==one.Archive.Payload and two.Archive.Digest==one.Archive.Digest)
  local other=CP.Encode({Unrelated=true});assert(not CP.RememberArchive(r,other));equal(CP.Decode(two),CP.Capture(r,rp))
  local corrupt=copy(one.Archive);corrupt.Digest='bad';assert(not pcall(CP.RememberArchive,r,corrupt))
  local mutable=CP.Capture(r,rp);mutable.Engine.MarketRetirement.AuditSample.Balance=0
  assert(r.MarketRetirement.AuditSample.Balance==125)
 end)
 return rows
end
return Tests
