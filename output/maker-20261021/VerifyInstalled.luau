local H=game:GetService('HttpService')
local root=game.ServerScriptService.MarketReign
local function norm(s)return s:gsub('\r','')end
local unchanged={'MarketEngine','BotMomentum','BotWhale','BotParticipation','BotExitRetry','ProtectiveOrders','PlayerExecution'}
for _,name in ipairs(unchanged)do assert(norm(root[name].Source)==norm(H:GetAsync('http://127.0.0.1:8819/original/server/'..name..'.luau')),'Safeguard source changed: '..name)end
local names={'BotMaker','BotMakerTests','Participants','WorldCheckpoint','MarketConfig','BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotRefreshTests','BotWhaleTests','MakerLiquidityTests'}
for _,name in ipairs(names)do local module=name=='MarketConfig'and game.ReplicatedStorage.MarketReign.MarketConfig or root[name];assert(norm(module.Source)==norm(H:GetAsync('http://127.0.0.1:8819/candidate/'..name..'.luau')),'Source differs: '..name)end
H:PostAsync('http://127.0.0.1:8819/source-verification.json',H:JSONEncode({CandidateFiles=#names,UnchangedCoreFiles=unchanged,Passed=true}),Enum.HttpContentType.ApplicationJson)
return 'All 11 candidate sources match; 7 core strategy/safeguard sources unchanged'
