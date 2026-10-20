-- Template: insert the current MarketServer source at the marker before running in Studio Edit.
-- All accounts, remotes, clocks, entitlement responses and persistence are isolated fixtures.
local RealGame=game
local Shared=RealGame.ReplicatedStorage.DepthSpamShared
local Server=RealGame.ServerScriptService.DepthSpamServer
local function clone(x)if type(x)~="table"then return x end local r={}for k,v in pairs(x)do r[k]=clone(v)end return r end
local AuditConfig=clone(require(Shared.MarketConfig))
AuditConfig.BotPopulation=nil -- This fixture deliberately isolates reserve liquidity.
AuditConfig.ParticipantsPerInstrument=0;AuditConfig.MakersPerInstrument=0;AuditConfig.ScalpersPerInstrument=0
AuditConfig.WhaleFrequency=0;AuditConfig.NewsFrequency=0
AuditConfig.Regimes={{Name="Fixed",Weight=1,Volatility=0,Liquidity=1,Activity=1,Trend=0}}
local AuditLadder=clone(require(Shared.ProgressionConfig));AuditLadder.StartingBalance=1000000000
local AuditEngine=require(Server.MarketEngine).new(AuditConfig,1729)
local AuditPopulation=require(Server.Participants).new(AuditEngine)
local now=100
local function signal()local s={}function s:Connect(fn)self.Callback=fn;return {Disconnect=function()end}end return s end
local auditPlayer={UserId=901,Name="AuditOne",DisplayName="Audit One"}
local otherPlayer={UserId=902,Name="AuditTwo",DisplayName="Audit Two"}
local fakePlayers={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function()return {auditPlayer,otherPlayer}end}
local fakeRun={Heartbeat=signal(),IsStudio=function()return false end}
local fakeTeleport={TeleportInitFailed=signal()}
local remoteMap,packets,counts={},{},{}
local fakeRoot={SetAttribute=function()end,FindFirstChild=function(_,n)return remoteMap[n]end,MarketConfig="config",ProgressionConfig="ladder"}
local fakeInstance={}
function fakeInstance.new(class)
 local o={ClassName=class,OnServerEvent=signal(),Triggered=signal(),Destroy=function()end}
 function o:FireClient(player,packet)
  counts[player]=(counts[player]or 0)+1;packets[player]=packet
 end
 return setmetatable(o,{__newindex=function(t,k,v)rawset(t,k,v);if k=="Name"then remoteMap[v]=t end end})
end
local auditWorld={Studio=true,Engine=AuditEngine,Population=AuditPopulation,Epoch=1,Mode="Local",
 CanRun=function()return true end,Label=function()return "AUDIT"end,Maintain=function()end,HasCapacity=function()return true end}
local modules={config=AuditConfig,ladder=AuditLadder,WorldService={new=function()return auditWorld end},
 FundedAccounts=require(Server.FundedAccounts),LeaderboardRanking=require(Server.LeaderboardRanking),
 ReplyBuffer=require(Server.ReplyBuffer),WorldConfig=require(Server.WorldConfig),OwnerResetCommand=require(Server.OwnerResetCommand),OwnerGiveCommand=require(Server.OwnerGiveCommand),
 LeaderboardService={new=function()return {}end},MarketDepthAccess={new=function()return {
  Refresh=function()end,Forget=function()end,Apply=function(_,packet)packet.DepthAccess={Allowed=true,State="Owned"}end}end}}
local game={GetService=function(_,n)
 if n=="ReplicatedStorage"then return {WaitForChild=function()return fakeRoot end}
 elseif n=="Players"then return fakePlayers elseif n=="RunService"then return fakeRun elseif n=="TeleportService"then return fakeTeleport
 elseif n=="MarketplaceService"then return {PromptGamePassPurchaseFinished=signal()}
 elseif n=="TextChatService"then return {FindFirstChild=function()end}end
 error("Unexpected service: "..n)
end,BindToClose=function()end,CreatorType=Enum.CreatorType.User,CreatorId=0}
local script={Parent={}};for name in pairs(modules)do script.Parent[name]=name end
local require=function(k)assert(modules[k],"Unexpected module: "..tostring(k));return modules[k]end
local Instance=fakeInstance
local task={spawn=function()end}
local os={clock=function()return now end,time=function()return 1000 end}
local debug={profilebegin=function()end,profileend=function()end}
local warnings={};local warn=function(message)table.insert(warnings,message)end
-- INSERT_SERVER_SOURCE
local results={}
local function check(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
local nextId=0
local function send(player,request)
 nextId+=1;request.Id=nextId;request.ExpectedAccount=request.ExpectedAccount or clients[player].Owner
 requestRemote.OnServerEvent.Callback(player,request)
end
local function frame(dt)dt=dt or .1;now+=dt;fakeRun.Heartbeat.Callback(dt)end
frame()
check("Queued market order serializes and keeps both subscribers live",function()
 send(auditPlayer,{Action="Subscribe",Contract="BX",Timeframe="1m"})
 send(otherPlayer,{Action="Subscribe",Contract="BX",Timeframe="1m"})
 send(auditPlayer,{Action="Place",Contract="BX",Direction=1,Quantity=1000000,Type="Market",Execution="Sliced"})
 frame()
 local packet=packets[auditPlayer];assert(packet and not packet.StatusOnly and packet.CanTrade)
 local found=false;for _,order in ipairs(packet.Orders or {})do if order.Type=="Market"then
  assert(order.Price==nil and order.Queued and order.Quantity>0);found=true
 end end
 assert(found,"Queued market packet was not delivered");assert(packets[otherPlayer] and #warnings==0)
 assert(#packet.Quotes.BX.Depth.Asks>0 and #packet.Quotes.BX.Depth.Bids>0)
end)
check("1200 rapid submissions retain depth broadcasts and bounded server work",function()
 local before=counts[auditPlayer];local beforeOther=counts[otherPlayer];local start=sequence
 for _=1,120 do
  for _=1,10 do send(auditPlayer,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"})end
  frame(1/60)
 end
 assert(sequence-start<=32,"Spam bypassed server allowance")
 assert(counts[auditPlayer]-before>=19 and counts[otherPlayer]-beforeOther>=19,"Depth stream stalled")
 assert(#queue==0 and #clients[auditPlayer].Replies<=64 and #warnings==0)
 return {Requests=1200,AcceptedForProcessing=sequence-start,DepthPackets=counts[auditPlayer]-before,OtherPlayerPackets=counts[otherPlayer]-beforeOther}
end)
check("Subscription recovery bypasses exhausted trade allowance and coalesces updates",function()
 clients[auditPlayer].Tokens=0;clients[auditPlayer].TokenTime=now
 local before=counts[auditPlayer]
 send(auditPlayer,{Action="Subscribe",Contract="BT",Timeframe="5m"})
 send(auditPlayer,{Action="Subscribe",Contract="BG",Timeframe="1m"})
 assert(counts[auditPlayer]==before,"Subscription caused an immediate packet burst")
 frame();assert(packets[auditPlayer].Contract=="BG"and packets[auditPlayer].Full)
 send(otherPlayer,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"});frame()
 local found=false;for _,r in ipairs(packets[otherPlayer].Replies or{})do if r.Kind=="Place"then assert(r.Ok);found=true end end
 assert(found,"Spam blocked another player's trade")
end)
check("One failed subscriber does not interrupt another; next packet recovers fully",function()
 local original=market.Snapshot;local owner=clients[auditPlayer].Owner
 market.Snapshot=function(self,id,...)if id==owner then error("Injected packet failure")end return original(self,id,...)end
 local before=counts[otherPlayer];frame();assert(counts[otherPlayer]>before)
 local warned=#warnings;for _=1,4 do frame()end;assert(#warnings==warned,"Unbounded repeated error logging")
 market.Snapshot=original;frame();assert(packets[auditPlayer].Full and packets[auditPlayer].CanTrade)
end)
check("Cancellation clears the queued market order while depth keeps streaming",function()
 now+=4
 local a=market.Accounts[clients[auditPlayer].Owner];local id=next(a.OpenOrders);assert(id)
 send(auditPlayer,{Action="Cancel",OrderId=id});frame()
 assert(not market.Orders[id]);assert(packets[auditPlayer].Orders and #packets[auditPlayer].Orders==0)
 assert(packets[auditPlayer].Quotes.BG.Depth)
 market:Audit()
end)
return results
