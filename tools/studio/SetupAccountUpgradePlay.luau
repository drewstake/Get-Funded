-- Temporary Play instrumentation: all storage is in memory, restored before delivery.
local h=game:GetService("HttpService");local prior=h.HttpEnabled;h.HttpEnabled=true
local source=h:GetAsync("http://127.0.0.1:8796/src/server/MarketServer.server.luau");h.HttpEnabled=prior
local prefix=[=[
local function qaClone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=qaClone(x)end return r end
local function qaStore()local s={};function s:UpdateAsync(_,fn)local v=fn(qaClone(self.Value));if v then self.Value=qaClone(v)end;return qaClone(v)end;function s:GetAsync()return qaClone(self.Value)end;return s end
local qaWorldStore,qaLeaderboardStore=qaStore(),qaStore()
]=]
source=source:gsub("World.new%(Config%)","World.new(Config,{Store=qaWorldStore})")
source=source:gsub("Leaderboards.new%({Studio=world.Studio}%)","Leaderboards.new({Studio=world.Studio,Store=qaLeaderboardStore})")
source=source:gsub("diagnostic.OnInvoke=function%(command,a,b%)",[=[diagnostic.OnInvoke=function(command,a,b)
 if command=="QASeed"then
  assert(world:CanRun())
  population.Step=function()end
  for _,id in ipairs(market.AccountOrder)do market:CancelAll(id)end
  local player=Players:GetPlayers()[1];local uid=tostring(player.UserId);local p=funded:Profile(uid);local account=market.Accounts[p.Account]
  p.Tutorial="Done";p.Awards.FirstWin={At=1,Title="Green Spark",Goal=25};p.Awards.Trades5={At=2,Title="Tape Reader",Goal=100};p.RankId="Apprentice";funded:Evaluate(uid,true)
  funded:SetProtectionPreferences(uid,{StopOn=false,TargetOn=false,StopDollars=500,TargetDollars=1500})
  local T=require(script.Parent.TestLiquidity)
  assert(T.Submit(market,account.Id,{Contract="BX",Type="Market",Direction=1,Quantity=5}))
  funded:Depart(uid,os.time()-65)
  local entry=account.Positions.BX.Entry
  T.Offer(market,"BX",-1,1,entry+1);market:AddAccount("qa:print",1e9,1e6,.99,false)
  assert(market:Submit("qa:print",{Contract="BX",Type="Market",Direction=1,Quantity=1}))
  funded:Return(uid);assert(world:Save(false));emit(player,clients[player])
  return {Account=account.Id,Position=account.Positions.BX,View=funded:View(uid),Audit=market:Audit()}
 end
 if command=="QASaveRoundtrip"then
  assert(world:Save(false));local CP=require(script.Parent.WorldCheckpoint)
  local engine=CP.Restore(CP.Decode(qaWorldStore.Value.Checkpoint),Config);local f=Funded.new(engine,Progression,Config)
  local uid=tostring(Players:GetPlayers()[1].UserId)
  return {View=f:View(uid),Stats=f:Stats(uid),Positions=engine.Accounts[f:Owner(uid)].Positions,Audit=engine:Audit(),Mode="In-memory stores"}
 end
]=])
source=prefix..source;assert(loadstring(source));game.ServerScriptService.MarketReign.MarketServer.Source=source
return "In-memory-only Play fixture installed; no real account or storage is accessed."
