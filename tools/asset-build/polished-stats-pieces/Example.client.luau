-- Disabled in the RBXMX. Enable only to view synthetic sample data.
local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local Kit=require(script.Parent:WaitForChild("StatsPieces"))
local demo=HttpService:JSONDecode([====[__FIXTURES__]====])
local controller=Kit.Mount(Players.LocalPlayer:WaitForChild("PlayerGui"),demo.All.Life,{
 OnFilter=function(scope,period)return demo[scope] and demo[scope][period]end,
 OnNavigate=function(name)print("Connect navigation to:",name)end,
})
script.Destroying:Connect(function()controller:Destroy()end)

