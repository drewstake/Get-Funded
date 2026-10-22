-- Market references and announcements derived solely from completed executions.
-- No random generator, target price, news schedule or directional impulse.
local Flow={}
function Flow.Reference(book)return book.Last or book.Reference end
function Flow.Adopt(population)
 local e=population.Engine;local c=e.Config.OrderFlowMarket
 if not c or population.OrderFlowVersion==c.Version then return end
 -- Withdraw old valuation-based entry intent before the first new order is processed.
 for _,a in ipairs(population.Agents)do
  local b=e.Books[a.Key]
  if b and not b.Spec.CloseOnly then
   local ids={};local ac=e.Accounts[a.Id]
   for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
   table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
   a.Belief=Flow.Reference(b);a.Parent=0;a.ParentSide=1
   a.ObservedAt=e.Time;a.NextObservation=e.Time
  end
 end
 for key,m in pairs(population.Markets)do
  m.Fair=nil;m.Anchor=nil;m.Impulse=nil
  local b=e.Books[key];if b and not b.Spec.CloseOnly then b.FairReference=Flow.Reference(b);b.Flow=nil end
 end
 population.News=nil;population.NewsUntil=0;population.NextNews=nil;population.NextBeliefs=nil;population.Direction=nil
 population.Events={}
 if population.Regime then
  population.Regime=table.clone(population.Regime);population.Regime.Trend=nil
  if population.Regime.Name=='Trending'then population.Regime.Name='Active'end
 end
 population.OrderFlowVersion=c.Version
end
function Flow.Record(e,b)
 local c=e.Config.OrderFlowMarket;if not c then return end
 b.FairReference=Flow.Reference(b) -- Compatibility field; now an observed execution reference.
 local state=b.Flow
 if not state then state={History={},Count=0,NextEventAt=0};b.Flow=state end
 state.Count+=1
 local history=state.History;local now=e.Time;local last=history[#history]
 local bucket=math.floor(now/c.SampleSeconds)
 if last and last.Bucket==bucket then
  last.Time=now;last.Price=b.Last;last.Count=state.Count
 else table.insert(history,{Bucket=bucket,Time=now,Price=b.Last,Count=state.Count})end
 local cutoff=now-c.WindowSeconds
 while #history>2 and history[2].Time<=cutoff do table.remove(history,1)end
 local first=history[1]
 if first.Time>cutoff or state.Count-first.Count<c.MinTrades or now<state.NextEventAt then return end
 local move=b.Last-first.Price
 local threshold=math.max(c.MinMoveTicks*math.max(1,b.Spec.Scale or 1),first.Price*c.MoveFraction)
 if math.abs(move)<threshold then return end
 state.Event={Id=b.Key..':'..tostring(e.NextTrade),Contract=b.Key,Direction=move>0 and 1 or -1,
  ExpiresAt=now+c.DisplaySeconds,Time=now,Step=e.Step,FromPrice=first.Price*b.Spec.Tick,ToPrice=b.Last*b.Spec.Tick}
 state.NextEventAt=now+c.CooldownSeconds
end
function Flow.Event(e,key,epoch)
 local b=e.Books[key];local event=b and b.Flow and b.Flow.Event
 if not event or event.ExpiresAt<=e.Time then return nil end
 local result=table.clone(event);result.Id=tostring(epoch or 0)..':'..result.Id
 return result
end
return Flow
