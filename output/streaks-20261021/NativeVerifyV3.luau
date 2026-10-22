local H=game:GetService('HttpService')
local lab={Done=false,Phase='Loading'};_G.StreakLab=lab
local f=Instance.new('Folder');f.Name='StreakCandidateLab';lab.Root=f
local shared=Instance.new('Folder');shared.Name='Shared';shared.Parent=f
for _,m in ipairs(game.ReplicatedStorage.MarketReign:GetChildren())do if m:IsA('ModuleScript')then m:Clone().Parent=shared end end
for _,m in ipairs(game.ServerScriptService.MarketReign:GetChildren())do if m:IsA('ModuleScript')then local n=m:Clone();n.Source=n.Source:gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.');n.Parent=f end end
for _,name in ipairs({'BotMomentum','BotMomentumTests','Participants','WorldCheckpoint','MakerLiquidityTests','BotOrderFlowTests','BotParticipationTests','BotRefreshTests','BotWhaleTests','OrderFlowMarketTests'})do
 f[name].Source=H:GetAsync('http://127.0.0.1:8821/candidate-v3/'..name..'.luau'):gsub('game.ReplicatedStorage.MarketReign%.','script.Parent.Shared.')
end
shared.MarketConfig.Source=H:GetAsync('http://127.0.0.1:8821/candidate-v3/MarketConfig.luau')
task.spawn(function()
 local ok,err=pcall(function()
  lab.Phase='Native parity';local CP=require(f.WorldCheckpoint);local C=require(shared.MarketConfig)
  local e,p=CP.Restore(H:JSONDecode(H:GetAsync('http://127.0.0.1:8821/snapshots/normalized-Seed71.json')),C)
  for i=1,400 do p:Step();if i%20==0 then task.wait()end end
  local raw=H:JSONEncode(CP.Capture(e,p));local parts=math.ceil(#raw/500000)
  for i=1,parts do H:PostAsync('http://127.0.0.1:8821/native-parity-'..i..'.part',raw:sub((i-1)*500000+1,i*500000),Enum.HttpContentType.TextPlain);task.wait()end
  lab.Parity={Parts=parts,Hash=e.TradeHash,Audit=e:Audit()}
  for _,name in ipairs({'BotExitRetryTests','BotFairnessTests','BotMomentumTests','BotOrderFlowTests','BotParticipationTests','BotPublicInformationTests','BotRefreshTests','BotSignalsTests','BotWhaleTests','ExecutionChoiceTests','ExecutionIntegrityTests','MakerLiquidityTests','MarketTests','OrderFlowMarketTests','ProtectionScaleTests','ProtectiveOrdersTests','ScalperTests','SecurityTests','SharedDepthTests','TradeLimitsTests','WorldTests'})do
   lab.Phase=name;task.wait()
   local pass,result=pcall(function()return require(f[name]).Run()end)
   H:PostAsync('http://127.0.0.1:8821/suites/Candidate-'..name..'.json',H:JSONEncode({Suite=name,Ok=pass,Results=pass and result or tostring(result)}),Enum.HttpContentType.ApplicationJson)
   task.wait()
  end
 end)
 lab.Done=true;lab.Ok=ok;lab.Error=not ok and tostring(err)or nil;lab.Phase='Complete'
end)
return 'Detached native verification started; live sources unchanged'
