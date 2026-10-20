-- Server-only command policy. Dependencies keep security and lookup tests off real profiles.
local Command={} Command.__index=Command
function Command.Parse(text)
 if type(text)~="string" or #text>80 then return nil end
 local alias,name=text:match("^%s*(%S+)%s+@?([%w_]+)%s*$")
 if not alias or alias:lower()~="/reset" or #name<3 or #name>20 then return nil end
 return name
end
function Command.IsOwner(userId,creatorType,creatorId,groupLookup)
 if type(userId)~="number" or userId<=0 or creatorId<=0 then return false end
 if creatorType==Enum.CreatorType.User then return userId==creatorId end
 if creatorType~=Enum.CreatorType.Group then return false end
 local ok,info=pcall(groupLookup,creatorId)
 return ok and type(info)=="table" and type(info.Owner)=="table" and info.Owner.Id==userId
end
function Command.new(options)
 return setmetatable({Options=options,Busy=false,LastAt=setmetatable({},{__mode="k"})},Command)
end
function Command:Handle(player,text)
 local o=self.Options local now=(o.Now or os.clock)()
 if now-(self.LastAt[player] or -math.huge)<2 then return end
 self.LastAt[player]=now
 if not Command.IsOwner(player.UserId,o.CreatorType,o.CreatorId,o.GroupLookup)then
  o.Notify(player,"Only the experience owner can use /reset.");return
 end
 local name=Command.Parse(text)
 if not name then o.Notify(player,"Usage: /reset <exact Roblox username>");return end
 if self.Busy then o.Notify(player,"A reset is already in progress. Please wait.");return end
 if not o.Ready()then o.Notify(player,"The saved exchange is busy or unavailable. Try /reset again shortly.");return end
 self.Busy=true
 local ok,err=pcall(function()
  local found,uid,canonical=pcall(o.Resolve,name)
  if not found or type(uid)~="number" or uid<=0 or type(canonical)~="string" or canonical:lower()~=name:lower()then
   o.Notify(player,"Username not found. Use the exact current Roblox username, not a display name.");return
  end
  o.Notify(player,"Resetting @"..canonical.."...")
  local saved,message=o.Reset(uid,canonical)
  o.Notify(player,message)
  if saved and o.AfterReset then o.AfterReset(uid)end
 end)
 self.Busy=false
 if not ok then
  warn("[Get Funded!] Owner reset failed: "..tostring(err))
  o.Notify(player,"Reset could not be confirmed. Wait for the saved exchange to recover, then check the player before retrying.")
 end
end
return Command
