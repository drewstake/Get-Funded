-- Accepts an already-read snapshot. Never claims a lease or writes any saved data.
local DryRun={}
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function DryRun.Run(snapshot,current,checkpoint)
 local engine,population=checkpoint.Restore(snapshot,current)
 local captured=checkpoint.Capture(engine,population)
 local byId={};for _,a in ipairs(captured.Engine.Accounts)do byId[a.Id]=a end
 local players,positions,legacy=0,0,0
 for _,a in ipairs(snapshot.Engine.Accounts)do
  local b=assert(byId[a.Id],'Account disappeared during migration')
  if a.Player then assert(equal(a,b),'Player account changed during bot migration');players+=1 end
  assert(a.Realized==b.Realized and a.CashFlow==b.CashFlow,'Trading ledger changed')
  assert(equal(a.Positions,b.Positions),'Position obligation changed');positions+=1
 end
 for _,a in ipairs(snapshot.Population.Agents)do
  local key=current.Renamed[a.Key]or a.Key
  if engine.Books[key].Spec.CloseOnly then
   for _,old in ipairs(snapshot.Engine.Accounts)do if old.Id==a.Id then assert(equal(old,byId[a.Id]),'Legacy bot changed');break end end
   legacy+=1
  end
 end
 assert(equal(snapshot.Engine.Profiles,captured.Engine.Profiles),'Player profiles changed')
 assert(snapshot.Engine.NextTrade==engine.NextTrade and snapshot.Engine.TotalVolume==engine.TotalVolume,'Migration traded')
 local record=checkpoint.Encode(captured)
 assert(record.RawBytes<=checkpoint.MaxDecodedBytes and #record.Payload+4096<3600000,'Migrated checkpoint does not fit')
 local resumed,rp=checkpoint.Restore(checkpoint.Decode(record),current)
 assert(equal(captured,checkpoint.Capture(resumed,rp)),'Migration is not idempotent')
 local active,equity=0,0
 for _,a in ipairs(population.Agents)do if not a.Retiring and not engine.Books[a.Key].Spec.CloseOnly then active+=1;equity+=engine:Summary(engine.Accounts[a.Id]).Equity end end
 assert(active==390 and math.abs(equity-204000000)<.01,'Active migration funding differs')
 return {DryRun=true,NoStoredWrites=true,PlayersPreserved=players,AccountObligationsPreserved=positions,LegacyBotsPreserved=legacy,
  Audit=engine:Audit(),Migration=population.MigrationReport,RawBytes=record.RawBytes,EncodedBytesWithHeadroom=#record.Payload+4096,
  ActiveBots=active,ActiveEquity=equity,SecondRestoreIdentical=true}
end
return DryRun
