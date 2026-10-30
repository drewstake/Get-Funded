-- Absence accounting consumes actual server executions, never reconnect-price guesses.
-- The market/positions/profiles are saved together in the fenced world checkpoint.
local Absence={}
local function mark(engine,key)
 local b=engine.Books[key];return (b.Last or b.Reference)*b.Spec.Tick
end
-- Use the saved return price, including for summaries created before full P&L was stored.
-- Keep the since-departure deltas for accounting, separate from the displayed trade P&L.
function Absence.WithPnl(engine,summary)
 if not summary then return nil end
 summary.Unrealized=0
 for _,row in ipairs(summary.Rows)do
  row.Unrealized=row.Remaining>0 and (row.CurrentPrice-row.Entry)*row.Remaining*row.Direction*engine.Books[row.Contract].Spec.Multiplier or 0
  summary.Unrealized+=row.Unrealized
 end
 return summary
end
function Absence.Depart(engine,p,now)
 if p.Absence then return end
 local a=engine.Accounts[p.Account];if not a then return end
 p.AbsenceSequence=(p.AbsenceSequence or 0)+1
 local absence={Id=tostring(p.Run)..":"..p.AbsenceSequence,Account=a.Id,At=now,Step=engine.Step,Time=engine.Time,Positions={}}
 for key,pos in pairs(a.Positions)do
  absence.Positions[key]={Id=pos.Id,Contract=key,Direction=pos.Direction,Entry=pos.Entry,Quantity=pos.Quantity,
   DeparturePrice=mark(engine,key),Multiplier=engine.Books[key].Spec.Multiplier,Closed=0,Realized=0,RealizedChange=0,Exits={}}
 end
 p.Absence=absence
end
function Absence.Closed(p,row)
 local absence=p.Absence
 local item=absence and absence.Positions[row.Contract]
 if not item or row.PositionId~=item.Id or row.TradeId<=(item.LastTradeId or 0)then return end
 item.LastTradeId=row.TradeId
 item.Closed+=row.Quantity;item.Realized+=row.Pnl
 item.RealizedChange+=(row.Exit-item.DeparturePrice)*row.Quantity*item.Direction*item.Multiplier
 local reason=row.Reason or "Trade"
 local exit=item.Exits[reason] or {Reason=reason,Quantity=0,Realized=0,Change=0,Notional=0}
 exit.Quantity+=row.Quantity;exit.Realized+=row.Pnl;exit.Change+=(row.Exit-item.DeparturePrice)*row.Quantity*item.Direction*item.Multiplier
 exit.Notional+=row.Exit*row.Quantity;item.Exits[reason]=exit
end
function Absence.Return(engine,p,now)
 local absence=p.Absence;if not absence then return end
 p.Absence=nil
 if absence.Account~=p.Account or not next(absence.Positions)then return end
 local a=engine.Accounts[p.Account]
 local summary={Id=absence.Id,Seconds=math.max(0,now-absence.At),MarketSeconds=math.max(0,engine.Time-absence.Time),
  Realized=0,RealizedChange=0,UnrealizedChange=0,Rows={},
  Coverage="Exits use actual exchange trades while the server runs. The market pauses when no server is running; no missing prices or outcomes are invented."}
 local ordered={};for key in pairs(absence.Positions)do table.insert(ordered,key)end;table.sort(ordered)
 for _,key in ipairs(ordered)do
  local item=absence.Positions[key];local held=a.Positions[key]
  local remaining=held and held.Id==item.Id and held.Quantity or 0
  local current=mark(engine,key)
  local delta=(current-item.DeparturePrice)*remaining*item.Direction*item.Multiplier
  local exits={};for _,exit in pairs(item.Exits)do table.insert(exits,exit)end
  table.sort(exits,function(x,y)return x.Reason<y.Reason end)
  table.insert(summary.Rows,{Contract=key,Direction=item.Direction,Quantity=item.Quantity,Remaining=remaining,
   Entry=item.Entry,DeparturePrice=item.DeparturePrice,CurrentPrice=current,Realized=item.Realized,
   RealizedChange=item.RealizedChange,UnrealizedChange=delta,Exits=exits})
  summary.Realized+=item.Realized;summary.RealizedChange+=item.RealizedChange;summary.UnrealizedChange+=delta
 end
 summary.Total=summary.RealizedChange+summary.UnrealizedChange
 summary.CarriedIn=summary.Realized-summary.RealizedChange
 p.AwaySummary=Absence.WithPnl(engine,summary)
end
function Absence.Acknowledge(p,id)
 if p.AwaySummary and p.AwaySummary.Id==id then p.AwaySummary=nil;p.LastAwaySummary=id;return true end
 return p.LastAwaySummary==id
end
return Absence
