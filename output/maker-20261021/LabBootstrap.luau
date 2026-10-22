local H=game:GetService('HttpService')
local lab=assert(_G.MakerLab)
local function root(candidate)
 local f=Instance.new('Folder');f.Name=candidate and 'MakerCandidateLab'or 'MakerBaselineLab'
 local shared=Instance.new('Folder');shared.Name='Shared';shared.Parent=f
 for _,s in ipairs(game.ReplicatedStorage.MarketReign:GetChildren())do if s:IsA('ModuleScript')then s:Clone().Parent=shared end end
 for _,s in ipairs(game.ServerScriptService.MarketReign:GetChildren())do if s:IsA('ModuleScript')then
  local m=s:Clone();m.Source=m.Source:gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.');m.Parent=f
 end end
 if candidate then
  for _,name in ipairs({'BotMaker','BotMakerTests','BotOrderFlowTests','BotParticipationTests','BotRefreshTests','BotWhaleTests','MakerLiquidityTests','OrderFlowMarketTests','Participants','WorldCheckpoint'})do
   local m=f:FindFirstChild(name)or Instance.new('ModuleScript');m.Name=name
   m.Source=H:GetAsync('http://127.0.0.1:8819/candidate/'..name..'.luau'):gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.');m.Parent=f
  end
  shared.MarketConfig.Source=H:GetAsync('http://127.0.0.1:8819/candidate/MarketConfig.luau')
 end
 return f
end
lab.Baseline=root(false);lab.Candidate=root(true)
return 'Detached baseline and candidate ready; live sources unchanged'
