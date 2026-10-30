-- One dollar-to-tick calculation shared by the ticket and authoritative exchange.
-- Dollars are the estimated TOTAL for the requested quantity, excluding slippage.
local Protection={}
-- A partially filled profit target is still editable protection on live inventory.
-- Stops, voluntary closes and account liquidation retain their closing authority.
function Protection.CanEdit(position,account)
 return position~=nil and (position.Quantity or 0)>0 and position.ProtectionEditable~=false
  and (not position.Triggered or position.Triggered=="Take profit")
  and not(account and (account.Locked or account.Liquidating or account.Resetting))
end
Protection.MaxDollars=1e9
Protection.Defaults={StopOn=true,TargetOn=true,StopDollars=500,TargetDollars=1500}
-- Preferences are dollar intentions, independent of the current instrument/quantity.
-- The ticket, saved preferences and exchange share the same dollar ceiling.
function Protection.Preferences(value)
 local result={}
 for key,default in pairs(Protection.Defaults)do
  local v;if type(value)=="table"then v=value[key]end
  if type(default)=="boolean"then
   if type(v)=="boolean"then result[key]=v else result[key]=default end
  else result[key]=type(v)=="number"and v==v and v>=.01 and v<=Protection.MaxDollars and v or default end
 end
 return result
end
function Protection.ValidatePreferences(value)
 if type(value)~="table"then return nil end
 for key,default in pairs(Protection.Defaults)do
  local v=value[key]
  if type(v)~=type(default)then return nil end
  if type(v)=="number"and(v~=v or v<.01 or v>Protection.MaxDollars)then return nil end
 end
 return Protection.Preferences(value)
end
function Protection.SamePreferences(a,b)
 for key in pairs(Protection.Defaults)do if a[key]~=b[key]then return false end end
 return true
end
function Protection.MaximumTicks(spec,quantity)
 -- Include the nearest tick at the dollar ceiling, including the one-tick minimum.
 return math.max(1,math.round(Protection.MaxDollars/(spec.Tick*spec.Multiplier*quantity)))
end
function Protection.ValidPrice(spec,price)
 return type(price)=="number"and price==price and price>0 and price<1e12
  and math.abs(price/spec.Tick-math.round(price/spec.Tick))<=.00001
end
function Protection.TargetPrice(spec,entry,direction,ticks)
 local price=math.round((entry+direction*ticks*spec.Tick)/spec.Tick)*spec.Tick
 if Protection.ValidPrice(spec,price)then return price end
 return nil
end
function Protection.Resolve(spec,quantity,dollars,entry,direction,field)
 if type(quantity)~="number" or quantity<1 or quantity%1~=0 then return nil,"Enter a whole number of contracts, starting at 1." end
 local unit=spec.Tick*spec.Multiplier*quantity
 if type(dollars)~="number" or dollars~=dollars or dollars<.01 or dollars>Protection.MaxDollars then
  return nil,"Enter a protection amount from $0.01 to $1,000,000,000."
 end
 local ticks=math.max(1,math.round(dollars/unit))
 local result={Ticks=ticks,Dollars=ticks*unit,TickDollars=unit}
 if entry then
  local side=(field=="Stop" and -1 or 1)*(direction or 1)
  result.Price=math.round((entry+side*ticks*spec.Tick)/spec.Tick)*spec.Tick
  if field=="Target"and not Protection.ValidPrice(spec,result.Price)then
   return nil,"Take profit must resolve to a positive market price. Reduce the take-profit amount."
  end
  result.Dollars=math.abs(result.Price-entry)*spec.Multiplier*quantity
 end
 return result
end
return Protection
