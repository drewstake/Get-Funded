-- Isolated UI review: cloned modules, an in-memory exchange, no profile stores or live orders.
local shared=game.ReplicatedStorage.MarketReign:Clone()
local old=game.ReplicatedStorage:FindFirstChild("CopyReviewShared");if old then old:Destroy()end
local oldServer=game.ServerScriptService:FindFirstChild("CopyReviewServer");if oldServer then oldServer:Destroy()end
shared.Name="CopyReviewShared";shared.Parent=game.ReplicatedStorage
local server=game.ServerScriptService.MarketReign:Clone()
server.Name="CopyReviewServer";server.MarketServer.Enabled=false;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do
 if m:IsA("BaseScript")then m.Enabled=false end
 if m:IsA("LuaSourceContainer")then
  m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage.CopyReviewShared")
   :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService.CopyReviewServer")
 end
end end
-- The hook exists only in this disposable clone; production Preview behavior stays unchanged.
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub('if RunService:IsStudio%(%)and not options.Preview then','if RunService:IsStudio() then')
shared.TerminalUI.Source=shared.TerminalUI.Source:gsub('if not s.Coach or options.Preview then return end','if not s.Coach then return end')
local Config=require(shared.MarketConfig)
local engine=require(server.MarketEngine).new(Config,73521)
local population=require(server.Participants).new(engine)
for _=1,math.floor(Config.WarmupSeconds/Config.StepSeconds)do population:Step()end
local funded=require(server.FundedAccounts).new(engine,require(shared.ProgressionConfig),Config)
funded:Start("copy-review");funded:Flag("copy-review","TutorialDone")
local snapshot=engine:Snapshot(funded:Owner("copy-review"),"BX","1m",true)
snapshot.CandlesBySeries={}
for _,key in ipairs(Config.ContractOrder)do for _,tf in ipairs(Config.Timeframes)do
 snapshot.CandlesBySeries[key..":"..tf[1]]=engine:Snapshot(funded:Owner("copy-review"),key,tf[1],true).Candles
end end
local data=Instance.new("StringValue");data.Name="Fixture";data.Value=game.HttpService:JSONEncode({Snapshot=snapshot,Portfolio=funded:View("copy-review"),Stats=funded:Stats("copy-review")});data.Parent=shared
local ctl=require(shared.TerminalUI).Mount(game.StarterGui.MarketReign,{Preview=true,PreviewData=snapshot,PortfolioData=funded:View("copy-review")})
return {Ready=true,Viewport=tostring(workspace.CurrentCamera.ViewportSize),StorageAccessed=false}
