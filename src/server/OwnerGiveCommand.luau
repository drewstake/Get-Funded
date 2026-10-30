-- Server-only chat command. Uses the same creator/group-owner policy as /reset.
local Owner=require(script.Parent.OwnerResetCommand)
local Command={MaxAmount=1000000000000};Command.__index=Command
local powers={k=3,m=6,b=9,t=12}
function Command.Parse(text)
 if type(text)~="string"or #text>100 then return nil end
 local alias,name,token=text:match("^%s*(%S+)%s+@?([%w_]+)%s+(%S+)%s*$")
 if not alias or alias:lower()~="/give"or #name<3 or #name>20 then return nil end
 local digits,suffix=token:lower():match("^([%d%.]+)([kmbt]?)$")
 if not digits then return nil end
 local whole,fraction=digits:match("^(%d+)%.(%d+)$")
 if not whole then whole=digits:match("^(%d+)$");fraction=""end
 if not whole then return nil end
 fraction=fraction:gsub("0+$","")
 local power=powers[suffix]or 0
 -- Scale decimal digits as integers so 1.001k is exactly 1001 dollars.
 if #fraction>power then return nil end
 local amount=tonumber(whole..fraction)*10^(power-#fraction)
 if not amount or amount<1 or amount>Command.MaxAmount or amount%1~=0 then return nil end
 return name,amount
end
function Command.new(options)return setmetatable({Options=options,Busy=false,LastAt=setmetatable({},{__mode="k"})},Command)end
function Command:Handle(player,text)
 local o=self.Options;local now=(o.Now or os.clock)()
 if now-(self.LastAt[player]or -math.huge)<2 then return end;self.LastAt[player]=now
 if not Owner.IsOwner(player.UserId,o.CreatorType,o.CreatorId,o.GroupLookup)then o.Notify(player,"Only the experience owner can use /give.");return end
 local name,amount=Command.Parse(text)
 if not name then o.Notify(player,"Usage: /give <exact Roblox username> <amount>. Examples: 1k, 1.5m, 10m, 1b, 1t. Range: $1–$1 trillion, whole dollars.");return end
 if self.Busy then o.Notify(player,"A money grant is already being saved. Please wait.");return end
 if not o.Ready()then o.Notify(player,"The saved exchange is busy or unavailable. Try /give again shortly.");return end
 self.Busy=true
 local ok,err=pcall(function()
  local found,uid,canonical=pcall(o.Resolve,name)
  if not found or type(uid)~="number"or uid<=0 or uid%1~=0 or type(canonical)~="string"or canonical:lower()~=name:lower()then
   o.Notify(player,"Username not found. Use the exact current Roblox username, not a display name.");return
  end
  local saved,message=o.Give(uid,canonical,amount,player.UserId)
  o.Notify(player,message)
 end)
 self.Busy=false
 if not ok then
  warn("[Get Funded!] Owner give failed: "..tostring(err))
  o.Notify(player,"Grant could not be confirmed. Check the saved balance before retrying /give.")
 end
end
return Command
