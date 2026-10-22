-- Participation health and zero-sum capital recycling between simulated bots.
-- Recovery never edits price, inventory, trading P&L or player accounts.
local H={}
local Retry=require(script.Parent.BotExitRetry)
local function enabled(e,a,ac)
 return e.Config.BotParticipation and e.Config.BotPopulation and a.Budget and not a.Retiring and not a.Retired
  and not e.Books[a.Key].Spec.CloseOnly and not ac.Player and not ac.House and not ac.Archive
end
local function stagger(id,span)
 local hash=0;for i=1,#id do hash=(hash*31+string.byte(id,i))%65521 end
 return hash%math.max(1,span)
end
function H.Risk(e,a,summary)
 local ac=e.Accounts[a.Id];local c=e.Config.BotParticipation
 if not enabled(e,a,ac)then return nil end
 local equity=summary.Equity;local margin=e.Books[a.Key].Spec.Margin
 if equity<=0 or math.floor(equity*ac.Risk*e.Config.BotPopulation.MarginFraction/margin)<1 then return 'Underfunded' end
 local drawdown=c.MaxDrawdown
 if a.Kind=='Liquidity'and e.Config.BotLiquidity then drawdown=e.Config.BotLiquidity.MaxDrawdown
 elseif e.Config.BotOrderFlow and e.Config.BotOrderFlow.Kinds[a.Kind]then drawdown=e.Config.BotOrderFlow.MaxDrawdown end
 if equity<=a.Budget*(1-drawdown)then return 'Risk paused' end
 return nil
end
function H.Inspect(e,a,summary)
 local ac=e.Accounts[a.Id];local c=e.Config.BotParticipation or {}
 local recent=ac.LastBotFillAt~=nil and e.Time-ac.LastBotFillAt<=(c.RecentSeconds or 300)
 local quoting=false
 for id in pairs(ac.OpenOrders)do local o=e.Orders[id]
  if o and not o.ReduceOnly and not o.Queued and o.Type=='Limit'and e:_available(o,true)>0 then quoting=true;break end
 end
 local state
 if a.Retiring or a.Retired or e.Books[a.Key].Spec.CloseOnly then state='Retired'
 else
  state=H.Risk(e,a,summary)
  if not state and a.RecoveryReadyAt then state='Recovering' end
  if not state and (ac.Locked or ac.Liquidating)then state='Risk paused' end
  if not state and ((a.FlowCooldownUntil or 0)>e.Time or (a.ReadyAt or 0)>e.Time or (a.ParticipationResumeAt or 0)>e.Time)then state='Cooldown' end
  if not state then state=recent and 'Trading' or quoting and 'Quoting' or next(ac.Positions)and 'Holding' or 'Waiting' end
 end
 local eligible=state=='Trading'or state=='Quoting'or state=='Holding'or state=='Waiting'
 return state,recent,quoting,eligible
end
function H.Step(p,a)
 local e=p.Engine;local ac=e.Accounts[a.Id];local c=e.Config.BotParticipation
 if not enabled(e,a,ac)then return false end
 local risk=H.Risk(e,a,e:Summary(ac))
 if risk and not a.RecoveryReadyAt then
  a.RecoveryReadyAt=e.Time+c.CooldownSeconds+stagger(a.Id,c.StaggerSeconds)
  a.OrderObjective=nil;a.FlowPositionId=nil;a.FlowCooldownUntil=nil
 end
 if not a.RecoveryReadyAt then return (a.ParticipationResumeAt or 0)>e.Time end
 -- Withdraw only entries. Stops and working reduce-only exits keep their authority.
 local ids={};for id in pairs(ac.OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly then table.insert(ids,id)end end
 table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
 for _,key in ipairs(e.Config.ContractOrder)do local pos=ac.Positions[key]
  if pos and not pos.Triggered and not pos.ExitOrder and Retry.Ready(e,ac,key,pos)then
   local ok,result=e:Submit(a.Id,{Contract=key,Direction=-pos.Direction,Quantity=math.min(pos.Quantity,c.ExitSliceContracts,a.Size),Type='Market',ReduceOnly=true})
   if not ok or result.Filled==0 then Retry.Attempted(e,ac,key,pos)end
  end
 end
 return true
end
local function adjust(e,ac,amount)
 ac.StartingCapital=ac.StartingCapital or ac.Base
 ac.NetCapitalAdjustments=(ac.NetCapitalAdjustments or 0)+amount
 ac.ParticipationCapitalNet=(ac.ParticipationCapitalNet or 0)+amount
 ac.Base=ac.StartingCapital+ac.NetCapitalAdjustments
 ac.Balance=ac.Base+(ac.PnlBaseline or 0)+ac.Realized
 ac.LossLimit=ac.Base;ac.Revision+=1
 e.EligibilityRevision=(e.EligibilityRevision or 0)+1
end
function H.Rebalance(p)
 local e=p.Engine;local c=e.Config.BotParticipation
 if not c or e.Time<(p.NextParticipationReview or 0)then return end
 p.NextParticipationReview=e.Time+c.ReviewSeconds
 local donors,waiting={},{}
 for _,a in ipairs(p.Agents)do local ac=e.Accounts[a.Id]
  if enabled(e,a,ac)then
   local s=e:Summary(ac)
   if a.RecoveryReadyAt and e.Time>=a.RecoveryReadyAt and not next(ac.Positions)and not next(ac.OpenOrders)then
    table.insert(waiting,a)
   elseif not a.RecoveryReadyAt and not ac.Locked and not ac.Liquidating then
    -- Only realized cash surplus is distributable; keep unrealized gains and all reserved margin.
    local spare=math.floor(math.max(0,math.min(ac.Balance,s.Equity)-a.Budget*c.DonorFloorFraction)*100)/100
    if spare>0 then
     local lo,hi=0,math.floor(spare*100)
     while lo<hi do local mid=math.ceil((lo+hi)/2)
      if e:Exposure(ac,a.Key,1,0,{Equity=s.Equity-mid/100})then lo=mid else hi=mid-1 end
     end
     if lo>0 then table.insert(donors,{Agent=a,Available=lo/100})end
    end
   end
  end
 end
 table.sort(donors,function(a,b)return a.Agent.Id<b.Agent.Id end)
 table.sort(waiting,function(a,b)if a.RecoveryReadyAt~=b.RecoveryReadyAt then return a.RecoveryReadyAt<b.RecoveryReadyAt end return a.Id<b.Id end)
 for _,a in ipairs(waiting)do
  local ac=e.Accounts[a.Id];local need=math.max(0,math.ceil((a.Budget*c.RecoveryFraction-ac.Balance)*100)/100)
  local available=0;for _,d in ipairs(donors)do if d.Agent.Key==a.Key then available+=d.Available end end
  -- Atomic full recovery, never repeated tiny top-ups to a permanently paused bot.
  if available+.001>=need then
   local remaining=need
   for _,d in ipairs(donors)do if d.Agent.Key==a.Key and remaining>0 then
    local amount=math.min(d.Available,remaining)
    if amount>0 then adjust(e,e.Accounts[d.Agent.Id],-amount);adjust(e,ac,amount);d.Available-=amount;remaining-=amount end
   end end
   ac.Locked=false;ac.Liquidating=nil
   ac.ParticipationRecoveries=(ac.ParticipationRecoveries or 0)+1
   ac.LastParticipationRecovery=e.Time
   a.RecoveryReadyAt=nil;a.OrderObjective=nil;a.FlowPositionId=nil;a.FlowCooldownUntil=nil
   a.Quotes={};a.ReplenishAt={};a.LiquidityQuotes={};a.Parent=0
   a.ParticipationResumeAt=e.Time+1+stagger(a.Id,c.ResumeStaggerSeconds)
   a.Next=a.ParticipationResumeAt;a.FlowNextDecision=a.Next
   p.ParticipationRecovered=(p.ParticipationRecovered or 0)+1
   p.ParticipationTransferred=(p.ParticipationTransferred or 0)+need
  end
 end
end
return H