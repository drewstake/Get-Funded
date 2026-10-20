-- Lossless execution state, including FIFO identity and the participants' next random draw.
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local TradeStats=require(script.Parent.TradeStats)
local Http=game:GetService("HttpService")
local Encoding=game:GetService("EncodingService")
-- Version 3 introduces E-minis, retained close-only micro books and equity-only failure.
-- Version 4 adds armed stop entry orders, which wait off the order book. An older build would
-- rest them as limits, so it must fail closed on V4. V1-V3 are read unchanged.
-- Version 5 executes player orders off the order book against a saved house counterparty account. An older
-- build would rest player limits in the book again and liquidate the house as a bot, so it fails closed on V5.
-- V5 originally moved V1-V4 player limits off-book; V9 now cancels pre-V9 player limits on migration.
-- V6 permanently separates tier access, account instances and Shop receipts. Older writers must
-- refuse it, otherwise they could reset permanent entitlements or spend the wallet twice.
-- V7 renames ES/NQ to BX/BT, keeps RTY/YM only as retired close-only books and adds BG. Older builds
-- cannot map those markets, so they must refuse V7. V1-V6 saves migrate on restore (see plan and rename).
-- V8 adds the single-account profile. Older writers must fail closed.
-- V9 makes player limits executable book liquidity and persists amendment priority.
-- Pre-V9 pending player limits are cancelled during migration rather than retroactively matched.
-- V10 adds permanent reward grants, player resets and disconnect accounting. Older writers
-- must fail closed so they cannot discard an acknowledged summary or reset a granted bonus.
-- V11 adds scalpers with their own entry/exit state. Older writers must not resume them as generic traders.
-- V12 persists queued market/limit execution and aggregate budgets. Older matching engines must fail closed.
local Checkpoint={Version=12,Readable={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true}}
local function digest(raw)
 local bytes=Encoding:ComputeStringHash(raw,Enum.HashAlgorithm.Sha256)
 return (bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))
end
local function clone(value)
 if type(value)~="table"then return value end
 local result={} for key,v in pairs(value)do result[key]=clone(v)end return result
end
-- Maps each saved market to its current symbol (config.Renamed) and checks its economics: every saved market
-- must still exist as a current or retired (close-only) contract with the same tick and multiplier. The
-- restored order is every current market, then the retired markets the save held. A current market the
-- save lacks opens as a new book after restore (`added`).
local function plan(saved,current)
 assert(saved.StepSeconds==current.StepSeconds,"Saved market step size differs from configuration")
 local renamed,held,map=current.Renamed or {},{},{}
 for _,key in ipairs(saved.ContractOrder)do
  local name=renamed[key] or key
  local a,b=saved.Contracts[key],current.Contracts[name] or current.LegacyContracts[name]
  assert(a and b and not held[name] and a.Tick==b.Tick and a.Multiplier==b.Multiplier,"Saved contract specification changed: "..key)
  held[name]=true map[key]=name
 end
 local order,added={},{}
 for _,key in ipairs(current.ContractOrder)do table.insert(order,key) if not held[key] then added[key]=true end end
 for _,key in ipairs(current.LegacyOrder)do if held[key] and not current.Contracts[key] then table.insert(order,key) end end
 assert(#saved.Timeframes==#current.Timeframes,"Saved timeframes differ")
 for i,tf in ipairs(current.Timeframes)do assert(saved.Timeframes[i][1]==tf[1]and saved.Timeframes[i][2]==tf[2],"Saved timeframe changed")end
 return map,order,added
end
-- Moves renamed markets in saved state: table keys and the fields that name a market (Contract, Key) take the
-- current symbol. Saved ids stay opaque and unchanged (for example participant accounts "bot:ES:Maker:1").
local function rename(value,map,field)
 if type(value)=="string"then return (field=="Contract"or field=="Key")and map[value]or value end
 if type(value)~="table"then return value end
 local result={}
 for key,v in pairs(value)do result[type(key)=="string"and map[key]or key]=rename(v,map,key)end
 return result
end
function Checkpoint.Capture(engine,population)
 local e={Accounts={},Books={},Orders={},Profiles=clone(engine.Profiles or {})}
 for _,key in ipairs({"Seed","Time","Step","NextOrder","NextPriority","NextTrade","TotalVolume","TradeHash","PendingStops","Execution"})do e[key]=clone(engine[key])end
 for _,id in ipairs(engine.AccountOrder)do
  local a=clone(engine.Accounts[id]);a.OpenOrders=nil
  -- Bot histories are display-only; balances, cash ledger and inventory are retained exactly.
  if not a.Player then a.History={} a.Fills={}end
  table.insert(e.Accounts,a)
 end
 for _,key in ipairs(engine.Config.ContractOrder)do
  local book={}
  for field,value in pairs(engine.Books[key])do if field~="Bids"and field~="Asks"and field~="Spec"then book[field]=clone(value)end end
  e.Books[key]=book
 end
 local ids={}for id in pairs(engine.Orders)do table.insert(ids,id)end table.sort(ids)
 for _,id in ipairs(ids)do table.insert(e.Orders,clone(engine.Orders[id]))end
 local p={RandomState=population.Random.State}
 for key,value in pairs(population)do if key~="Engine"and key~="Config"and key~="Random"then p[key]=clone(value)end end
 return {Version=Checkpoint.Version,Config=clone(engine.Config),Engine=e,Population=p}
end
function Checkpoint.Restore(snapshot,currentConfig)
 assert(type(snapshot)=="table"and Checkpoint.Readable[snapshot.Version],"Unsupported saved market format")
 local map,order,added=plan(snapshot.Config,currentConfig)
 for old,name in pairs(map)do if old~=name then snapshot=rename(snapshot,map) break end end
 -- Preserve saved behavior except explicit, versioned migrations; presentation cadence may change.
 local config=clone(snapshot.Config)
 local upgradeReserves=(config.ReservePopulationVersion or 0)<(currentConfig.ReservePopulationVersion or 0)
 if upgradeReserves then config.Reserve=clone(currentConfig.Reserve);config.ReservePopulationVersion=currentConfig.ReservePopulationVersion end
 config.PlayerExecution=clone(currentConfig.PlayerExecution)
 local upgradeScalpers=(config.ScalperPopulationVersion or 0)<(currentConfig.ScalperPopulationVersion or 0)
 if upgradeScalpers then
  config.ScalpersPerInstrument=currentConfig.ScalpersPerInstrument
  config.ScalperPopulationVersion=currentConfig.ScalperPopulationVersion
  config.Scalper=clone(currentConfig.Scalper)
 end
 local upgradeMakers=(config.MakerPopulationVersion or 0)<(currentConfig.MakerPopulationVersion or 0)
 if upgradeMakers then
  config.MakersPerInstrument=currentConfig.MakersPerInstrument
  config.MakerPopulationVersion=currentConfig.MakerPopulationVersion
 end
 config.DailyLossLimit=nil
 for _,key in ipairs({"LegacyOrder","LegacyContracts","LegacyToCurrent","Renamed"})do config[key]=clone(currentConfig[key])end
 config.ContractOrder=order
 local retiring={}
 for _,key in ipairs(order)do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  local spec=config.Contracts[key]
  if added[key] then
   spec=clone(current) config.Contracts[key]=spec
   -- A new book starts near the saved market it succeeds, without relabelling historical executions or volume.
   for old,successor in pairs(currentConfig.LegacyToCurrent)do
    local b=successor==key and snapshot.Engine.Books[old]
    if b then spec.Last=(b.Last or b.Reference)*config.Contracts[old].Tick end
   end
  else
   -- Saved economics stay exact (checked in plan); names and the close-only rule follow this build.
   if current.CloseOnly and not spec.CloseOnly then retiring[key]=true end
   spec.Name=current.Name spec.Short=current.Short spec.CloseOnly=current.CloseOnly
  end
 end
 -- MaxCandles only bounds chart history (matching never reads candles), so a restored world adopts the current limit.
 for _,key in ipairs({"BroadcastSeconds","SimulationSpeed","MaxCatchupSteps","MaxCandles","MaxPlayerQuantity","MaxPlayerInventory","MaxPlayerOrders","DepthLevels","MakerQuotePolicyVersion","MakerMinRestSeconds","MakerRepriceTicks","MakerQuoteSizeMultiplier","MakerReplenishSeconds","MakerDecisionMultiplier"})do config[key]=currentConfig[key]end
 -- Simulated margin is buying-power policy; contract economics and all saved ledgers stay intact.
 for key,spec in pairs(config.Contracts) do
  local current=currentConfig.Contracts[key] or currentConfig.LegacyContracts[key]
  if current then spec.Margin=current.Margin end
 end
 local data=snapshot.Engine local engine=Engine.new(config,data.Seed)
 for _,key in ipairs({"Time","Step","NextOrder","NextTrade","TotalVolume","TradeHash","PendingStops","Execution"})do engine[key]=clone(data[key])end
 engine.NextPriority=data.NextPriority or data.NextOrder
 for _,a in ipairs(data.Accounts)do
  local account=clone(a);account.OpenOrders={}
  account.LossLimit=account.Base
  assert(not engine.Accounts[a.Id],"Duplicate saved account")
  engine.Accounts[a.Id]=account table.insert(engine.AccountOrder,a.Id)
 end
 for key,fields in pairs(data.Books)do for name,value in pairs(fields)do engine.Books[key][name]=clone(value)end end
 engine.Profiles=clone(data.Profiles or {})
 for uid,profile in pairs(engine.Profiles)do
  assert(type(uid)=="string"and type(profile)=="table"and type(profile.Tiers)=="table"and type(profile.Ledger)=="table","Invalid saved funded profile")
  for _,id in ipairs(profile.Ledger)do assert(engine.Accounts[id],"Saved funded account missing")end
 end
 local prior=0
 for _,order in ipairs(data.Orders)do
  local o=clone(order)
  -- Preserve execution behavior for orders placed before the explicit choice existed.
  o.Execution=o.Execution or "Sliced"
  assert(o.Id>prior and o.Remaining>0 and engine.Accounts[o.Owner]and engine.Books[o.Contract],"Invalid saved resting order")
  prior=o.Id engine.Orders[o.Id]=o engine.Accounts[o.Owner].OpenOrders[o.Id]=true
  o.Priority=o.Priority or o.Id
  engine.NextPriority=math.max(engine.NextPriority,o.Priority)
  if o.Type=="Limit"and not o.Queued and not(engine.Accounts[o.Owner].Player and snapshot.Version<9)then engine:_rest(engine.Books[o.Contract],o)end
 end
 local population=setmetatable({Engine=engine,Config=config},Participants)
 for key,value in pairs(snapshot.Population)do if key~="RandomState"then population[key]=clone(value)end end
 population.Random=Participants.RNG.new(1);population.Random.State=snapshot.Population.RandomState
 assert(type(population.Random.State)=="number"and population.Random.State>0 and population.Random.State<2147483647,"Invalid saved random state")
 for _,agent in ipairs(population.Agents)do assert(engine.Accounts[agent.Id],"Saved participant account missing")end
 if snapshot.Version<3 then
  local currentAccounts={}
  for _,profile in pairs(engine.Profiles) do for _,entry in pairs(profile.Tiers) do if entry.Account then currentAccounts[entry.Account]=true end end end
  for _,profile in pairs(engine.Profiles) do for _,id in ipairs(profile.Ledger) do if not currentAccounts[id] then engine.Accounts[id].Retired=true end end end
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player and not a.Retired and engine:Summary(a).Equity>0 then
    a.Locked=false a.Liquidating=nil
    for _,p in pairs(a.Positions) do if p.Triggered=="Risk liquidation" then p.Triggered=nil end end
   end
   if a.Player then
    for orderId in pairs(clone(a.OpenOrders)) do
     local o=engine.Orders[orderId]
     if config.Contracts[o.Contract].CloseOnly and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 -- A market that became close-only keeps its positions, SL/TP and closing orders. Its entry orders could only
 -- open new exposure there, so they are cancelled (the order history records it).
 if next(retiring) then
  for _,id in ipairs(engine.AccountOrder) do
   local a=engine.Accounts[id]
   if a.Player then
    local ids={} for orderId in pairs(a.OpenOrders) do table.insert(ids,orderId) end table.sort(ids)
    for _,orderId in ipairs(ids) do
     local o=engine.Orders[orderId]
     if o and retiring[o.Contract] and not o.ReduceOnly then engine:Cancel(id,orderId) end
    end
   end
  end
 end
 for _,key in ipairs(order) do if added[key] then population:AddMarket(key) end end
 if upgradeMakers then population:EnsureMakers(currentConfig.ContractOrder,config.MakersPerInstrument) end
 if upgradeScalpers then population:EnsureScalpers(currentConfig.ContractOrder,config.ScalpersPerInstrument) end
 if upgradeReserves then population:EnsureReserves(currentConfig.ContractOrder);population:RefreshReservePolicy()end
 -- Lifetime trading stats (no format change): rebuilt once from saved history for older accounts,
 -- reconciled against the ledger for all others. Idempotent across repeated restores.
 local now=os.time()
 -- Older settlement added every fill separately to large balances, accumulating sub-cent
 -- floating-point drift. Rebuild only tiny discrepancies from the existing capital/P&L ledger;
 -- larger differences still fail Audit. New settlement derives Balance from that ledger.
 for _,id in ipairs(engine.AccountOrder)do local a=engine.Accounts[id]
  local gap=a.Balance-a.Base-a.Realized
  if a.Base>=1e9 and math.abs(gap)<.005 then a.Balance=a.Base+a.Realized end
 end
 for _,id in ipairs(engine.AccountOrder) do local a=engine.Accounts[id] if a.Player then TradeStats.Reconcile(engine,a,now) end end
 -- Required migration, not optional leaderboard work: any failure aborts restore before saving.
 require(script.Parent.FundedAccounts).new(engine,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),currentConfig)
 -- Archive legacy profile evidence first; then cancel remaining off-book limits without a trade.
 if snapshot.Version<9 then
  local pending={};for id,o in pairs(engine.Orders)do if o.Type=="Limit"and engine.Accounts[o.Owner].Player then table.insert(pending,id)end end
  table.sort(pending);for _,id in ipairs(pending)do local o=engine.Orders[id];engine:Cancel(o.Owner,id)end
 end
 engine:Audit()
 return engine,population
end
-- The reader's decompressed-size bound. It is unchanged, so every checkpoint that opened before still opens.
-- Encode refuses anything larger before compressing, so the writer and the reader enforce one bound: every
-- checkpoint the writer accepts decodes, and every save that decodes today can be written again.
Checkpoint.MaxDecodedBytes=32000000
-- The reader's header rules, shared by Encode (before a commit) and Decode (on restore).
function Checkpoint.Check(record,maxDecodedBytes)
 assert(type(record)=="table" and Checkpoint.Readable[record.Version] and record.Codec=="zstd-base64" and type(record.Payload)=="string","Invalid checkpoint encoding")
 local compressed=Encoding:Base64Decode(buffer.fromstring(record.Payload))
 local bytes=Encoding:GetDecompressedBufferSize(compressed,Enum.CompressionAlgorithm.Zstd)
 assert(bytes and bytes==record.RawBytes and bytes<=math.min(maxDecodedBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes),"Invalid checkpoint length")
 return compressed,bytes
end
function Checkpoint.Encode(snapshot,maxRawBytes)
 local raw=Http:JSONEncode(snapshot)
 local limit=math.min(maxRawBytes or Checkpoint.MaxDecodedBytes,Checkpoint.MaxDecodedBytes)
 if #raw>limit then error(string.format("Exchange checkpoint is too large (%d raw bytes, limit %d); trading paused to protect saved state",#raw,limit),2) end
 local compressed=Encoding:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd,3)
 local record={Version=Checkpoint.Version,Codec="zstd-base64",RawBytes=#raw,
  Digest=digest(raw),
  Payload=buffer.tostring(Encoding:Base64Encode(compressed))}
 Checkpoint.Check(record,limit)
 return record
end
function Checkpoint.Decode(record,maxDecodedBytes)
 local compressed=Checkpoint.Check(record,maxDecodedBytes)
 local raw=buffer.tostring(Encoding:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))
 assert(digest(raw)==record.Digest,"Checkpoint checksum failed")
 return Http:JSONDecode(raw)
end
return Checkpoint
