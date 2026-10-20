-- Install only the reviewed UI source in Edit mode. Does not publish or access account storage.
assert(not game:GetService("RunService"):IsRunning(),"Use Edit mode")
local H=game:GetService("HttpService")
local target=game.ReplicatedStorage.MarketReign.TerminalUI
local before=H:GetAsync("http://127.0.0.1:8803/before"):gsub("\r\n","\n")
local source=H:GetAsync("http://127.0.0.1:8803/source"):gsub("\r\n","\n")
assert(target.Source:gsub("\r\n","\n")==before or target.Source:gsub("\r\n","\n")==source,"Studio source changed since capture")
assert(loadstring(source),"Source does not compile")
target.Source=source
assert(target.Source:gsub("\r\n","\n")==source,"Installed source mismatch")
local preview=_G.HelpRedesignPreview
if preview then
 preview.Controller:Destroy();preview.Gui:Destroy();preview.Shared:Destroy();_G.HelpRedesignPreview=nil
end
-- The stored Edit preview is static. Remove the old button affordance here too;
-- the client rebuilds all UI from the installed module when the game starts.
local root=game.StarterGui.MarketReign:FindFirstChild("Workspace")
local summary=root and root:FindFirstChild("AccountSummary",true)
if summary then
 for _,name in ipairs({"BalanceCard","UnrealizedCard"})do
  local old=summary:FindFirstChild(name)
  if old and old:IsA("GuiButton")then
   local card=Instance.new("Frame");card.Name=old.Name
   for _,prop in ipairs({"Size","Position","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderSizePixel","ZIndex","LayoutOrder","Visible","Rotation"})do card[prop]=old[prop]end
   for _,child in ipairs(old:GetChildren())do child.Parent=card end
   card.Parent=summary;old:Destroy()
  end
 end
end
H:PostAsync("http://127.0.0.1:8803/installed",H:JSONEncode({Ok=true,SourceMatches=true,Module=target:GetFullName(),Published=false}),Enum.HttpContentType.ApplicationJson)
return "How to Play installed; balance cards are display-only."
