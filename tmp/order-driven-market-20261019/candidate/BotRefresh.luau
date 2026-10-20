-- Accounting-only maintenance. No matching, clock advancement, strategy changes or storage.
local Refresh={}
local function finite(n)return type(n)=="number"and n==n and math.abs(n)<1e15 end
function Refresh.Prepare(engine,population,sequence,actor)
 assert(type(sequence)=="number"and sequence%1==0 and sequence>0,"Invalid refresh sequence")
 local previous=population.BotRefreshReceipt
 if previous and sequence==previous.Sequence then
  assert(actor==previous.Actor,"Refresh receipt actor mismatch")
  return {Receipt=previous,Duplicate=true}
 end
 assert(sequence==(previous and previous.Sequence or 0)+1,"Stale or out-of-order bot refresh")
 local capital=assert(engine.Config.BotPopulation and engine.Config.BotPopulation.Capital,"Bot capital policy required")
 local receipt={Sequence=sequence,Actor=actor,Step=engine.Step,Time=engine.Time,Count=0,Amount=0}
 local plan={Receipt=receipt,Rows={}};local seen={}
 for _,agent in ipairs(population.Agents)do
  local a=assert(engine.Accounts[agent.Id],"Bot account missing")
  assert(not seen[a.Id],"Duplicate bot participant");seen[a.Id]=true
  -- Only current, active strategies receive capital. Legacy archives stay frozen.
  if a.Player or a.House or a.Archive or a.Retired or agent.Retired or agent.Retiring
   or engine.Books[agent.Key].Spec.CloseOnly then continue end
  local target=capital[agent.Kind]
  assert(finite(target)and target>0,"Unknown bot capital allocation: "..tostring(agent.Kind))
  local s=engine:Summary(a);local amount=target-s.Equity
  assert(finite(amount)and finite(a.Realized)and finite(s.Unrealized),"Invalid bot accounting")
  local marks={}
  for key,p in pairs(a.Positions)do
   local b=assert(engine.Books[key],"Missing bot position market")
   local mark=(b.Last or b.Reference)*b.Spec.Tick
   assert(finite(mark)and mark>0 and p.Quantity>0,"Invalid bot mark")
   marks[key]=mark
  end
  local row={Id=a.Id,Marks=marks,Target=target,Amount=amount,Realized=a.Realized,
   Unrealized=s.Unrealized,EquityBefore=s.Equity,BalanceBefore=a.Balance,
   Base=a.Base+amount,Baseline=(a.PnlBaseline or 0)+a.Realized+s.Unrealized}
  table.insert(plan.Rows,row);receipt.Count+=1;receipt.Amount+=amount
 end
 return plan
end
function Refresh.Apply(engine,population,plan)
 if plan.Duplicate then return plan.Receipt end
 local r=plan.Receipt
 for _,row in ipairs(plan.Rows)do
  local a=engine.Accounts[row.Id]
  a.StartingCapital=a.StartingCapital or a.Base
  a.NetCapitalAdjustments=(a.NetCapitalAdjustments or 0)+row.Amount
  a.CapitalAdjustments=a.CapitalAdjustments or {}
  table.insert(a.CapitalAdjustments,{Reason="Owner bot refresh",Sequence=r.Sequence,Actor=r.Actor,Step=r.Step,Time=r.Time,
   Amount=row.Amount,EquityBefore=row.EquityBefore,TargetEquity=row.Target,BalanceBefore=row.BalanceBefore,
   RealizedBefore=row.Realized,UnrealizedSettled=row.Unrealized,CashAdjustment=row.Target-row.BalanceBefore,
   PnlBaseline=row.Baseline})
  -- Base remains contributed capital. Frozen prior P&L reconciles it to spendable cash.
  -- Entry remains the strategy/execution price; only accounting uses PnlEntry.
  a.Base=row.Base;a.PnlBaseline=row.Baseline;a.Realized=0;a.Balance=row.Target
  for key,mark in pairs(row.Marks)do a.Positions[key].PnlEntry=mark end
  a.LossLimit=a.Base;a.Locked=false;a.Revision+=1
 end
 -- Funding can make resting liquidity eligible. Wake exits through their existing
 -- revision check; keep retry deadlines, attempt caps and all order priorities.
 engine.EligibilityRevision=(engine.EligibilityRevision or 0)+1
 population.BotRefreshReceipt=r
 return r
end
-- Copy just the records Apply writes; every other execution/strategy field is read-only.
function Refresh.Preview(engine,population,plan)
 local e=setmetatable(table.clone(engine),getmetatable(engine));e.Accounts=table.clone(engine.Accounts)
 local p=setmetatable(table.clone(population),getmetatable(population));p.Engine=e
 for _,row in ipairs(plan.Rows)do
  local old=engine.Accounts[row.Id];local a=table.clone(old);e.Accounts[row.Id]=a
  a.CapitalAdjustments=table.clone(old.CapitalAdjustments or {});a.Positions={}
  for key,pos in pairs(old.Positions)do a.Positions[key]=table.clone(pos)end
 end
 Refresh.Apply(e,p,plan)
 return e,p
end
return Refresh
