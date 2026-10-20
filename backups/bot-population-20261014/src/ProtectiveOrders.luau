-- Server-owned exits are tied to one position. Client ReduceOnly requests do not
-- acquire this authority. A working TP uses ordinary book price/time priority.
local Protection={}
function Protection.Valid(e,a,o)
 local p=a.Positions[o.Contract]
 if not o.ReduceOnly or not p or o.ProtectivePosition~=p.Id or o.Direction~=-p.Direction then return false end
 if o.Protection=="Take profit"then
  return p.Target~=nil and o.Type=="Limit"and o.Price==math.round(p.Target/e.Books[o.Contract].Spec.Tick)
   and (not p.Triggered or p.Triggered=="Take profit") and not a.Liquidating
 end
 return o.Protection==p.Triggered and (o.Protection=="Stop loss"or o.Protection=="Account depleted"or o.Protection=="Margin liquidation"or o.Protection=="Account reset"and a.Resetting==true)
end
function Protection.Mark(e,a,key)
 if not a.Player then return end
 e.ProtectionDirty=e.ProtectionDirty or {};e.ProtectionDirty[a.Id]=e.ProtectionDirty[a.Id]or {};e.ProtectionDirty[a.Id][key]=true
end
local function ensure(e,a,key,deferred)
 local p=a.Positions[key]
 local exit=p and p.ExitOrder and e.Orders[p.ExitOrder]
 if exit and exit.ReduceOnly and exit.Type=="Market"and exit.Direction==-p.Direction
  and(p.Triggered=="Stop loss"or p.Triggered=="Account depleted"or p.Triggered=="Margin liquidation"or p.Triggered=="Account reset"and a.Resetting)then
  exit.Protection=p.Triggered;exit.ProtectivePosition=p.Id
 end
 local wanted=p and p.Target and (not p.Triggered or p.Triggered=="Take profit")and not a.Locked and not a.Liquidating
 -- Adopt old triggered TP exits without replacing their identity or priority.
 local target=p and (p.TargetOrder or p.Triggered=="Take profit"and p.ExitOrder)
 local o=target and e.Orders[target]
 if wanted and o and o.ReduceOnly and o.Type=="Limit"and o.Direction==-p.Direction and o.Price==math.round(p.Target/e.Books[key].Spec.Tick)then
  o.Protection="Take profit";o.ProtectivePosition=p.Id;p.TargetOrder=o.Id
 end
 local ids={};for id in pairs(a.OpenOrders)do table.insert(ids,id)end;table.sort(ids)
 for _,id in ipairs(ids)do
  local child=e.Orders[id]
  if child and child.Contract==key and child.Protection=="Take profit"then
   if not wanted or child~=o or not Protection.Valid(e,a,child)or child.Remaining<p.Quantity then
    e:Cancel(a.Id,id);if child==o then o=nil end
   elseif child.Remaining>p.Quantity then
    child.Cancelled+=child.Remaining-p.Quantity;child.Remaining=p.Quantity;e:_cleanBook(e.Books[key])
   end
  end
 end
 if not wanted then if p then p.TargetOrder=nil end;return end
 if not o or not e.Orders[o.Id]then
  p.TargetOrder=nil
  local ok,result=e:Submit(a.Id,{Contract=key,Direction=-p.Direction,Quantity=p.Quantity,Type="Limit",Price=p.Target,ReduceOnly=true},
   {Protection="Take profit",PositionId=p.Id,DeferProtection=deferred})
  assert(ok,"Cannot create protective target: "..tostring(result))
 elseif p.Triggered=="Take profit"then p.ExitOrder=o.Id end
end
function Protection.Sync(e,deferred)
 if e.SyncingProtection then return end
 e.SyncingProtection=true
 -- A fill can dirty the same position again while its new target matches.
 local passes=0
 while e.ProtectionDirty and next(e.ProtectionDirty)and passes<200 do
  local dirty=e.ProtectionDirty;e.ProtectionDirty=nil;passes+=1
  local owners={};for owner in pairs(dirty)do table.insert(owners,owner)end;table.sort(owners)
  for _,owner in ipairs(owners)do
   local a=e.Accounts[owner]
   -- Reset can retire an account after cancelling its target marked it dirty.
   if a then for _,key in ipairs(e.Config.ContractOrder)do if dirty[owner][key]then ensure(e,a,key,deferred)end end end
  end
 end
 e.SyncingProtection=nil
end
function Protection.Status(e,a,p,field)
 local closing=p.Triggered==(field=="Target"and "Take profit"or "Stop loss")
 local o=e.Orders[field=="Target"and p.TargetOrder or p.ExitOrder]
 local filled=field=="Target"and(p.TargetFilled or 0)or closing and o and o.Protection=="Stop loss"and o.Filled or 0
 if not closing then return field=="Target"and "Working · awaiting price"or "Armed",filled end
 local reason=o and o.BlockedReason or "Waiting for liquidity"
 if field=="Target"and o and not o.Queued then
  local Policy=require(script.Parent.PlayerExecution)
  reason=Policy.Allows(e,e.Books[o.Contract],o.Price,p.Direction)and "Waiting for liquidity at target"or "Waiting · price safeguard"
 end
 return (filled>0 and filled.." filled · "or "")..p.Quantity.." remaining · "..reason,filled
end
return Protection
