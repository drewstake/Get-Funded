-- Replays an explicitly supplied read-only checkpoint; never connects to Roblox.
local fs=require('@lune/fs');local serde=require('@lune/serde')
local env=require('./environment');local http=env.game:GetService('HttpService')
local CP=require('./candidate/WorldCheckpoint');local C=require('./candidate/MarketConfig')
local Policy=require('./candidate/PlayerExecution')
local output=__OUTPUT__;local path=__SNAPSHOT__
local export=http:JSONDecode(fs.readFile(path));local snapshot=CP.Decode(export.Checkpoint)
local e,p=CP.Restore(snapshot,C);local playerId=__PLAYER__
local a=assert(e.Accounts[playerId],'Saved player not found')
local before={Step=e.Step,Summary=e:Summary(a),Positions={}}
local original={};for _,ac in ipairs(snapshot.Engine.Accounts)do original[ac.Id]=ac end
local capital=0
for id,ac in pairs(e.Accounts)do
 local old=assert(original[id],'Unexpected new account during safety migration')
 for _,field in ipairs({'Base','Balance','Realized','CashFlow'})do assert(math.abs(ac[field]-old[field])<.005,'Migration changed '..id..'.'..field)end
 capital+=ac.Base
 for key,pos in pairs(ac.Positions)do local prior=assert(old.Positions[key]);assert(pos.Quantity==prior.Quantity and pos.Direction==prior.Direction and pos.Entry==prior.Entry and pos.PnlEntry==prior.PnlEntry,'Migration changed a position')end
end
assert(e.NextTrade==snapshot.Engine.NextTrade and e.Time==snapshot.Engine.Time,'Migration executed trades')
for key,pos in pairs(a.Positions)do before.Positions[key]={Quantity=pos.Quantity,Entry=pos.Entry,Direction=pos.Direction,NewSameSideCapacity=e:OrderCapacity(a,key,pos.Direction)}end
-- Repeat the upgraded restore before running: queued exit identity and the new bands persist.
local r,rp=CP.Restore(CP.Decode(CP.EncodeWorld(e,p)),C)
local checkpoints={};local firstFlat;local start=e.Time
for i=1,2400 do
 p:Step();rp:Step()
 assert(e.NextTrade==r.NextTrade and e.TradeHash==r.TradeHash,'Restart changed deterministic execution')
 if not next(a.Positions)and not firstFlat then firstFlat=e.Time-start end
 if i%120==0 then
  local held=0;for _,pos in pairs(a.Positions)do held+=pos.Quantity end
  table.insert(checkpoints,{Seconds=e.Time-start,Remaining=held,BX=e.Books.BX.Last*e.Books.BX.Spec.Tick,BidContracts=Policy.Liquidity(e,e.Books.BX,-1)})
 end
end
assert(firstFlat and not next(a.Positions),'Saved position did not completely exit')
local afterCapital=0;for _,ac in pairs(e.Accounts)do afterCapital+=ac.Base end
assert(math.abs(afterCapital-capital)<.01,'Replay injected capital')
local report={Passed=true,Scope=export.Scope,SnapshotPath=path,Player=playerId,MigrationPreservedLedgers=true,
 NewCheckpointVersion=CP.Version,Before=before,After=e:Summary(a),SecondsUntilFlat=firstFlat,
 SimulatedSeconds=e.Time-start,Checkpoints=checkpoints,CapitalChange=afterCapital-capital,
 RestartDeterministic=true,Audit=e:Audit(),RestartAudit=r:Audit()}
fs.writeFile(output..'/saved-position-results.json',serde.encode('json',report,true))
print('SAVED POSITION PASS; flat after',firstFlat,'simulated seconds; final balance',a.Balance,'capital change',afterCapital-capital)
