-- Authoritative lifetime trading statistics, stored on each player account inside the exchange checkpoint.
-- A "completed trade" is one closing execution: exactly one row of the account's Trade History. A partial
-- close records the contracts it closed; the rest count when they close. A reversal counts its closing part.
-- Counters are updated by MarketEngine on the same execution that changes Balance/Realized, so they save and
-- restore atomically with the ledger. Display history is bounded (MaxAccountHistory); these counters are not.
local Stats={Version=1,EvenCents=0}
local EPS=0.005 -- half a cent: reconciliation tolerance for floating-point P&L

-- Calendar days are [00:00:00, 24:00:00) UTC, from the server's close timestamp.
-- Simulation HH:MM:SS is deliberately never treated as a historical calendar date.
local function dayRow()
 return {Trades=0,Wins=0,Losses=0,Even=0,Gains=0,Loss=0,Net=0}
end
function Stats.TrackDay(s,row)
 local stamp=row.ClosedAt
 if type(stamp)=="number" and stamp==stamp and stamp>0 and stamp<1e12 then
  local key=tostring(math.floor(stamp/86400))
  local d=s.Days[key] or dayRow() s.Days[key]=d
  local pnl=row.Pnl or 0 local cents=math.round(pnl*100)
  d.Trades+=1 d.Net+=pnl
  if cents>0 then d.Wins+=1 elseif cents<0 then d.Losses+=1 else d.Even+=1 end
  if pnl>0 then d.Gains+=pnl elseif pnl<0 then d.Loss-=pnl end
  d.Best=math.max(d.Best or pnl,pnl) d.Worst=math.min(d.Worst or pnl,pnl)
  s.FirstClosedAt=math.min(s.FirstClosedAt or stamp,stamp)
 end
 s.DayLastTradeId=math.max(s.DayLastTradeId or 0,row.TradeId or 0)
end
function Stats.EnsureDays(s,rows)
 if s.DayV~=1 then s.DayV=1 s.Days={} s.DayLastTradeId=0 end
 -- Also repairs dates retained after an older server updated lifetime counters but not days.
 local last=s.DayLastTradeId or 0
 for i=#(rows or {}),1,-1 do local row=rows[i]
  if type(row.TradeId)=="number" and row.TradeId>last and row.TradeId<=(s.LastTradeId or 0) then Stats.TrackDay(s,row) end
 end
end

function Stats.New(origin,now)
 return {V=Stats.Version,Trades=0,Wins=0,Losses=0,Even=0,Gains=0,Loss=0,Best=nil,Worst=nil,LastTradeId=0,
  UntrackedNet=0,UntrackedTrades=0,CountUnknown=false,Origin=origin or "Live",Since=now,DayV=1,Days={},DayLastTradeId=0}
end
-- Classify by the cent: a result that rounds to $0.00 is break-even. Sums use the exact values so that
-- Gains - Loss equals the ledger's realized total.
function Stats.Add(s,row)
 Stats.EnsureDays(s)
 Stats.TrackDay(s,row)
 local pnl=row.Pnl or 0
 local cents=math.round(pnl*100)
 s.Trades+=1
 if cents>Stats.EvenCents then s.Wins+=1 elseif cents<-Stats.EvenCents then s.Losses+=1 else s.Even+=1 end
 if pnl>0 then s.Gains+=pnl elseif pnl<0 then s.Loss-=pnl end
 if s.Best==nil or pnl>s.Best then s.Best=pnl end
 if s.Worst==nil or pnl<s.Worst then s.Worst=pnl end
 if type(row.TradeId)=="number" and row.TradeId>s.LastTradeId then s.LastTradeId=row.TradeId end
end
function Stats.Tracked(s) return s.Gains-s.Loss end

-- Depletion is recorded per attempt, once. New executions set Depleted when the engine latches Locked at
-- $0 equity. Saved attempts from before this marker existed are classified from their final state.
function Stats.MarkDepletion(engine,a)
 -- An archive record aggregates many finished attempts; each was classified before it was folded.
 if a.Archive or a.MigrationArchived or a.Depleted or a.Breached or not a.Locked or not a.Player then return end
 local equity=engine:Summary(a).Equity
 -- Checkpoint v3 reopened every positive-equity account that older loss rules had locked, so a current
 -- (not retired) locked account is depleted. A retired attempt still holding most of its capital was
 -- restarted under the earlier loss-limit rules and is reported separately, not as blown.
 if equity<=0 or not a.Retired or a.Balance<=a.Base*0.5 then a.Depleted=true
 else a.Breached="Earlier loss limit" end
end

-- Idempotent migration + drift repair. Safe to call on every restore.
--  * Accounts without Stats are rebuilt from their saved Trade History. When the rows reconcile with the
--    ledger (realized total, and the completed-trade counter when present) and the history was never trimmed,
--    the rebuild is complete ("Recovered"). Otherwise the unmatched part is kept as an untracked remainder
--    ("Partial") so Net realized still equals the ledger, and the UI labels the breakdown period.
--  * Accounts with Stats pick up any retained rows newer than LastTradeId (e.g. written by an older server
--    build), and any remaining mismatch is moved into the untracked remainder. Nothing is ever counted twice.
function Stats.Reconcile(engine,a,now)
 if not a.Player then return nil end
 local max=engine.Config.MaxAccountHistory or 60
 local rows=a.History or {}
 local s=a.Stats local fresh=type(s)~="table" or s.V~=Stats.Version
 if fresh then s=Stats.New("Recovered",now) a.Stats=s end
 Stats.EnsureDays(s,rows)
 -- History is newest first. Skip the scan when the newest row is already counted.
 local newest=rows[1]
 if fresh or (newest and type(newest.TradeId)=="number" and newest.TradeId>s.LastTradeId) then
  for i=#rows,1,-1 do
   local h=rows[i]
   if fresh or (type(h.TradeId)=="number" and h.TradeId>s.LastTradeId) then Stats.Add(s,h) end
  end
 end
 local gap=a.Realized-(Stats.Tracked(s)+s.UntrackedNet)
 local ledger=a.CompletedTrades
 if fresh then
  local trimmed=#rows>=max
  local countKnown=(ledger==nil and not trimmed) or ledger==s.Trades
  if math.abs(gap)<EPS and countKnown then
   s.Origin=#rows>0 and "Recovered" or "Live"
   -- The completed-trade counter predates some saves; a complete rebuild makes it exact.
   if ledger==nil and s.Trades>0 then a.CompletedTrades=s.Trades end
  else
   s.Origin="Partial" s.PartialSince=now
   s.UntrackedNet=gap
   s.UntrackedTrades=math.max(0,(ledger or #rows)-s.Trades)
   -- A counter that started from an already-trimmed history can itself undercount. Say so.
   s.CountUnknown=trimmed and ledger~=s.Trades
  end
 else
  if math.abs(gap)>=EPS then s.UntrackedNet+=gap s.Origin="Partial" s.PartialSince=s.PartialSince or now end
  local counted=s.Trades+s.UntrackedTrades
  if ledger and ledger>counted then s.UntrackedTrades+=ledger-counted s.Origin="Partial" s.PartialSince=s.PartialSince or now end
 end
 Stats.MarkDepletion(engine,a)
 return s
end

-- Folds one finished attempt's lifetime counters into an archive record. Every field is additive or an
-- extreme (best/worst, first/last), so the archive reports exactly what the separate attempts reported.
function Stats.Merge(into,s)
 Stats.EnsureDays(into) Stats.EnsureDays(s)
 for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","UntrackedNet","UntrackedTrades"}) do into[k]+=s[k] or 0 end
 if s.Best~=nil and (into.Best==nil or s.Best>into.Best) then into.Best=s.Best end
 if s.Worst~=nil and (into.Worst==nil or s.Worst<into.Worst) then into.Worst=s.Worst end
 into.LastTradeId=math.max(into.LastTradeId or 0,s.LastTradeId or 0)
 into.DayLastTradeId=math.max(into.DayLastTradeId or 0,s.DayLastTradeId or 0)
 for key,day in pairs(s.Days) do
  local d=into.Days[key] or dayRow() into.Days[key]=d
  for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","Net"}) do d[k]+=day[k] end
  if day.Best then d.Best=math.max(d.Best or day.Best,day.Best) end
  if day.Worst then d.Worst=math.min(d.Worst or day.Worst,day.Worst) end
 end
 if s.FirstClosedAt then into.FirstClosedAt=math.min(into.FirstClosedAt or s.FirstClosedAt,s.FirstClosedAt) end
 if s.Since then into.Since=math.min(into.Since or s.Since,s.Since) end
 into.CountUnknown=into.CountUnknown==true or s.CountUnknown==true
 into.RecoveredAny=into.RecoveredAny or s.RecoveredAny or s.Origin=="Recovered" or nil
 if s.Origin=="Partial" then
  into.Origin="Partial"
  if s.PartialSince then into.PartialSince=math.min(into.PartialSince or s.PartialSince,s.PartialSince) end
 elseif into.Origin~="Partial" and into.RecoveredAny then into.Origin="Recovered" end
 return into
end
-- Aggregation used by every Stats scope. Open P&L comes from the live engine summary of open positions.
function Stats.Empty()
 return {Attempts=0,Blown=0,Breached=0,Trades=0,Wins=0,Losses=0,Even=0,Gains=0,Loss=0,Net=0,Open=0,
  UntrackedNet=0,UntrackedTrades=0,CountUnknown=false,Partial=false,Recovered=false,Since=nil,Days={}}
end
function Stats.Include(agg,engine,a)
 local s=a.Stats or Stats.Reconcile(engine,a,os.time())
 Stats.EnsureDays(s,a.History)
 for key,day in pairs(s.Days) do
  local d=agg.Days[key] or dayRow() agg.Days[key]=d
  for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","Net"}) do d[k]+=day[k] end
  if day.Best then d.Best=math.max(d.Best or day.Best,day.Best) end
  if day.Worst then d.Worst=math.min(d.Worst or day.Worst,day.Worst) end
 end
 if s.FirstClosedAt then agg.FirstClosedAt=math.min(agg.FirstClosedAt or s.FirstClosedAt,s.FirstClosedAt) end
 if a.Archive then
  -- Folded finished attempts keep their own attempt/blown/breached classification.
  agg.Attempts+=a.Archive.Attempts agg.Blown+=a.Archive.Blown agg.Breached+=a.Archive.Breached
 else
  agg.Attempts+=1
  if a.Depleted then agg.Blown+=1 elseif a.Breached then agg.Breached+=1 end
 end
 if s.RecoveredAny then agg.Recovered=true end
 for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","UntrackedNet","UntrackedTrades"}) do agg[k]+=s[k] end
 agg.Net+=a.Realized
 if not a.Retired then agg.Open+=engine:Summary(a).Unrealized end
 if s.Best~=nil and (agg.Best==nil or s.Best>agg.Best) then agg.Best=s.Best end
 if s.Worst~=nil and (agg.Worst==nil or s.Worst<agg.Worst) then agg.Worst=s.Worst end
 if s.Origin=="Partial" then
  agg.Partial=true agg.CountUnknown=agg.CountUnknown or s.CountUnknown
  if s.PartialSince and (agg.Since==nil or s.PartialSince<agg.Since) then agg.Since=s.PartialSince end
 elseif s.Origin=="Recovered" then agg.Recovered=true end
 return agg
end
-- Derived values, computed once on the server so every client shows the same numbers.
function Stats.Finish(agg,datedOnly)
 if math.abs(agg.UntrackedNet)<EPS then agg.UntrackedNet=0 end
 agg.Total=agg.Net+agg.Open
 agg.WinRate=agg.Trades>0 and agg.Wins/agg.Trades or nil
 agg.AllTrades=agg.Trades+agg.UntrackedTrades
 if not agg.CountUnknown and agg.AllTrades>0 then agg.Average=agg.Net/agg.AllTrades agg.AverageScope="All"
 elseif agg.Trades>0 then agg.Average=(agg.Gains-agg.Loss)/agg.Trades agg.AverageScope="Tracked" end
 agg.AvgWin=agg.Wins>0 and agg.Gains/agg.Wins or nil
 agg.AvgLoss=agg.Losses>0 and agg.Loss/agg.Losses or nil
 agg.WinLossRatio=agg.AvgLoss and agg.AvgLoss>0 and (agg.AvgWin or 0)/agg.AvgLoss or nil
 agg.ProfitFactor=agg.Loss>0 and agg.Gains/agg.Loss or nil
 agg.NoLosses=agg.Trades>0 and agg.Gains>0 and agg.Loss==0
 local dated=Stats.Empty() local days,wins,lossDays,dayTrades,best=0,0,0,0,nil
 for _,day in pairs(agg.Days or {}) do
  days+=1 dayTrades+=day.Trades
  if math.round(day.Net*100)>0 then wins+=1 end
  if math.round(day.Net*100)<0 then lossDays+=1 end
  best=math.max(best or day.Net,day.Net)
  for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","Net"}) do dated[k]+=day[k] end
 end
 agg.UndatedTrades=math.max(0,agg.AllTrades-dayTrades)
 agg.DayCount=days agg.WinningDays=wins agg.LosingDays=lossDays agg.BestDay=best
 agg.DailyComplete=agg.UndatedTrades==0 and not agg.CountUnknown and not agg.Partial
 agg.DayWinRate=agg.DailyComplete and days>0 and wins/days or nil
 agg.BestDayShare=agg.DailyComplete and best and best>0 and agg.Net>=EPS and best/agg.Net or nil
 if not datedOnly then
  dated.Days=agg.Days dated.FirstClosedAt=agg.FirstClosedAt
  dated.Attempts=agg.Attempts dated.Blown=agg.Blown dated.Breached=agg.Breached
  agg.Dated=Stats.Finish(dated,true)
 end
 -- Day buckets remain on the saved account; only compact derived results cross the network.
 agg.Days=nil
 return agg
end
return Stats
