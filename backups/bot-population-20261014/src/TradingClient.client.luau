local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local player=Players.LocalPlayer
local screen=script.Parent
local ui=require(game:GetService("ReplicatedStorage"):WaitForChild("MarketReign"):WaitForChild("TerminalUI"))
local controller=ui.Mount(screen)
-- Private replies for the server-owned /reset command. This remote has no server event handler.
local noticeConnection
task.spawn(function()
 local remote=game:GetService("ReplicatedStorage").MarketReign:WaitForChild("OwnerNotice")
 noticeConnection=remote.OnClientEvent:Connect(function(message)
  if type(message)~="string"then return end
  local channels=game:GetService("TextChatService"):FindFirstChild("TextChannels")
  local channel=channels and (channels:FindFirstChild("RBXSystem")or channels:FindFirstChild("RBXGeneral"))
  if channel then
   local safe=message:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;")
   channel:DisplaySystemMessage("[Get Funded!] "..safe)
  end
 end)
end)
-- Keep the Roblox system menu, but prevent avatar controls covering the trading workspace.
pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false)end)
pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health,false)end)
pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false)end)
game:GetService("GuiService").TouchControlsEnabled=false
-- Humanoid state switches are local to each simulation; disable jumping on the client too.
-- CharacterAdded covers respawns even though this ScreenGui survives them.
local function disableJump(character)
 local humanoid=character:WaitForChild("Humanoid",10)
 if not humanoid or player.Character~=character then return end
 humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
 humanoid.AutoJumpEnabled=false;humanoid.Jump=false;humanoid:Move(Vector3.zero)
end
local characterConnection=player.CharacterAdded:Connect(disableJump)
if player.Character then task.spawn(disableJump,player.Character)end
screen.Destroying:Connect(function()
 characterConnection:Disconnect();if noticeConnection then noticeConnection:Disconnect()end;controller:Destroy()
end)
print("[Get Funded!] Native trading workspace ready. Server-authoritative order book.")
