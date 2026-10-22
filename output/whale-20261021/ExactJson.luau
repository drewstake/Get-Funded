-- Luau tonumber preserves IEEE-754 round trips. The standalone serde decoder can
-- round decimal tokens by an extra ULP; never use that for deterministic snapshots.
local serde=require('@lune/serde')
return function(raw)
 local at=1
 local function space()local _,last=raw:find('^[ \t\r\n]*',at);at=(last or at-1)+1 end
 local parse
 local function str()
  local first=at;at+=1
  while at<=#raw do
   local ch=raw:sub(at,at)
   if ch=='\\'then at+=2
   elseif ch=='"'then at+=1;return serde.decode('json',raw:sub(first,at-1))
   else at+=1 end
  end
  error('Unterminated JSON string')
 end
 parse=function()
  space();local ch=raw:sub(at,at)
  if ch=='"'then return str()end
  if ch=='{'then
   at+=1;space();local t={};if raw:sub(at,at)=='}'then at+=1;return t end
   while true do space();assert(raw:sub(at,at)=='"');local key=str();space();assert(raw:sub(at,at)==':');at+=1;t[key]=parse();space()
    ch=raw:sub(at,at);at+=1;if ch=='}'then return t end;assert(ch==',')
   end
  end
  if ch=='['then
   at+=1;space();local t={};if raw:sub(at,at)==']'then at+=1;return t end
   local i=1;while true do t[i]=parse();i+=1;space();ch=raw:sub(at,at);at+=1;if ch==']'then return t end;assert(ch==',')end
  end
  if raw:sub(at,at+3)=='true'then at+=4;return true end
  if raw:sub(at,at+4)=='false'then at+=5;return false end
  if raw:sub(at,at+3)=='null'then at+=4;return nil end
  local token=raw:match('^[-+%d.eE]+',at);assert(token,'Invalid JSON at '..at);at+=#token;return assert(tonumber(token))
 end
 local result=parse();space();assert(at>#raw,'Trailing JSON');return result
end
