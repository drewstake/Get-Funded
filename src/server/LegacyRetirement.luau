-- One-time administrative settlement of closed markets. Never generates a trade,
-- candle, reward, funding adjustment or random draw. Archived records are audit-only.
local TradeStats=require(script.Parent.TradeStats)
local Retirement={Version=2}
local function copy(v)
 if type(v)~='table'then return v end
 local out={}for k,x in pairs(v)do out[k]=copy(x)end return out
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e15 end
function Retirement.Apply(e,p)
 local version=e.Config.MarketRetirementVersion or 0
 assert(version<=Retirement.Version,'Unsupported market retirement policy')
 if version==0 then return nil end
 local closed={};local count=0
 for _,key in ipairs(e.Config.ContractOrder)do
  if e.Books[key].Spec.CloseOnly then closed[key]=true;count+=1 end
 end
 local existing=e.MarketRetirement
 assert(not existing or existing.Version>=1 and existing.Version<=version,'Inconsistent market retirement archive')
 if count==0 then
  if existing and existing.Version<version then
   e.MarketRetirement=copy(existing);e.MarketRetirement.Version=version
  end
  return e.MarketRetirement
 end
 local archive=existing and copy(existing)or{Version=version,Step=e.Step,Time=e.Time,Markets={},Accounts={},Agents={},Settlements={},CancelledOrders={}}
 archive.Version=version
 local settlements,retired,net={},{},{}
 for key in pairs(closed)do
  assert(not archive.Markets[key],'Market already archived: '..key);net[key]=0
  local b=e.Books[key];local mark=(b.Last or b.Reference)*b.Spec.Tick
  assert(finite(mark)and mark>0,'Invalid legacy settlement price')
 end
 -- Validate the entire operation before changing any account or order.
 for _,a in ipairs(p.Agents)do if closed[a.Key]then
  assert(not retired[a.Id],'Duplicate legacy participant')
  local account=assert(e.Accounts[a.Id],'Missing legacy account')
  assert(not account.Player and not account.House and not account.Archive,'Invalid legacy participant')
  for key in pairs(account.Positions)do assert(closed[key],'Legacy bot holds an active-market position')end
  for id in pairs(account.OpenOrders)do assert(closed[e.Orders[id].Contract],'Legacy bot has an active-market order')end
  retired[a.Id]=true
 end end
 for _,id in ipairs(e.AccountOrder)do local a=e.Accounts[id]
  for key,pos in pairs(a.Positions)do if closed[key]then
   local b=e.Books[key];local mark=(b.Last or b.Reference)*b.Spec.Tick
   assert(pos.Quantity>0 and pos.Quantity%1==0 and(pos.Direction==1 or pos.Direction==-1),'Invalid legacy position')
   local pnl=(mark-(pos.PnlEntry or pos.Entry))*pos.Quantity*pos.Direction*b.Spec.Multiplier
   assert(finite(pnl),'Invalid legacy settlement P&L');net[key]+=pos.Quantity*pos.Direction
   table.insert(settlements,{Owner=id,Contract=key,Position=copy(pos),Price=mark,Pnl=pnl,
    Notional=mark*pos.Quantity*pos.Direction*b.Spec.Multiplier,Step=e.Step,Time=e.Time,Reason='Retired market cash settlement'})
  end end
 end
 for key,quantity in pairs(net)do assert(quantity==0,'Unbalanced legacy inventory: '..key)end
 table.sort(settlements,function(a,b)return a.Owner==b.Owner and a.Contract<b.Contract or a.Owner<b.Owner end)
 local orders={};for id,o in pairs(e.Orders)do if closed[o.Contract]then table.insert(orders,id)end end;table.sort(orders)
 for _,id in ipairs(orders)do local o=e.Orders[id]
  e:Cancel(o.Owner,id);table.insert(archive.CancelledOrders,copy(o))
 end
 for _,row in ipairs(settlements)do local a=e.Accounts[row.Owner]
  row.BalanceBefore=a.Balance
  a.CashFlow+=row.Notional;a.Realized+=row.Pnl;a.Balance=a.Base+(a.PnlBaseline or 0)+a.Realized
  a.Positions[row.Contract]=nil;a.Revision+=1;row.BalanceAfter=a.Balance
  -- Administrative settlement is not a completed trade or a reward event.
  if a.Player then TradeStats.Reconcile(e,a,os.time());e:ContractLimit(a)end
  table.insert(archive.Settlements,row)
 end
 local agents={};for _,a in ipairs(p.Agents)do
  if retired[a.Id]then a.Retiring=nil;a.Retired=true;table.insert(archive.Agents,a)else table.insert(agents,a)end
 end;p.Agents=agents
 local accounts={};for _,id in ipairs(e.AccountOrder)do local a=e.Accounts[id]
  if retired[id]then
   assert(not next(a.Positions)and not next(a.OpenOrders),'Legacy account is not flat')
   a.Retired=true;a.Locked=true;a.Liquidating=nil
   table.insert(archive.Accounts,a);e.Accounts[id]=nil
   if e.ReductionDirty then e.ReductionDirty[id]=nil end
  else table.insert(accounts,id)end
 end;e.AccountOrder=accounts
 local pending={};for _,row in ipairs(e.PendingStops or {})do if not closed[row.Contract]then table.insert(pending,row)end end;e.PendingStops=pending
 local order={};for _,key in ipairs(e.Config.ContractOrder)do
  if closed[key]then
   local b=e.Books[key];assert(not b.Bids[1]and not b.Asks[1],'Legacy order book not empty')
   archive.Markets[key]={Book=b,Signal=p.Markets[key],SettledAt=e.Time,SettledStep=e.Step,Price=(b.Last or b.Reference)*b.Spec.Tick}
   e.Books[key]=nil;p.Markets[key]=nil
  else table.insert(order,key)end
 end;e.Config.ContractOrder=order
 e.MarketRetirement=archive
 -- Rebuild derived order indexes after removing closed-market orders.
 e.Stops=nil;e.StopDirty=nil
 return archive
end
return Retirement
