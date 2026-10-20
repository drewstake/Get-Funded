-- Server-only entitlement and packet boundary. Ownership is always verified by Roblox.
-- PassId=0 disables access; there is no Studio or client ownership bypass.
local Access={PassId=2006894567}
Access.__index=Access

function Access.new(passId,marketplace,clock)
 return setmetatable({PassId=passId or Access.PassId,Marketplace=marketplace or game:GetService("MarketplaceService"),Clock=clock or os.clock,Players={}},Access)
end
function Access:Configured()
 local id=self.PassId
 return type(id)=="number"and id>0 and id<math.huge and id%1==0
end
function Access:Refresh(player,force)
 if not self:Configured()then return end
 local state=self.Players[player]
 if not state then state={Allowed=false,State="Checking",NextCheck=0};self.Players[player]=state end
 if state.Busy then if force then state.Recheck=true end;return end
 if not force and self.Clock()<state.NextCheck then return end
 state.Busy=true
 task.spawn(function()
  local ok,owned=pcall(self.Marketplace.UserOwnsGamePassAsync,self.Marketplace,player.UserId,self.PassId)
  if self.Players[player]~=state then return end
  state.Busy=false;state.Allowed=ok and owned==true
  state.State=not ok and "Unavailable"or state.Allowed and "Owned"or "Locked"
  state.NextCheck=self.Clock()+(ok and 120 or 15)
  if state.Recheck then state.Recheck=nil;self:Refresh(player,true)end
 end)
end
function Access:Status(player)
 if not self:Configured()then return {Allowed=false,State="Unconfigured"}end
 local state=self.Players[player]
 return {Allowed=state~=nil and state.Allowed==true,State=state and state.State or "Checking",PassId=self.PassId}
end
function Access:Apply(packet,player,contract)
 packet.DepthAccess=self:Status(player)
 for symbol,quote in pairs(packet.Quotes or{})do
  if not packet.DepthAccess.Allowed or symbol~=contract then quote.Depth=nil end
 end
end
function Access:Forget(player)self.Players[player]=nil end
return Access
