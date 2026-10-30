-- Read-only owner report. Never sends raw accounts, histories or player data.
local Health=require(script.Parent.BotParticipation)
local Stats={MaxBytes=300000}
local fields={"Count","Active","Retired","Depleted","Allocation","Balance","Equity","Realized","Unrealized","Pnl",
 "CapitalAdjusted","Positions","Contracts","Orders","Queued","Exits",
 "Trading","Quoting","Paused","Underfunded","Recovering","Cooldown","Waiting","Holding","Recoveries","Recycled"}
local function empty()local r={}for _,k in ipairs(fields)do r[k]=0 end return r end
local function add(total,row)for _,k in ipairs(fields)do total[k]+=row[k]end end
local function keys(t)local r={}for k in pairs(t)do table.insert(r,k)end table.sort(r);return r end
local function cell(value)return tostring(value):gsub("[%c]"," ")end
local function number(n)if math.abs(n)<.005 then n=0 end return string.format("%.2f",n)end
function Stats.Capture(engine,population)
 local report={Step=engine.Step,Time=engine.Time,RecentSeconds=engine.Config.BotParticipation and engine.Config.BotParticipation.RecentSeconds or 300,Recovered=population.ParticipationRecovered or 0,Transferred=population.ParticipationTransferred or 0,Total=empty(),Kinds={},Markets={},Bots={}}
 local last=population.BotRefreshReceipt
 if last then report.Refresh={Sequence=last.Sequence,Step=last.Step,Time=last.Time}end
 local seen={}
 for _,agent in ipairs(population.Agents)do
  local a=assert(engine.Accounts[agent.Id],"Missing participant account")
  assert(not seen[a.Id],"Duplicate participant");seen[a.Id]=true
  if a.Player or a.House or a.Archive then continue end
  local summary=engine:Summary(a);local book=assert(engine.Books[agent.Key],"Missing participant market")
  local retired=agent.Retiring or book.Spec.CloseOnly
  local row=empty();row.Id=a.Id;row.Kind=agent.Kind;row.Market=agent.Key
  row.Count=1;row.Retired=retired and 1 or 0;row.Active=1-row.Retired;row.Depleted=summary.Equity<=0 and 1 or 0
  row.Allocation=assert(engine.Config.BotPopulation.Capital[agent.Kind],"Missing bot allocation")
  row.Balance=a.Balance;row.Equity=summary.Equity;row.Realized=a.Realized;row.Unrealized=summary.Unrealized
  row.Pnl=row.Realized+row.Unrealized;row.CapitalAdjusted=a.NetCapitalAdjustments or 0
  local exitKinds,exitStates={},{};local exitAge
  for key,pos in pairs(a.Positions)do
   row.Positions+=1;row.Contracts+=pos.Quantity
   if pos.Triggered or pos.ExitOrder then
    row.Exits+=1
    local order=pos.ExitOrder and engine.Orders[pos.ExitOrder]
    table.insert(exitKinds,key..": "..(pos.Triggered or "Exit"))
    local status=not order and "No working exit order"or engine:OrderBlockReason(order)or (order.Type=="Limit"and "Resting limit"or "Executing")
    if agent.RecoveryReadyAt and pos.Triggered=="Take profit"then status="Recovery awaiting target replacement"end
    table.insert(exitStates,key..": "..status)
    if order then exitAge=math.max(exitAge or 0,engine.Time-order.Time)end
   end
  end
  table.sort(exitKinds);table.sort(exitStates)
  row.ExitKind=table.concat(exitKinds,"; ");row.ExitState=table.concat(exitStates,"; ")
  row.ExitOrderAge=exitAge and string.format('%.0f',exitAge)or(row.Exits>0 and 'unknown'or '')
  for id in pairs(a.OpenOrders)do local order=engine.Orders[id]
   if order then row.Orders+=1;if order.Queued then row.Queued+=1 end end
  end
  local state,recent,quoting,eligible=Health.Inspect(engine,agent,summary)
  row.State=state;row.Active=eligible and 1 or 0;row.Trading=recent and 1 or 0;row.Quoting=quoting and 1 or 0
  row.Paused=state=='Risk paused'and 1 or 0;row.Underfunded=state=='Underfunded'and 1 or 0
  row.Recovering=agent.RecoveryReadyAt and 1 or 0;row.Cooldown=state=='Cooldown'and 1 or 0
  row.Waiting=state=='Waiting'and 1 or 0;row.Holding=state=='Holding'and 1 or 0
  row.Recoveries=a.ParticipationRecoveries or 0;row.Recycled=a.ParticipationCapitalNet or 0
  row.LastFill= a.LastBotFillAt and string.format('%.0f',engine.Time-a.LastBotFillAt)or 'unknown'
  table.insert(report.Bots,row);add(report.Total,row)
  report.Kinds[row.Kind]=report.Kinds[row.Kind]or empty();add(report.Kinds[row.Kind],row)
  report.Markets[row.Market]=report.Markets[row.Market]or empty();add(report.Markets[row.Market],row)
 end
 table.sort(report.Bots,function(a,b)return a.Id<b.Id end)
 return report
end
function Stats.Format(report)
 local t=report.Total
 local lines={"GET FUNDED! - BOT STATS",string.format("Simulation step: %d | Simulation time: %.2fs",report.Step,report.Time),
  string.format("Bots: %d | Entry-eligible: %d | Retired/retiring: %d | Equity <= 0: %d",t.Count,t.Active,t.Retired,t.Depleted),
  string.format("Filled in last %.0fs: %d | Entry quotes: %d | Risk paused: %d | Underfunded: %d | In recovery: %d | Cooldown: %d | Waiting: %d | Holding: %d",
   report.RecentSeconds,t.Trading,t.Quoting,t.Paused,t.Underfunded,t.Recovering,t.Cooldown,t.Waiting,t.Holding),
  string.format("Recoveries: %d | Capital recycled between bots: $%s",report.Recovered,number(report.Transferred)),
  "Recent fills and entry quotes are activity flags; they may overlap paused/recovering states.",
  "Entry-eligible means policy permits new risk; available margin and strategy signals still govern orders.",
  "Recovery waits for flat inventory and a cooldown, then uses available realized bot surplus in the same market.",
  "Configured allocation: $"..number(t.Allocation).." | Cash balance: $"..number(t.Balance).." | Equity: $"..number(t.Equity),
  "P&L: $"..number(t.Pnl).." | Realized: $"..number(t.Realized).." | Unrealized: $"..number(t.Unrealized),
  "Net capital adjustments: $"..number(t.CapitalAdjusted),
  string.format("Open positions: %d | Contracts: %d | Working orders: %d | Queued orders: %d | Pending exits: %d",t.Positions,t.Contracts,t.Orders,t.Queued,t.Exits),
  report.Refresh and string.format("Last bot refresh: #%d at simulation step %d",report.Refresh.Sequence,report.Refresh.Step)or "Last bot refresh: none",
  "P&L excludes capital adjustments and performance before each bot's last refresh.",
  "Recovery counts and recycled capital are cumulative; they are not reset by a bot refresh.",
  "Exit-order age is the age of the oldest working exit order, not last-fill age or original exit-intent age; unknown means no working exit reference.",
  "All amounts are simulated dollars. Tables are tab-separated for pasting into a spreadsheet."}
 local header="Bots\tRetired\tDepleted\tAllocation\tBalance\tEquity\tRealized\tUnrealized\tNet P&L\tP&L % allocation\tCapital adjusted\tPositions\tContracts\tOrders\tQueued\tExits\tEligible\tRecent fills\tQuoting\tRisk paused\tUnderfunded\tRecovering\tCooldown\tRecoveries\tRecycled capital"
 local function values(row)
  return table.concat({row.Count,row.Retired,row.Depleted,number(row.Allocation),number(row.Balance),number(row.Equity),
   number(row.Realized),number(row.Unrealized),number(row.Pnl),number(row.Allocation>0 and row.Pnl/row.Allocation*100 or 0),
   number(row.CapitalAdjusted),row.Positions,row.Contracts,row.Orders,row.Queued,row.Exits,row.Active,row.Trading,row.Quoting,row.Paused,row.Underfunded,row.Recovering,row.Cooldown,row.Recoveries,number(row.Recycled)},"\t")
 end
 for _,section in ipairs({{"BY BOT TYPE",report.Kinds},{"BY MARKET",report.Markets}})do
  table.insert(lines,"");table.insert(lines,section[1]);table.insert(lines,"Group\t"..header)
  for _,key in ipairs(keys(section[2]))do table.insert(lines,cell(key).."\t"..values(section[2][key]))end
 end
 table.insert(lines,"");table.insert(lines,"INDIVIDUAL BOTS")
 table.insert(lines,"Bot ID\tMarket\tType\tState\tSeconds since fill\t"..header.."\tExit reason\tOldest exit order seconds\tExit status")
 for _,row in ipairs(report.Bots)do table.insert(lines,cell(row.Id).."\t"..cell(row.Market).."\t"..cell(row.Kind).."\t"..row.State.."\t"..row.LastFill.."\t"..values(row).."\t"..cell(row.ExitKind or '').."\t"..cell(row.ExitOrderAge or '').."\t"..cell(row.ExitState or ''))end
 local text=table.concat(lines,"\n")
 assert(#text<=Stats.MaxBytes,"Bot stats report exceeds the copy window capacity")
 return text
end
function Stats.Text(engine,population)return Stats.Format(Stats.Capture(engine,population))end
return Stats
