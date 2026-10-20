local Instance=require("@lune/roblox").Instance
local env=require("../environment")
local game,Enum,task=env.game,env.Enum,env.task
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local root=ReplicatedStorage:WaitForChild("MarketReign")
local Config=require("./MarketConfig")
local Progression=require("./ProgressionConfig")
local World=require("./WorldService")
local Funded=require("./FundedAccounts")
local Leaderboards=require("./LeaderboardService")
local Ranking=require("./LeaderboardRanking")
local ReplyBuffer=require("./ReplyBuffer")
local WorldSettings=require("./WorldConfig")
local SimulationScheduler=require("./SimulationScheduler")
local RequestJournal=require("./RequestJournal")
local RequestQueue=require("./RequestQueue")
local OwnerResetCommand=require("./OwnerResetCommand")
local OwnerGiveCommand=require("./OwnerGiveCommand")
local OwnerBotsCommand=require("./OwnerBotsCommand")
local BotStats=require("./BotStats")
local DepthAccess=require("./MarketDepthAccess")
local depthAccess=DepthAccess.new()
Funded.Validate(Progression) -- Fail closed on invalid progression configuration.
local function remote(name)
 local old=root:FindFirstChild(name) if old then old:Destroy() end
 local r=Instance.new("RemoteEvent") r.Name=name r.Parent=root return r
end
local requestRemote=remote("OrderRequest") local updateRemote=remote("MarketUpdate")
local ownerNotice=remote("OwnerNotice")
local ownerBotStats=remote("OwnerBotStats") -- Server-to-owner only; no OnServerEvent handler.
local world=World.new(Config)
local leaderboard=Leaderboards.new({Studio=world.Studio})
world.CaptureProjection=function(engine)return Ranking.Capture(Funded.new(engine,Progression,Config))end
local oldLeaderboard=root:FindFirstChild("LeaderboardRequest") if oldLeaderboard then oldLeaderboard:Destroy() end
local leaderboardRemote=Instance.new("RemoteFunction") leaderboardRemote.Name="LeaderboardRequest" leaderboardRemote.Parent=root
local market,population,funded local epoch=-1
root:SetAttribute("SessionSeed",nil) root:SetAttribute("Ready",false)
local clients={} local queue={} local sequence=0 local actionLog={}
local resettingUid
-- Acknowledgements are bounded per connection by count and age (see ReplyBuffer).
local replies=ReplyBuffer.new(WorldSettings.MaxQueuedReplies,WorldSettings.ReplyMaxAgeSeconds)
-- Joining idempotently creates one $10,000 account for a new player.
local function resolve(player,state)
 if not funded or not world:CanRun() or state.ResetPending then return end
 funded:Join(state.Uid) funded:Return(state.Uid) funded:Evaluate(state.Uid)
 local p=funded:Profile(state.Uid)
 if p then
  p.PlayerName=player.Name;p.DisplayName=player.DisplayName
  -- A join restores history without replaying sounds for old/offline executions.
  local events={};for _,event in ipairs(p.Events or {})do if event.Kind~="TradeClosed"then table.insert(events,event)end end;p.Events=events
 end
 state.Owner=funded:Owner(state.Uid) state.Full=true state.PortfolioRevision=nil
 if state.RequestEngine~=market then
  state.RequestEngine=market;state.RequestSession=RequestJournal.Open(market,state.Uid)
 end
 if state.Owner then market:SetConnected(state.Owner,true)end
end
local function add(player)
 if clients[player] then return end
 clients[player]={Uid=Funded.Key(player.UserId),Contract=Config.ContractOrder[1],Timeframe="1m",Full=true,Tokens=20,TokenTime=os.clock(),
  Seen={},SeenOrder={},Replies={},ReplyTimes={},Subscribed=false,PortfolioAt=0,ResetPending=tostring(player.UserId)==resettingUid}
 depthAccess:Refresh(player)
 resolve(player,clients[player])
end
Players.PlayerAdded:Connect(add) for _,p in ipairs(Players:GetPlayers()) do add(p) end
-- The purchase event only triggers a fresh ownership query. Its boolean never grants access.
game:GetService("MarketplaceService").PromptGamePassPurchaseFinished:Connect(function(player,passId)
 if clients[player]and passId==depthAccess.PassId then depthAccess:Refresh(player,true)end
end)
leaderboardRemote.OnServerInvoke=function(player,tab)
 local state=clients[player]
 if not state or (tab~="Global" and tab~="Server") then return nil end
 -- Read-only endpoint; rate limits are independent of order traffic. No scores/ids accepted.
 local now=os.clock()
 if now<(state.LeaderboardAt or 0) then return {Tab=tab,State="Throttled"} end
 state.LeaderboardAt=now+2
 if not funded or not world:CanRun() then return {Tab=tab,State="Loading",Rows={},Studio=world.Studio} end
 if tab=="Server" then return leaderboard:Server(funded,Players:GetPlayers(),player) end
 local own=Ranking.Row(funded,state.Uid,player)
 return leaderboard:Global(own)
end
-- Portfolio + projection accompany each price batch. Closed and open amounts are one snapshot.
local function attachPortfolio(state,packet)
 if not funded then return end
 packet.Events=funded:TakeEvents(state.Uid)
 local profile=funded:Profile(state.Uid)
 local revision=profile and profile.Revision or 0 local now=os.clock()
 packet.Portfolio=funded:View(state.Uid) state.PortfolioRevision=revision state.PortfolioAt=now
 -- Lifetime stats: sent on join/refresh and whenever a counted value changes (a close, a depletion,
 -- a restart). A failure here is isolated from trading and reported to the Stats page.
 local key=funded:StatsKey(state.Uid)
 if state.Full or key~=state.StatsKey then
  local ok,stats=pcall(funded.Stats,funded,state.Uid)
  if not ok then warn("[Get Funded!] Stats unavailable: "..tostring(stats)) end
  packet.Stats=ok and stats or {Error="Stats are temporarily unavailable. Your trades and saved results are not affected."}
  state.StatsKey=key
 end
end
local function emit(player,state)
 depthAccess:Refresh(player)
 if funded and world:CanRun() and not funded:Owner(state.Uid) and os.clock()>=(state.JoinRetryAt or 0) then
  state.JoinRetryAt=os.clock()+5;resolve(player,state)
 end
 if funded then
  local owner=funded:Owner(state.Uid)
  if state.Owner~=owner then state.Owner=owner;state.Full=true;if owner then market:SetConnected(owner,true)end end
 end
 local unavailable=not market or world.Transaction or state.ResetPending or world.Mode=="Unavailable" or world.Mode=="Following" or world.Mode=="Loading"
 if unavailable or not state.Owner or not market.Accounts[state.Owner] then
  -- No trading account yet (first join) or the exchange is not ready: send status and portfolio only.
  local queued,dropped=replies:Take(state)
  local packet={StatusOnly=true,CanTrade=not unavailable and world:CanRun(),ConnectionStatus=world:Label(),Replies=queued,RepliesDropped=dropped,NoAccount=not unavailable or nil,RequestSession=state.RequestSession,RequestHigh=state.LastRequestId}
  if not unavailable then attachPortfolio(state,packet) state.Full=false end
  depthAccess:Apply(packet,player,state.Contract)
  updateRemote:FireClient(player,packet)
  return
 end
 local packet=market:Snapshot(state.Owner,state.Contract,state.Timeframe,state.Full)
 packet.Seed=nil -- The server's future random stream is private.
 packet.CanTrade=world:CanRun() packet.ConnectionStatus=world:Label() packet.PersistenceMode=world.Mode
 if market.Accounts[state.Owner].Resetting then
  packet.CanTrade=false;packet.ConnectionStatus="Resetting account · liquidating positions…"
 end
 -- Quotes/candles/P&L are frequent; unchanged order and trade histories are not resent.
 local orderParts={}
 for _,order in ipairs(packet.Orders)do
  table.insert(orderParts,table.concat({order.Id,order.Contract,order.Protection or "",order.Quantity,order.Price or "Market",order.Status},":"))
 end
 local orderSignature=table.concat(orderParts,"|")
 if not state.Full and state.SentRevision==packet.Revision and state.SentOwner==state.Owner then
  packet.History=nil packet.Fills=nil
 end
 -- OCO/trigger status can change before a closing execution changes the account revision.
 if not state.Full and state.SentOwner==state.Owner and state.SentOrders==orderSignature then
  packet.Orders=nil
 end
 depthAccess:Apply(packet,player,state.Contract)
 state.SentRevision=packet.Revision state.SentOwner=state.Owner state.SentOrders=orderSignature
 packet.Regime=population.Regime.Name packet.News=market.Time<population.NewsUntil and population.News or nil
 packet.Speed=Config.SimulationSpeed packet.Replies,packet.RepliesDropped=replies:Take(state)
 packet.AccountKey=(funded:Profile(state.Uid) or {}).Active
 packet.AccountToken=state.Owner -- identifies the exact attempt; checked, never used to choose an owner
 packet.RequestSession=state.RequestSession
 packet.RequestHigh=state.LastRequestId
 attachPortfolio(state,packet)
 updateRemote:FireClient(player,packet) state.Full=false
end
-- A packet failure for one connection must not stop every other player's feed.
local function safeEmit(player,state)
 local ok,err=pcall(emit,player,state)
 if not ok then
  state.Full=true
  local now=os.clock()
  if now>=(state.EmitWarningAt or 0)then
   state.EmitWarningAt=now+5;warn("[Get Funded!] Market update failed; retrying: "..tostring(err))
  end
 end
end
local function reply(state,id,ok,message,result,extra)
 local r={RequestId=id,Ok=ok,Message=message,Result=result}
 for k,v in pairs(extra or {})do r[k]=v end
 local active=state.ActiveJournal
 if active and active.Id==id then RequestJournal.Finish(market,state.Uid,active.Session,id,r)end
 replies:Push(state,r,os.clock())
end
local allowed={Place=true,Cancel=true,Close=true,Subscribe=true,AmendProtection=true,AmendOrder=true,
 Start=true,Restart=true,ResetAccount=true,AcknowledgeAway=true,Flag=true,Stats=true,ProtectionPreferences=true}
local fields={"RequestSession","ExpectedAccount","Contract","Timeframe","Direction","Quantity","Type","Price","StopTicks","TargetTicks","StopDollars","TargetDollars","ExpectedQuantity","OrderId","Protection","ExpectedPrice",
 "Stage","StopOn","TargetOn","Create","SummaryId","Execution"}
requestRemote.OnServerEvent:Connect(function(player,request)
 local state=clients[player]
 if not state or state.ResetPending or type(request)~="table" then return end
 local now=os.clock()
 -- Subscription recovery has its own allowance, so order spam cannot starve the feed.
 if request.Action=="Subscribe"or request.Action=="Stats"then
  state.ReadTokens=math.min(4,(state.ReadTokens or 4)+(now-(state.ReadTokenTime or now))*2);state.ReadTokenTime=now
  if state.ReadTokens<1 then return end;state.ReadTokens-=1
 else
  state.Tokens=math.min(20,state.Tokens+(now-state.TokenTime)*6);state.TokenTime=now
  if state.Tokens<1 then return end;state.Tokens-=1
 end
 if type(request.Id)~="number" or request.Id%1~=0 or request.Id<1 or request.Id>1e9 then return end
 if state.Seen[request.Id]then
  local cached=RequestJournal.Cached(market,state.Uid,request.RequestSession,request.Id)
  if cached then replies:Push(state,cached,now)else state.Full=true end
  return
 end
 if not allowed[request.Action] then return end
 -- Whitelist scalar inputs. ExpectedAccount detects a stale view; it never selects an owner.
 -- Execution prices, timestamps and account ownership remain server-owned.
 local clean={Id=request.Id,Action=request.Action}
 for _,field in ipairs(fields) do
  local value=request[field]
  if value~=nil then
   if field=="StopOn"or field=="TargetOn"or field=="Create"then
    if type(value)~="boolean"then return end
   elseif type(value)~="number" and type(value)~="string" then return end
   if type(value)=="number" and (value~=value or math.abs(value)>1e9) then return end
   if type(value)=="string" and #value>(field=="Followers" and 512 or field=="ExpectedAccount" and 64 or 32) then return end
   clean[field]=value
  end
 end
 if #queue>=RequestQueue.Capacity then reply(state,clean.Id,false,"Exchange busy. Please retry.") return end
 state.Seen[clean.Id]=true table.insert(state.SeenOrder,clean.Id)
 state.LastRequestId=math.max(state.LastRequestId or 0,clean.Id)
 if #state.SeenOrder>256 then state.Seen[table.remove(state.SeenOrder,1)]=nil end
 -- Read-only: resend the authoritative Stats packet with the next update (Stats page Retry).
 if clean.Action=="Stats"then state.StatsKey=nil return end
 if clean.Action=="Subscribe"then
  local valid=false for _,tf in ipairs(Config.Timeframes)do if tf[1]==clean.Timeframe then valid=true break end end
  if Config.Contracts[clean.Contract]and valid then
   state.Contract=clean.Contract state.Timeframe=clean.Timeframe state.Full=true state.Subscribed=true
   -- Coalesce rapid subscription changes into the next scheduled market packet.
  end
  return
 end
 if not world:CanRun()then reply(state,clean.Id,false,world:Label())return end
 sequence+=1 table.insert(queue,{Player=player,Request=clean,Sequence=sequence,Epoch=epoch,Owner=state.Owner})
end)
local function processCore(item)
 local state=clients[item.Player] if not state or state.ResetPending then return end
 if not world:CanRun() then reply(state,item.Request.Id,false,world:Label(),nil,{Kind=item.Request.Action}) return end
 if item.Epoch~=epoch then reply(state,item.Request.Id,false,"Exchange reconnected. Please submit your order again.")return end
 local req=item.Request local uid=state.Uid
 funded:Evaluate(uid)
 local owner=funded:Owner(uid)
 if state.Owner~=owner then
  state.Owner=owner;state.Full=true
  if owner then market:SetConnected(owner,true)end
  if req.Action=="Place" or req.Action=="Close" or req.Action=="Cancel" or req.Action=="AmendOrder" or req.Action=="AmendProtection" then
   reply(state,req.Id,false,"Your account has restarted. Check the current account and try again.") return
  end
 end
 -- Account lifecycle. Each is idempotent and validated against the saved profile.
 if req.Action=="Start" then
  local ok,message,created=funded:Start(uid)
  local profile=funded:Profile(uid);if profile then profile.PlayerName=item.Player.Name;profile.DisplayName=item.Player.DisplayName end
  state.Owner=funded:Owner(uid) state.Full=true;if state.Owner then market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Start",Created=created}) return
 elseif req.Action=="Restart" then
  local ok,message=funded:Restart(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid) state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="Restart",Tier=req.Tier}) return
 elseif req.Action=="ResetAccount"then
  local ok,message=funded:ResetAccount(uid,req.ExpectedAccount)
  if ok then state.Owner=funded:Owner(uid);state.Full=true;market:SetConnected(state.Owner,true)end
  reply(state,req.Id,ok,message,nil,{Kind="ResetAccount"});return
 elseif req.Action=="AcknowledgeAway"then
  local ok,message=funded:AcknowledgeAway(uid,req.SummaryId)
  reply(state,req.Id,ok,message,nil,{Kind="AcknowledgeAway"});return
 elseif req.Action=="Flag" then
  local ok,message=funded:Flag(uid,req.Stage)
  reply(state,req.Id,ok,message,nil,{Kind="Flag",Stage=req.Stage}) return
 elseif req.Action=="ProtectionPreferences"then
  local ok,message=funded:SetProtectionPreferences(uid,req)
  reply(state,req.Id,ok,message,nil,{Kind="ProtectionPreferences"}) return
 end
 -- Trading owner and current run token are resolved only on the server.
 local owner=state.Owner
 if item.Owner~=owner or req.ExpectedAccount~=owner then reply(state,req.Id,false,"Your account has changed. Check it and try again.") return end
 if not owner or not market.Accounts[owner] then reply(state,req.Id,false,"Your trading account is loading.") return end
 local ok,result=Funded.Perform(market,owner,req)
 market:ProcessStops()
 funded:Evaluate(uid)
 local message=type(result)=="table" and Funded.Describe(result) or result or "Request rejected."
 reply(state,req.Id,ok,message,type(result)=="table" and result or nil,{Kind=req.Action})
end
local function process(item)
 local state=clients[item.Player];if not state or state.ResetPending then return end
 local req=item.Request
 if not market then reply(state,req.Id,false,"Exchange is not ready.");return end
 local accepted,cached,message=RequestJournal.Begin(market,state.Uid,req.RequestSession,req.Id)
 if not accepted then
  if cached then replies:Push(state,cached,os.clock())else reply(state,req.Id,false,message)end
  state.Full=true;return
 end
 state.ActiveJournal={Id=req.Id,Session=req.RequestSession}
 market.RequestContext={Sequence=item.Sequence,Id=req.Id,Step=market.Step}
 local ok,err=pcall(processCore,item)
 market.RequestContext=nil
 if not ok then
  reply(state,req.Id,false,"Request interrupted. Check the account snapshot before placing another order.")
  state.Full=true;warn("[Get Funded!] Request processing failed: "..tostring(err))
 end
 state.ActiveJournal=nil
end
Players.PlayerRemoving:Connect(function(player)
 depthAccess:Forget(player)
 -- Leaving cancels working orders. Positions and their protective triggers remain on the exchange.
 local departing=clients[player]
 if market and departing and departing.Owner then funded:Depart(departing.Uid);market:SetConnected(departing.Owner,false)end
 -- Accept already-received preference edits even if the player leaves before the next market step.
 local remaining={}
 for _,item in ipairs(queue)do
  if item.Player==player and item.Request.Action=="ProtectionPreferences"then process(item)
  elseif item.Player==player and market and departing then
   local req=item.Request
   if RequestJournal.Begin(market,departing.Uid,req.RequestSession,req.Id)then
    RequestJournal.Finish(market,departing.Uid,req.RequestSession,req.Id,{RequestId=req.Id,Ok=false,Message="Disconnected before execution; request cancelled."})
   end
  elseif item.Player~=player then table.insert(remaining,item)end
 end
 queue=remaining;clients[player]=nil
end)
local routing={}
TeleportService.TeleportInitFailed:Connect(function(player)
 routing[player]=nil
 local state=clients[player]if state then state.NextRoute=os.clock()+10 end
end)
local function route(player,state)
 local owner=world.Owner
 if world.Studio or routing[player]or os.clock()<(state.NextRoute or 0)or not owner or
  owner.LeaseUntil<=os.time()or owner.JobId==""or owner.JobId==game.JobId then return end
 routing[player]=true state.NextRoute=os.clock()+15
 task.spawn(function()
  local ok,err=pcall(function()
   local options=Instance.new("TeleportOptions")options.ServerInstanceId=owner.JobId
   TeleportService:TeleportAsync(owner.PlaceId,{player},options)
  end)
  if not ok then routing[player]=nil warn("[Get Funded!] Exchange transfer will retry: "..tostring(err))end
 end)
end
Players.PlayerRemoving:Connect(function(player)routing[player]=nil end)
-- TextChatCommand intercepts the command; authorization and username resolution stay on the server.
-- The owner wipe remains separate from the player reset, which preserves lifetime progress.
local ownerCommand=OwnerResetCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared" and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=function(name)
  for _,player in ipairs(Players:GetPlayers())do
   if player.Name:lower()==name:lower()then return player.UserId,player.Name end
  end
  local uid=Players:GetUserIdFromNameAsync(name)
  return uid,Players:GetNameFromUserIdAsync(uid)
 end,
 Reset=function(userId,name)
  local uid=Funded.Key(userId)
  if not world.Engine or not world.Engine.Profiles[uid]then return false,"@"..name.." has no saved data to reset."end
  resettingUid=uid
  for _,state in pairs(clients)do if state.Uid==uid then state.ResetPending=true end end
  local ok=world:TransformSaved(function(engine)
   return Funded.new(engine,Progression,Config):ResetPlayer(uid)
  end)
  if not ok then
   resettingUid=nil
   for player,state in pairs(clients)do if state.Uid==uid then
    if not world.Engine then
     player:Kick("The exchange is checking saved data after an owner reset. Please rejoin shortly.")
    else state.ResetPending=nil;state.Full=true end
   end end
   return false,"Reset was not confirmed. Wait for the saved exchange to recover, then check @"..name.." before retrying."
  end
  -- Clear delayed actions and diagnostic copies belonging to the wiped profile.
  for i=#queue,1,-1 do if queue[i].Player.UserId==userId then table.remove(queue,i)end end
  for i=#actionLog,1,-1 do if actionLog[i].Player==userId then table.remove(actionLog,i)end end
  leaderboard:UseDurableProjection(world.DurableProjection)
  root:SetAttribute("LeaderboardRevision",(root:GetAttribute("LeaderboardRevision")or 0)+1)
  task.spawn(function()leaderboard.NextWrite=0;leaderboard:Flush()end)
  return true,"Reset saved for @"..name..". All trading history, ranks, titles and settings cleared. New $10,000 account ready."
 end,
 AfterReset=function(userId)
  -- Rejoining discards local drafts, tutorial state, preference retries and old request tokens.
  for _,player in ipairs(Players:GetPlayers())do
   if player.UserId==userId then player:Kick("The owner reset your Get Funded! data, including ranks, titles and trading history. Rejoin to start with $10,000 in-game money.")end
  end
  resettingUid=nil
 end,
})
local chat=game:GetService("TextChatService")
local oldCommand=chat:FindFirstChild("OwnerResetCommand");if oldCommand then oldCommand:Destroy()end
local resetCommand=Instance.new("TextChatCommand")
resetCommand.Name="OwnerResetCommand";resetCommand.PrimaryAlias="/reset";resetCommand.AutocompleteVisible=false
resetCommand.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then ownerCommand:Handle(player,text)end
end)
resetCommand.Parent=chat
local giveCommand=OwnerGiveCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=function(id)return game:GetService("GroupService"):GetGroupInfoAsync(id)end,
 Ready=function()return world.Mode=="Shared"and not world.Busy and world:CanRun()end,
 Notify=function(player,message)if player.Parent==Players then ownerNotice:FireClient(player,message)end end,
 Resolve=ownerCommand.Options.Resolve,
 Give=function(userId,name,amount,actor)
  local uid=Funded.Key(userId);local receipt=game:GetService("HttpService"):GenerateGUID(false)
  local ok,balance=world:TransformSaved(function(engine)
   local accounts=Funded.new(engine,Progression,Config,{Capacity=function(kind)return world:HasCapacity(kind)end})
   local result=accounts:GrantMoney(uid,amount,actor,receipt)
   local profile=accounts:Profile(uid);profile.PlayerName=name
   return result
  end)
  if not ok then
   if world:CanRun()then return false,"Grant not applied: "..tostring(balance)end
   return false,"Grant could not be confirmed. Wait for the saved exchange to recover and check @"..name.."'s balance before retrying."
  end
  local function money(n)return "$"..string.format("%.0f",n):reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")end
  return true,"Saved: gave "..money(amount).." to @"..name..". Balance: "..money(balance).."."
 end,
})
local oldGive=chat:FindFirstChild("OwnerGiveCommand");if oldGive then oldGive:Destroy()end
local giveChat=Instance.new("TextChatCommand");giveChat.Name="OwnerGiveCommand";giveChat.PrimaryAlias="/give";giveChat.AutocompleteVisible=false
giveChat.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then giveCommand:Handle(player,text)end
end)
giveChat.Parent=chat
local botsCommand=OwnerBotsCommand.new({
 CreatorType=game.CreatorType,CreatorId=game.CreatorId,
 GroupLookup=ownerCommand.Options.GroupLookup,
 Ready=function()return world.Mode=="Shared"and not world.Busy and world:CanRun()end,
 NextSequence=function()local r=world.Population.BotRefreshReceipt;return (r and r.Sequence or 0)+1 end,
 Notify=ownerCommand.Options.Notify,
 Refresh=function(sequence,actor)return world:RefreshBots(sequence,actor)end,
 StatsReady=function()return not world.Busy and world:CanRun()and world.Population~=nil end,
 Stats=function(player)
  -- Non-yielding inspection produces one coherent snapshot without saving or stepping.
  local report=BotStats.Text(world.Engine,world.Population)
  if player.Parent==Players then ownerBotStats:FireClient(player,report)end
 end,
})
local oldBots=chat:FindFirstChild("OwnerBotsCommand");if oldBots then oldBots:Destroy()end
local botsChat=Instance.new("TextChatCommand");botsChat.Name="OwnerBotsCommand";botsChat.PrimaryAlias="/bots";botsChat.AutocompleteVisible=false
botsChat.Triggered:Connect(function(source,text)
 local player=source and Players:GetPlayerByUserId(source.UserId)
 if player then botsCommand:Handle(player,text)end
end)
botsChat.Parent=chat
task.spawn(function()world:Open()end)
game:BindToClose(function()
 if funded then for _,state in pairs(clients)do funded:Depart(state.Uid)end end
 world:Close()
 leaderboard:Queue(world.DurableProjection)
 -- Exchange durability comes first. A missed publish is rebuilt from its save on the next owner.
 leaderboard.NextWrite=0;leaderboard:Flush()
end)
task.spawn(function()
 while not world.Closing do
  task.wait(5)
  leaderboard:Queue(world.DurableProjection)
  leaderboard:Flush()
 end
end)
local elapsed,broadcast,maintenance=0,0,0
local performance={Frames=0,Steps=0,TotalMs=0,MaxMs=0,Backlog=0,BudgetHits=0}
RunService.Heartbeat:Connect(function(dt)
 local started=os.clock()
 debug.profilebegin("FundedMarketHeartbeat")
 if epoch~=world.Epoch then
  epoch=world.Epoch market=world.Engine population=world.Population elapsed=0
  funded=market and Funded.new(market,Progression,Config,{Capacity=function(kind) return world:HasCapacity(kind) end}) or nil
  if market and funded then
   local connected={}
   for _,state in pairs(clients)do local owner=funded:Owner(state.Uid);if owner then connected[owner]=true end end
   market:SetConnectedOwners(connected)
  end
  for player,state in pairs(clients)do state.Owner=nil resolve(player,state) end
 end
 local active=world:CanRun()
 root:SetAttribute("Ready",active)root:SetAttribute("PersistenceStatus",world:Label())
 if active then elapsed+=dt*Config.SimulationSpeed else elapsed=0 end
 broadcast+=dt maintenance+=dt local steps=0
 if active then
  local limited
  elapsed,steps,limited=SimulationScheduler.Advance(elapsed,Config,function()
   -- Owner maintenance precedes the next request batch/step, never interleaves with a fill.
   if botsCommand:AtBoundary()then return false end
   -- Bound request work, with a fixed FIFO batch for deterministic replay. Every
   -- accepted tail stays queued; the simulation still completes each atomic step.
   local pending;pending,queue=RequestQueue.Take(queue)
   for _,item in ipairs(pending) do
    table.insert(actionLog,{Step=market.Step,Sequence=item.Sequence,Player=item.Player.UserId,Request=item.Request})
    if #actionLog>5000 then table.remove(actionLog,1) end
    process(item)
   end
   if not world:CanRun()then return false end
   population:Step();funded:ProcessResets()
  end,os.clock,started)
  if limited then performance.BudgetHits+=1 end
 end
 -- Already accepted requests keep their FIFO place through bot maintenance.
 if not active and #queue>0 and not world.BotRefreshSaving then
  for _,item in ipairs(queue)do local state=clients[item.Player]if state then reply(state,item.Request.Id,false,world:Label())end end
  queue={}
 end
 if maintenance>=1 then
  maintenance=0 task.spawn(function()world:Maintain()end)
  -- SL/TP can execute while a player is away; unlocks are still earned once.
  if active and funded then
   -- Progress from offline protective fills is evaluated on the same saved profile.
   
   for uid in pairs(market.Profiles)do funded:Evaluate(uid) end
  end
  -- Idle connections release expired acknowledgements even if they never send or subscribe again.
  local clock=os.clock() for _,state in pairs(clients)do replies:Prune(state,clock) end
  if world.Mode=="Following"then for player,state in pairs(clients)do route(player,state)end end
 end
 -- Do not skip simulation steps under load; catch up over subsequent frames.
 if broadcast>=Config.BroadcastSeconds then
  broadcast=broadcast%Config.BroadcastSeconds
  for player,state in pairs(clients) do if state.Subscribed then safeEmit(player,state) end end
 end
 local ms=(os.clock()-started)*1000
 performance.Frames+=1 performance.Steps+=steps performance.TotalMs+=ms
 performance.MaxMs=math.max(performance.MaxMs,ms) performance.Backlog=elapsed
 performance.LastMs=ms;performance.LastSteps=steps
 debug.profileend()
end)
-- Read-only diagnostic access in Studio; never replicated to game clients.
if RunService:IsStudio() then
 local diagnostic=Instance.new("BindableFunction") diagnostic.Name="StudioDiagnostics" diagnostic.Parent=script.Parent
 diagnostic.OnInvoke=function(command,a,b)
  if command=="Tests" then return require("./MarketTests").Run() end
  if command=="ContinuityTests"then return require("./WorldTests").Run()end
  if command=="SingleAccountTests"then return require("./SingleAccountTests").Run()end
  if command=="SecurityTests"then return require("./SecurityTests").Run()end
  if command=="LeaderboardStatus"then return {Cached=leaderboard.Cache,ReadError=leaderboard.ReadError,WriteError=leaderboard.WriteError,Pending=leaderboard.Pending,Scope=Leaderboards.Scope(world.Studio)}end
  if command=="Performance"then local result=table.clone(performance);result.MeanMs=result.TotalMs/math.max(1,result.Frames);return result end
  if command=="Actions" then return actionLog end
  if not market then return {Mode=world.Mode,Status=world:Label(),Error=world.LastError}end
  if command=="Execution"then
   local key=Config.Contracts[a]and a or Config.ContractOrder[1];local book=market.Books[key]
   local orders,levels,trades={},{Bids={},Asks={}},{ }
   for _,side in ipairs({"Bids","Asks"})do for _,level in ipairs(book[side])do
    local ids={};for _,order in ipairs(level.Orders)do table.insert(ids,order.Id)end
    table.insert(levels[side],{Price=level.Price*book.Spec.Tick,Quantity=level.Quantity,Orders=ids})
   end end
   for _,order in pairs(market.Orders)do if order.Contract==key then
    local row=table.clone(order);row.Price=row.Price and row.Price*book.Spec.Tick or nil;row.BlockedReason=market:OrderBlockReason(order)
    table.insert(orders,row)
   end end
   table.sort(orders,function(x,y)return x.Priority<y.Priority end)
   for i=math.max(1,#market.Trades-199),#market.Trades do local trade=market.Trades[i];if trade.Contract==key then table.insert(trades,trade)end end
   return {Contract=key,Step=market.Step,Time=market.Time,FairValue=book.FairReference and book.FairReference*book.Spec.Tick,
    Rules=market.Config.PlayerExecution,PriceBandFraction=market.Config.PriceBandFraction,Book=levels,Orders=orders,Executions=trades,
    Diagnostics=market.ExecutionDiagnostics,LastCloseNotificationError=market.LastCloseNotificationError,RequestQueueDepth=#queue}
  end
  if command=="Profiles"then
   local views={} for uid in pairs(market.Profiles)do views[uid]={Saved=market.Profiles[uid],View=funded:View(uid)}end return views
  end
  if command=="Stats"then
   local views={} for uid in pairs(market.Profiles)do views[uid]=funded:Stats(uid)end return views
  end
  local books={}
  for _,key in ipairs(Config.ContractOrder) do
   local book=market.Books[key]
   books[key]={Last=book.Last and book.Last*book.Spec.Tick,Volume=book.Volume,Up=book.Up,Down=book.Down,Bids=#book.Bids,Asks=#book.Asks,Candles=#book.Candles["1m"]}
  end
  local accounts={}
  for _,id in ipairs(market.AccountOrder) do local account=market.Accounts[id] if account.Player then accounts[id]=market:Snapshot(id,Config.ContractOrder[1],"1m",false) end end
  return {Seed=market.Seed,Mode=world.Mode,Status=world:Label(),Step=market.Step,Time=market.Time,Audit=market:Audit(),Books=books,Accounts=accounts,Participants=#population.Agents,Regime=population.Regime.Name}
 end
end
