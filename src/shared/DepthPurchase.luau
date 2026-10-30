-- Purchase presentation only. Only MarketDepthAccess on the server can grant depth.
local Purchase={}
Purchase.__index=Purchase

function Purchase.new(session,preview,changed,services)
 services=services or{}
 local self=setmetatable({Session=session,Preview=preview,Changed=changed,Alive=true,
  Marketplace=services.Marketplace or game:GetService("MarketplaceService"),
  Player=services.Player or game:GetService("Players").LocalPlayer,Clock=services.Clock or os.clock},Purchase)
 if not preview then
  self.Connection=self.Marketplace.PromptGamePassPurchaseFinished:Connect(function(player,id,purchased)
   if player~=self.Player or id~=self.PromptPass then return end
   self.Prompting=false;self.PromptPass=nil
   -- This client event only controls the waiting label. It never changes entitlement.
   self.VerifyUntil=purchased and self.Clock()+20 or nil
   self:Notify()
  end)
 end
 return self
end
function Purchase:Notify()if self.Alive and self.Changed then self.Changed()end end
function Purchase:Refresh(force)
 if not self.Alive or self.Preview then return end
 local access=self.Session.DepthAccess or{}
 local id=access.PassId
 if type(id)~="number"or id<=0 or id%1~=0 then return end
 if self.PassId~=id then self.PassId=id;self.Info=nil;self.InfoError=nil;self.NextCheck=0 end
 if self.Loading or (not force and self.Clock()<(self.NextCheck or 0))then return end
 self.Loading=true;self:Notify()
 task.spawn(function()
  local ok,info=pcall(self.Marketplace.GetProductInfoAsync,self.Marketplace,id,Enum.InfoType.GamePass)
  if not self.Alive then return end
  self.Loading=false
  if self.PassId~=id then self:Refresh(true);return end
  self.Info=ok and type(info)=="table"and info or nil
  self.InfoError=self.Info==nil
  self.NextCheck=self.Clock()+(self.InfoError and 15 or 30)
  self:Notify()
 end)
end
function Purchase:State()
 local access=self.Session.DepthAccess or{}
 local state={Label="Coming soon",Enabled=false,Note="One-time purchase · Permanent unlock"}
 local info=self.Info
 if info and type(info.IconImageAssetId)=="number"and info.IconImageAssetId>0 then state.Icon="rbxassetid://"..info.IconImageAssetId end
 if self.Preview then state.Label="Play to unlock";return state end
 if access.Allowed==true then state.Label="Owned";state.Note="Market Depth Pro is unlocked.";return state end
 if not access.PassId or access.State=="Unconfigured"then return state end
 if access.State=="Unavailable"then state.Label="Access unavailable";state.Note="Roblox ownership check will retry shortly.";return state end
 if access.State~="Locked"or (self.VerifyUntil and self.Clock()<self.VerifyUntil)then state.Label="Checking access…";return state end
 if self.Prompting then state.Label="Opening Roblox…";return state end
 if self.Loading or self.PassId~=access.PassId or not info and not self.InfoError then state.Label="Loading pass…";return state end
 if self.InfoError then state.Label="Retry";state.Enabled=true;state.Note="Pass details unavailable. Tap to retry.";return state end
 if info.IsForSale~=true then state.Label="Not on sale";state.Note="This pass is not on sale yet.";return state end
 state.Label=self.PromptError and "Retry unlock"or "Unlock L2";state.Enabled=true
 state.Note=self.PromptError and "Could not open Roblox. Tap to retry."or "Roblox confirms the price before you buy."
 return state
end
function Purchase:Prompt()
 if not self.Alive or not self:State().Enabled then return end
 if self.InfoError then self:Refresh(true);return end
 -- Recheck the current server-provided ID immediately before opening Roblox's prompt.
 local access=self.Session.DepthAccess or{}
 if access.Allowed or access.State~="Locked"or access.PassId~=self.PassId or not self.Info or self.Info.IsForSale~=true then return end
 self.Prompting=true;self.PromptPass=self.PassId;self.PromptError=nil;self:Notify()
 local ok=pcall(self.Marketplace.PromptGamePassPurchase,self.Marketplace,self.Player,self.PassId)
 if not self.Alive then return end
 if not ok then self.Prompting=false;self.PromptPass=nil;self.PromptError=true;self:Notify()end
end
function Purchase:Destroy()
 self.Alive=false
 if self.Connection then self.Connection:Disconnect()end
end
return Purchase
