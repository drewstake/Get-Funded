-- One dollar-to-tick calculation shared by the ticket and authoritative exchange.
-- Dollars are the estimated TOTAL for the requested quantity, excluding slippage.
local Protection={}
Protection.Defaults={StopOn=true,TargetOn=true,StopDollars=500,TargetDollars=1500}
-- Preferences are dollar intentions, independent of the current instrument/quantity.
-- Resolve still enforces the instrument's 10,000-tick limit when an order is placed.
function Protection.Preferences(value)
 local result={}
 for key,default in pairs(Protection.Defaults)do
  local v;if type(value)=="table"then v=value[key]end
  if type(default)=="boolean"then
   if type(v)=="boolean"then result[key]=v else result[key]=default end
  else result[key]=type(v)=="number"and v==v and v>=.01 and v<=1e9 and v or default end
 end
 return result
end
function Protection.ValidatePreferences(value)
 if type(value)~="table"then return nil end
 for key,default in pairs(Protection.Defaults)do
  local v=value[key]
  if type(v)~=type(default)then return nil end
  if type(v)=="number"and(v~=v or v<.01 or v>1e9)then return nil end
 end
 return Protection.Preferences(value)
end
function Protection.SamePreferences(a,b)
 for key in pairs(Protection.Defaults)do if a[key]~=b[key]then return false end end
 return true
end
function Protection.Resolve(spec,quantity,dollars,entry,direction,field)
 if type(quantity)~="number" or quantity<1 or quantity%1~=0 then return nil,"Enter a whole number of contracts, starting at 1." end
 local unit=spec.Tick*spec.Multiplier*quantity
 if type(dollars)~="number" or dollars~=dollars or dollars<=0 or dollars==math.huge or dollars>unit*10000 then
  return nil,"Enter a protection amount above $0 and within 10,000 price ticks for this quantity."
 end
 local ticks=math.max(1,math.round(dollars/unit))
 local result={Ticks=ticks,Dollars=ticks*unit,TickDollars=unit}
 if entry then
  local side=(field=="Stop" and -1 or 1)*(direction or 1)
  result.Price=math.round((entry+side*ticks*spec.Tick)/spec.Tick)*spec.Tick
  result.Dollars=math.abs(result.Price-entry)*spec.Multiplier*quantity
 end
 return result
end
return Protection
