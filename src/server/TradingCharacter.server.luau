-- Get Funded! is a trading workspace: avatars stay stationary on every spawn.
-- Scriptable movement supports both legacy controls and Roblox's Input Action System.
local Players=game:GetService("Players")
local StarterPlayer=game:GetService("StarterPlayer")
StarterPlayer.DevComputerMovementMode=Enum.DevComputerMovementMode.Scriptable
StarterPlayer.DevTouchMovementMode=Enum.DevTouchMovementMode.Scriptable
StarterPlayer.CharacterWalkSpeed=0
StarterPlayer.CharacterJumpPower=0
StarterPlayer.CharacterJumpHeight=0
StarterPlayer.AutoJumpEnabled=false

local function lockCharacter(character)
 local root=character:WaitForChild("HumanoidRootPart",10)
 if not root then return end
 root.Anchored=true
 root.AssemblyLinearVelocity=Vector3.zero
 root.AssemblyAngularVelocity=Vector3.zero
 local humanoid=character:WaitForChild("Humanoid",10)
 if not humanoid then return end
 humanoid.WalkSpeed=0;humanoid.JumpPower=0;humanoid.JumpHeight=0
 humanoid.AutoRotate=false;humanoid.AutoJumpEnabled=false;humanoid.Jump=false
 humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
 humanoid:Move(Vector3.zero)
end
local function add(player)
 player.DevComputerMovementMode=Enum.DevComputerMovementMode.Scriptable
 player.DevTouchMovementMode=Enum.DevTouchMovementMode.Scriptable
 player.CharacterAdded:Connect(lockCharacter)
 if player.Character then task.spawn(lockCharacter,player.Character)end
end
Players.PlayerAdded:Connect(add)
for _,player in ipairs(Players:GetPlayers())do add(player)end
