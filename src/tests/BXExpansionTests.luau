-- Detached V2 -> V3 migration checks; no services, resets or live funding changes.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Fixtures=require(script.Parent.TestMarkets)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Policy=require(script.Parent.BotPopulation)
local T=require(script.Parent.TestLiquidity)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture()
 local c=Fixtures.BXVersion2();local e=E.new(c,20261027);local p=P.new(e)
 for _=1,80 do p:Step()end
 local funded=require(script.Parent.FundedAccounts).new(e,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),c)
 funded:Start('expansion-player');local owner=funded:Owner('expansion-player')
 T.FillAt(e,owner,{Contract='BX',Type='Market',Direction=1,Quantity=1})
 local a=p.Agents[1];e.Accounts[a.Id].Locked=true;a.ReadyAt=e.Time+1000
 -- An unrelated account occupying the next ID must not get overwritten or funded.
 e:AddAccount('bot:BX:Maker:61',123456,10,.5,false)
 return e,p,owner
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(r or 'Passed')or tostring(r)})end
 test('V3 triples every BX group without changing per-bot settings or safeguards',function()
  local old=Fixtures.BXVersion2();local n=0
  assert(C.BotPopulation.Version==3 and #C.ContractOrder==1 and C.ContractOrder[1]=='BX')
  for _,kind in ipairs(C.BotPopulation.Order)do assert(C.BotPopulation.Counts[kind]==3*old.BotPopulation.Counts[kind]);n+=C.BotPopulation.Counts[kind]end
  assert(n==1170 and C.MakersPerInstrument==180 and C.ParticipantsPerInstrument==684 and C.ScalpersPerInstrument==216 and C.WhalesPerInstrument==36 and C.Reserve.Count==54)
  local comparable=copy(C);comparable.BotPopulation.Version=2;comparable.BotPopulation.Counts=copy(old.BotPopulation.Counts)
  for _,key in ipairs({'MakersPerInstrument','ParticipantsPerInstrument','ScalpersPerInstrument','WhalesPerInstrument'})do comparable[key]=old[key]end
  comparable.Reserve.Count=18;equal(old,comparable)
 end)
 test('Appending 780 traders preserves every existing account, order, profile, price and candle',function()
  local e,p=fixture();local before=CP.Capture(e,p);local frozen=copy(before)
  local r,rp=CP.Restore(before,C);equal(before,frozen);Policy.Validate(rp)
  assert(#rp.Agents==1170 and #r.Books.BX.ReserveProviders==54 and not r.Books.BT and not r.Books.BG)
  local after=CP.Capture(r,rp);local accounts={};for _,a in ipairs(after.Engine.Accounts)do accounts[a.Id]=a end
  for _,a in ipairs(before.Engine.Accounts)do equal(a,accounts[a.Id],'account '..a.Id);equal(e.Accounts[a.Id].OpenOrders,r.Accounts[a.Id].OpenOrders)end
  for i,a in ipairs(before.Population.Agents)do equal(a,rp.Agents[i],'agent '..a.Id)end
  local oldEngine=copy(before.Engine);local newEngine=copy(after.Engine);oldEngine.Accounts=nil;newEngine.Accounts=nil;equal(oldEngine,newEngine,'exchange')
  equal(p.Markets,rp.Markets,'signals')
  assert(rp.MigrationReport.PreserveExisting and rp.MigrationReport.FundingAdjustment==0 and #rp.MigrationReport.Accounts==0)
  local funding=0;for _,row in ipairs(rp.MigrationReport.Add)do funding+=row.Count*row.CapitalEach end;assert(funding==408000000)
  local ids={};for _,a in ipairs(rp.Agents)do assert(not ids[a.Id]);ids[a.Id]=true end
  for i=391,#rp.Agents do local a=rp.Agents[i];local ac=r.Accounts[a.Id]
   assert(a.Next>r.Time and ac.Base==C.BotPopulation.Capital[a.Kind]and ac.Balance==ac.Base and ac.NetCapitalAdjustments==0)
   assert(not next(ac.Positions)and not next(ac.OpenOrders))
  end
  r:Audit()
 end)
 test('Restart does not duplicate traders or funding and preserves deterministic replay',function()
  local e,p=fixture();local r,rp=CP.Restore(CP.Capture(e,p),C);local before=CP.Capture(r,rp)
  assert(not Policy.Apply(rp).Needed);equal(before,CP.Capture(r,rp))
  local rr,pp=CP.Restore(CP.Decode(CP.Encode(before)),C);equal(before,CP.Capture(rr,pp))
  for _=1,120 do rp:Step();pp:Step()end
  equal(CP.Capture(r,rp),CP.Capture(rr,pp));r:Audit();rr:Audit()
 end)
 test('Version gates reject old writers, funding changes, count reductions and unversioned edits',function()
  local e,p=fixture();local before=CP.Capture(e,p)
  local changed=copy(C);changed.BotPopulation.Capital.Reserve+=1;assert(not pcall(CP.Restore,before,changed))
  changed=copy(C);changed.BotPopulation.Counts.Maker=59;assert(not pcall(CP.Restore,before,changed))
  local r,rp=CP.Restore(before,C);local after=CP.Capture(r,rp)
  assert(not pcall(CP.Restore,after,Fixtures.BXVersion2()))
  changed=copy(C);changed.BotPopulation.Counts.Maker+=1;assert(not pcall(CP.Restore,after,changed))
 end)
 test('An older three-market save retires BT/BG once while expanding BX only',function()
  local old=Fixtures.ThreeMarkets();old.MarketRetirementVersion=1
  local e=E.new(old,827);local p=P.new(e);for _=1,20 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=31
  local r,rp=CP.Restore(saved,C);assert(#rp.Agents==1170 and #r.MarketRetirement.Agents==780)
  for _,a in ipairs(rp.Agents)do assert(a.Key=='BX')end
  equal(saved.Engine.Books.BX,CP.Capture(r,rp).Engine.Books.BX);assert(r.NextTrade==e.NextTrade)
  local archive=copy(r.MarketRetirement);local after=CP.Capture(r,rp)
  local rr,pp=CP.Restore(after,C);equal(archive,rr.MarketRetirement);equal(after,CP.Capture(rr,pp));rr:Audit()
 end)
 return rows
end
return Tests
