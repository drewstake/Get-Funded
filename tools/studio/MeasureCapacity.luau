-- Isolated stress scenario: 32 simulated players with $10B each; never live player accounts.
-- Run in Studio Edit after installing source changes. Fresh modules avoid require caching.
local suffix=game:GetService("HttpService"):GenerateGUID(false):gsub("-","")
local shared=game.ReplicatedStorage.MarketReign:Clone();shared.Name="CapacityMeasureShared"..suffix
local server=game.ServerScriptService.MarketReign:Clone();server.Name="CapacityMeasureServer"..suffix
for _,m in ipairs(server:GetDescendants())do if m:IsA("BaseScript")then m.Enabled=false end end
shared.Parent=game.ReplicatedStorage;server.Parent=game.ServerScriptService
for _,folder in ipairs({shared,server})do for _,m in ipairs(folder:GetDescendants())do
 if m:IsA("LuaSourceContainer")then
  m.Source=m.Source:gsub("game%.ReplicatedStorage%.MarketReign","game.ReplicatedStorage."..shared.Name)
   :gsub("game%.ServerScriptService%.MarketReign","game.ServerScriptService."..server.Name)
 end
end end
local ok,result=pcall(function()
local C=require(shared.MarketConfig)
local E=require(server.MarketEngine);local P=require(server.Participants);local F=require(server.FundedAccounts)
local Policy=require(server.PlayerExecution)
local e=E.new(C,90871);local p=P.new(e)
local accounts={};local budgets={};local trades=0;local guardChecks=0
local trade=e._trade
function e:_trade(b,incoming,resting,quantity)
 local a=self.Accounts[incoming.Owner]
 if a.Player then
  local epoch=math.floor(self.Time/C.PlayerExecution.WindowSeconds)
  local key=epoch..":"..Policy.Owner(a)..":"..incoming.Direction
  local market=epoch..":"..b.Key..":"..incoming.Direction
  budgets[key]=(budgets[key]or 0)+quantity;budgets[market]=(budgets[market]or 0)+quantity
  assert(budgets[key]<=C.PlayerExecution.OwnerContracts,"Spam exceeded player execution budget")
  assert(budgets[market]<=C.PlayerExecution.MarketContracts,"Aggregate execution budget exceeded")
  assert(Policy.Allows(self,b,resting.Price,incoming.Direction),"Player traded outside fair-value guard")
  trades+=1;guardChecks+=1
 end
 return trade(self,b,incoming,resting,quantity)
end
for i=1,32 do
 local id="stress-"..i;local a=e:AddAccount(id,10000000000,10000000,.8,true);a.ProfileId=id
 table.insert(accounts,a)
 local ok,r=e:Submit(id,{Contract="BX",Direction=1,Quantity=1000000,Type="Market"})
 assert(ok and r.Queued)
end
local cpu,maxStep,emptySamples,samples=0,0,0,0
for step=1,1200 do
 local start=os.clock();p:Step();local duration=os.clock()-start;cpu+=duration;maxStep=math.max(maxStep,duration)
 if step%20==0 then
  samples+=1;if #e.Books.BX.Bids==0 or #e.Books.BX.Asks==0 then emptySamples+=1 end
 end
 if step==600 then
  for _,a in ipairs(accounts)do assert(a.Positions.BX,"Player starved before close phase");assert(F.Perform(e,a.Id,{Action="Close",Contract="BX"}))end
 end
 if step%200==0 then e:Audit();task.wait()end
end
local closed,remaining=0,0
for _,a in ipairs(accounts)do
 if not a.Positions.BX then closed+=1 else remaining+=a.Positions.BX.Quantity end
end
return {Players=32,BalanceEach=10000000000,RequestedContractsEach=1000000,PlayerFills=trades,GuardChecks=guardChecks,
 ClosedPlayers=closed,RemainingContracts=remaining,EmptyQuoteSamples=emptySamples,QuoteSamples=samples,
 MeanStepMs=cpu/1200*1000,MaxStepMs=maxStep*1000,Audit=e:Audit()}
end)
shared:Destroy();server:Destroy()
if not ok then error(result)end
return result
