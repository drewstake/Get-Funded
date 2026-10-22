-- Population expansion must not become a funding reset or a new opening auction.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Policy=require(script.Parent.BotPopulation)
local Tests={}
local function clone(v)if type(v)~='table'then return v end;local t={};for k,x in pairs(v)do t[k]=clone(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' value');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function oldConfig()
 local c=clone(C);c.BotPopulation.Version=1
 c.BotPopulation.Counts={Maker=20,Liquidity=24,Momentum=12,Value=20,Reversion=12,Protective=8,Scalper=24,Whale=4,Reserve=6}
 c.MakersPerInstrument=20;c.ParticipantsPerInstrument=76;c.WhalesPerInstrument=4;c.ScalpersPerInstrument=24;c.Reserve.Count=6
 return c
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test('Every group triples while per-bot risk, funding and cadence stay fixed',function()
  local old=oldConfig();local n=0
  for _,kind in ipairs(C.BotPopulation.Order)do assert(C.BotPopulation.Counts[kind]==old.BotPopulation.Counts[kind]*3);n+=C.BotPopulation.Counts[kind]end
  assert(n==390 and C.MakersPerInstrument==60 and C.ParticipantsPerInstrument==228 and C.ScalpersPerInstrument==72 and C.WhalesPerInstrument==12 and C.Reserve.Count==18)
  return '390 bots per market, 1170 across BX/BT/BG'
 end)
 test('Saved V22 world appends 780 bots without changing existing state',function()
  local e=E.new(oldConfig(),19381);local p=P.new(e)
  for _=1,80 do p:Step()end
  -- Opaque IDs and an occupied future ID must not cause collisions or profile replacement.
  local a=p.Agents[1];local oldId=a.Id;local id='renamed:market-maker'
  e.Accounts[id]=e.Accounts[oldId];e.Accounts[oldId]=nil;e.Accounts[id].Id=id;a.Id=id
  for i,v in ipairs(e.AccountOrder)do if v==oldId then e.AccountOrder[i]=id end end
  for _,o in pairs(e.Orders)do if o.Owner==oldId then o.Owner=id end end
  e:AddAccount('bot:BX:Maker:21',750000,20,.5,false)
  e.Accounts[id].Locked=true;a.ReadyAt=e.Time+1000
  local snapshot=CP.Capture(e,p);snapshot.Version=22;local unchanged=clone(snapshot)
  local re,rp=CP.Restore(snapshot,C);equal(snapshot,unchanged)
  Policy.Validate(rp);assert(#rp.Agents==1170 and #re.AccountOrder==1171)
  assert(rp.MigrationReport.PreserveExisting and rp.MigrationReport.FundingAdjustment==0 and #rp.MigrationReport.Accounts==0)
  local funding=0;for _,row in ipairs(rp.MigrationReport.Add)do funding+=row.Count*row.CapitalEach end;assert(funding==408000000)
  local restored=CP.Capture(re,rp);local accounts={};for _,ac in ipairs(restored.Engine.Accounts)do accounts[ac.Id]=ac end
  for _,ac in ipairs(snapshot.Engine.Accounts)do
   equal(ac,accounts[ac.Id],'account.'..ac.Id)
   equal(e.Accounts[ac.Id].OpenOrders,re.Accounts[ac.Id].OpenOrders,'working orders.'..ac.Id)
  end
  for i,agent in ipairs(snapshot.Population.Agents)do equal(agent,rp.Agents[i],'agent.'..agent.Id)end
  local oldEngine=clone(snapshot.Engine);local newEngine=clone(restored.Engine)
  oldEngine.Accounts=nil;newEngine.Accounts=nil;equal(oldEngine,newEngine,'exchange')
  for i=391,#rp.Agents do local agent=rp.Agents[i];local ac=re.Accounts[agent.Id]
   assert(agent.Next>re.Time and ac.Base==C.BotPopulation.Capital[agent.Kind]and ac.NetCapitalAdjustments==0 and not next(ac.Positions)and not next(ac.OpenOrders))
  end
  assert(not Policy.Apply(rp).Needed);equal(restored,CP.Capture(re,rp))
  local rr,pp=CP.Restore(CP.Decode(CP.Encode(restored)),C);equal(restored,CP.Capture(rr,pp))
  for _=1,120 do rp:Step();pp:Step()end
  equal(CP.Capture(re,rp),CP.Capture(rr,pp));re:Audit();rr:Audit()
  return 'Existing accounts, orders, profiles, paused state and tape preserved; exact roundtrip and 120-step replay'
 end)
 test('Expansion rejects funding changes, reductions and downgrade',function()
  local e=E.new(oldConfig(),3);local p=P.new(e);local snapshot=CP.Capture(e,p)
  local changed=clone(C);changed.BotPopulation.Capital.Maker+=1;assert(not pcall(CP.Restore,snapshot,changed))
  changed=clone(C);changed.BotPopulation.Counts.Maker=19;assert(not pcall(CP.Restore,snapshot,changed))
  local re,rp=CP.Restore(snapshot,C);assert(not pcall(CP.Restore,CP.Capture(re,rp),oldConfig()))
  return 'Unsupported migrations fail before modifying saved state'
 end)
 test('Full-book maintenance runs once per market per step, with live eligibility on fills',function()
  local e=E.new(clone(C),312);local p=P.new(e);local scans=0;local prune=e._pruneBook
  e._pruneBook=function(self,b)scans+=1;return prune(self,b)end
  for _=1,40 do
   p:Step()
   for _,key in ipairs(C.ContractOrder)do
    local bid,ask=e:PublicPrices(key);local visible=e:PublicDepth(key,1)
    assert(bid==(visible.Bids[1]and visible.Bids[1].Price)and ask==(visible.Asks[1]and visible.Asks[1].Price),'Strategy prices differ from player depth')
   end
  end
  assert(scans==40*#C.ContractOrder,'Full-book scans multiplied by participant decisions')
  -- Funds/locks can change after a maintenance boundary. A stale best order must
  -- never fill just because the preceding full scan considered it eligible.
  for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
  local b=e.Books.BX;local price=b.Last*b.Spec.Tick
  e:AddAccount('stale',1000000,100,.8,false);e:AddAccount('valid',1000000,100,.8,false);e:AddAccount('taker',1000000,100,.8,false)
  assert(e:Submit('stale',{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=price}))
  assert(e:Submit('valid',{Contract='BX',Direction=-1,Quantity=2,Type='Limit',Price=price+b.Spec.Tick}))
  e.Accounts.stale.Locked=true
  local depth=e:PublicDepth('BX',1);assert(depth.Asks[1].Price==price+b.Spec.Tick)
  local _,ask=e:PublicPrices('BX');assert(ask==depth.Asks[1].Price)
  local ok,result=e:Submit('taker',{Contract='BX',Direction=1,Quantity=1,Type='Market'})
  assert(ok and result.Filled==1 and result.Average==price+b.Spec.Tick and not next(e.Accounts.stale.Positions))
  assert(not e.ProcessingParticipants,'Participant scope leaked into external requests')
  e:Audit();return 'Bounded scans; stale locked quotes excluded from public depth and actual execution'
 end)
 return rows
end
return Tests

