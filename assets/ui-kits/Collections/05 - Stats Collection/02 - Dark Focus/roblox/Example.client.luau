-- Disabled by default. Enable only for a separate sample preview during Play.
local Players=game:GetService("Players")
local Kit=require(script.Parent:WaitForChild("StatsKit"))
local sample={
 Net=-56808.75,Gains=12881,Loss=69689.75,Wins=12,Losses=29,Even=0,Trades=41,
 AvgWin=12881/12,AvgLoss=69689.75/29,WinRate=12/41,
 WinLossRatio=(12881/12)/(69689.75/29),ProfitFactor=12881/69689.75,
 NoLosses=false,DailyComplete=false,Partial=false,CountUnknown=false,Attempts=7,Blown=6,
}
local controller=Kit.Mount(Players.LocalPlayer:WaitForChild("PlayerGui"),sample,{AccountLabel="SAMPLE · $5K Funded #5"})
-- Bind server aggregates with controller:Update(aggregate). Do not calculate production stats on the client.
script.Destroying:Connect(function() controller:Destroy() end)
