local H=game:GetService('HttpService')
local lab=assert(_G.MomentumLab)
local function root(candidate)
 local f=Instance.new('Folder');f.Name=candidate and 'MomentumCandidateLab'or 'MomentumBaselineLab'
 local shared=Instance.new('Folder');shared.Name='Shared';shared.Parent=f
 for _,s in ipairs(game.ReplicatedStorage.MarketReign:GetChildren())do if s:IsA('ModuleScript')then s:Clone().Parent=shared end end
 for _,s in ipairs(game.ServerScriptService.MarketReign:GetChildren())do if s:IsA('ModuleScript')then
  local m=s:Clone();m.Source=m.Source:gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.');m.Parent=f
 end end
 if candidate then
  for _,name in ipairs({'BotMomentum','BotOrderFlow','Participants','WorldCheckpoint','BotMomentumTests'})do
   local m=f:FindFirstChild(name)or Instance.new('ModuleScript');m.Name=name
   m.Source=H:GetAsync('http://127.0.0.1:8817/candidate/'..name..'.luau'):gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.');m.Parent=f
  end
  shared.MarketConfig.Source=H:GetAsync('http://127.0.0.1:8817/candidate/MarketConfig.luau')
  for _,name in ipairs({'BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotRefreshTests'})do
   f[name].Source=f[name].Source:gsub('CP.Version==25','CP.Version==26'):gsub('CP.Version==24','CP.Version==26')
  end
 end
 return f
end
lab.Baseline=root(false);lab.Candidate=root(true)
lab.Snapshots={}
local cp=require(lab.Baseline.WorldCheckpoint);local config=require(lab.Baseline.Shared.MarketConfig)
for name,record in pairs(lab.Records)do
 local raw=cp.Decode(record.Checkpoint)
 local e,p=cp.Restore(raw,config)
 -- Baseline policy migrations happen once, equally, before either arm branches.
 lab.Snapshots[name]=cp.Capture(e,p)
end
return 'Detached roots and three normalized persisted worlds ready; live modules untouched'
