-- Temporary isolated Play setup. Restore MarketServer from src after stopping Play.
local H=game:GetService("HttpService")
local server=game.ServerScriptService.MarketReign
local source=H:GetAsync("http://127.0.0.1:8777/src/server/MarketServer.server.luau"):gsub("\r","")
local prefix=[=[
local function qaClone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=qaClone(x)end return r end
local function qaStore()
 local s={}
 function s:UpdateAsync(_,fn)local value=fn(qaClone(self.Value));if value then self.Value=qaClone(value)end return qaClone(value)end
 function s:GetAsync()return qaClone(self.Value)end
 return s
end
local qaWorldStore,qaLeaderboardStore=qaStore(),qaStore()
local qaNotices={}local qaTriggered={}
]=]
source=source:gsub("World.new%(Config%)","World.new(Config,{Store=qaWorldStore})")
source=source:gsub("Leaderboards.new%({Studio=world.Studio}%)","Leaderboards.new({Studio=world.Studio,Store=qaLeaderboardStore})")
source=source:gsub('Notify=function%(player,message%)','Notify=function(player,message)table.insert(qaNotices,{UserId=player.UserId,Message=message});')
source=source:gsub('resetCommand.Triggered:Connect%(function%(source,text%)','resetCommand.Triggered:Connect(function(source,text)table.insert(qaTriggered,{UserId=source.UserId,Text=text});')
source=source:gsub('diagnostic.OnInvoke=function%(command,a,b%)',[=[diagnostic.OnInvoke=function(command,a,b)
 if command=="QAStatus"then return {Notices=qaNotices,Triggered=qaTriggered,Sequence=qaWorldStore.Value and qaWorldStore.Value.SaveSequence,Mode=world.Mode,Ready=world:CanRun(),Projection=world.DurableProjection,Busy=world.Busy}end
 if command=="QASeed"then
  assert(world:CanRun())
  funded:Join("1");funded:Join("2")
  local profile=funded:Profile("1");profile.PlayerName="Roblox";profile.DisplayName="Roblox"
  local other=funded:Profile("2");other.PlayerName="OtherFixture";other.DisplayName="OtherFixture"
  local account=market.Accounts[profile.Account]
  assert(market:Submit(account.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  assert(market:Submit(account.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
  funded:SetProtectionPreferences("1",{StopOn=true,TargetOn=true,StopDollars=75,TargetDollars=150})
  assert(world:Save(false));leaderboard:Queue(world.DurableProjection);leaderboard.NextWrite=0;leaderboard:Flush()
  return {Target=profile,Other=other,Stats=funded:Stats("1")}
 end
 if command=="QADirect"then ownerCommand:Handle(Players:GetPlayers()[1],a);return qaNotices end
]=])
source=prefix..source
assert(loadstring(source))
game:GetService("ScriptEditorService"):UpdateSourceAsync(server.MarketServer,function()return source end)
return "In-memory stores and temporary QA instrumentation installed; no real DataStore access."
