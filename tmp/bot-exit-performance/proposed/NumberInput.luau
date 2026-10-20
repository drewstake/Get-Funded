-- Human-entered decimal numbers; field-specific bounds and rounding stay with the caller.
local NumberInput={}
local multipliers={k=1e3,m=1e6,b=1e9,t=1e12}
function NumberInput.Parse(text)
 if type(text)~="string"then return nil end
 local raw=text:match("^%s*(.-)%s*$")
 if raw:sub(1,1)=="$"then raw=raw:sub(2):match("^%s*(.-)%s*$")end
 local amount,suffix=raw:match("^(.-)%s*([kKmMbBtT])$")
 amount=amount or raw
 local sign,whole,decimal=amount:match("^([+-]?)([%d,]*)%.?(%d*)$")
 if not whole or whole==""and decimal==""then return nil end
 if whole:find(",",1,true)then
  local first,rest=whole:match("^(%d%d?%d?)(,.*)$")
  if not first or rest:gsub(",%d%d%d","")~=""then return nil end
 end
 local value=tonumber(sign..whole:gsub(",","").."."..decimal)
 if not value then return nil end
 value*=suffix and multipliers[suffix:lower()]or 1
 if value~=value or math.abs(value)==math.huge then return nil end
 return value
end
return NumberInput
