-- Disposable three-client fixture. Separate engine/remotes and injected ownership verifier;
-- no production profile, pass ownership, purchase, or DataStore is modified.
local S=game:GetService("StudioTestService")
if not game:GetService("RunService"):IsStudio()or S:GetTestArgs()~="SharedDepthValidation"then return end
local Players=game:GetService("Players");local H=game:GetService("HttpService")
local modules=game.ServerScriptService.MarketReign;local shared=game.ReplicatedStorage.MarketReign
local E=require(modules.MarketEngine);local Access=require(modules.MarketDepthAccess)
local e=E.new(require(shared.MarketConfig),7261)
local folder=Instance.new("Folder");folder.Name="SharedDepthNetworkFixture";folder.Parent=game.ReplicatedStorage
local command=Instance.new("RemoteEvent");command.Name="Command";command.Parent=folder
local update=Instance.new("RemoteEvent");update.Name="Update";update.Parent=folder
local report={Checks={},Clients={},OwnershipQueries=0,Isolated=true}
local players,roles,owners,acks,commands={}, {}, {}, {}, {}
local phase="join";local activeOrder;local callbackError
local function check(name,condition)assert(condition,name);table.insert(report.Checks,name)end
local function await(condition,label)
 local deadline=os.clock()+20
 repeat if callbackError then error(callbackError)end;if condition()then return end;task.wait(.05)until os.clock()>deadline
 error("Timed out: "..label)
end
local access
local function submit(player,request)
 local ok,result=e:Submit(owners[player],request);assert(ok,tostring(result));return result
end
command.OnServerEvent:Connect(function(player,kind,data)
 local ok,err=xpcall(function()
  if not roles[player]then return end
  if kind=="Ack"then
   assert(type(data)=="table"and data.Phase==phase and data.Ok==true,tostring(data and data.Error))
   acks[player]=phase;table.insert(report.Clients[player.Name],data);return
  end
  if phase=="place"and roles[player]==1 and kind=="Place"then
   activeOrder=submit(player,{Contract="BX",Direction=-1,Quantity=3,Type="Limit",Price=5825,StopTicks=100,TargetTicks=200}).Id
  elseif phase=="partial"and roles[player]==2 and kind=="Buy"then
   local result=submit(player,{Contract="BX",Direction=1,Quantity=1,Type="Market"});assert(result.Filled==1)
  elseif phase=="foreign_cancel"and roles[player]==3 and kind=="Cancel"then
   local ok=e:Cancel(owners[player],activeOrder);assert(not ok and e.Orders[activeOrder].Remaining==2)
  elseif phase=="cancel"and roles[player]==1 and kind=="Cancel"then assert(e:Cancel(owners[player],activeOrder))
  elseif phase=="repost"and roles[player]==1 and kind=="Place"then
   activeOrder=submit(player,{Contract="BX",Direction=-1,Quantity=2,Type="Limit",Price=5825.25}).Id
  elseif phase=="fill"and roles[player]==2 and kind=="Buy"then
   local result=submit(player,{Contract="BX",Direction=1,Quantity=2,Type="Market"});assert(result.Filled==2)
  elseif phase=="disconnect_order"and roles[player]==1 and kind=="Place"then
   activeOrder=submit(player,{Contract="BX",Direction=1,Quantity=4,Type="Limit",Price=5824}).Id
  else return end
  commands[phase]=true
 end,debug.traceback)
 if not ok then callbackError=err end
end)
Players.PlayerRemoving:Connect(function(player)if owners[player]then e:SetConnected(owners[player],false);access:Forget(player)end end)
local ok,err=xpcall(function()
 await(function()return #Players:GetPlayers()>=3 end,"three real Studio clients")
 players=Players:GetPlayers();table.sort(players,function(a,b)return a.Name<b.Name end)
 local connected={}
 for i,player in ipairs(players)do
  roles[player]=i;owners[player]="network:"..player.UserId;connected[owners[player]]=true
  e:AddAccount(owners[player],100000,100,.9,true);report.Clients[player.Name]={}
  player:SetAttribute("DepthTestRole",i)
 end
 e:SetConnectedOwners(connected);e:AddAccount("participant",1e9,10000,.99,false)
 local verifier={UserOwnsGamePassAsync=function(_,uid,id)
  assert(id==2006894567);report.OwnershipQueries+=1;return uid==players[2].UserId
 end}
 access=Access.new(2006894567,verifier)
 for _,player in ipairs(players)do access:Refresh(player)end
 await(function()return access:Status(players[2]).State=="Owned"end,"verified fixture ownership")
 local function broadcast(name)
  phase=name
  for _,player in ipairs(players)do if player.Parent==Players then
   local packet=e:Snapshot(owners[player],"BX","1m",true);access:Apply(packet,player,"BX")
   update:FireClient(player,{Phase=name,Packet=packet})
  end end
  await(function()for _,player in ipairs(players)do if player.Parent==Players and acks[player]~=name then return false end end;return true end,name.." client observations")
 end
 local function action(name,role,kind)
  phase=name;update:FireClient(players[role],{Action=kind,Phase=name})
  await(function()return commands[name]end,name.." client command")
 end
 -- Handshake allows all LocalScripts to connect before the first broadcast.
 task.wait(2)
 broadcast("empty")
 action("place",1,"Place");broadcast("placed")
 check("A real client order rests in the shared engine",e.Orders[activeOrder].Remaining==3)
 action("partial",2,"Buy");broadcast("partial_fill")
 check("Partial fills reduce exact displayed remaining quantity",e.Orders[activeOrder].Remaining==2)
 action("foreign_cancel",3,"Cancel");broadcast("foreign_cancel_rejected")
 check("Another client cannot cancel the owner's order",e.Orders[activeOrder].Remaining==2)
 action("cancel",1,"Cancel");broadcast("cancelled")
 check("Owner cancellation immediately removes the level",not e.Orders[activeOrder])
 action("repost",1,"Place");broadcast("reposted")
 action("fill",2,"Buy");broadcast("fully_filled")
 check("Full fills remove the level and settle both players",not e.Orders[activeOrder]and e.Accounts[owners[players[2]]].Positions.BX.Quantity==3)
 action("disconnect_order",1,"Place");broadcast("before_disconnect")
 phase="leave";update:FireClient(players[1],{Action="Leave",Phase=phase})
 await(function()return players[1].Parent~=Players end,"actual client disconnect")
 broadcast("after_disconnect")
 check("Disconnect removes resting orders but keeps position protection",not e.Orders[activeOrder]and e.Accounts[owners[players[1]]].Positions.BX.Stop~=nil)
 check("Ownership was queried server-side for every fixture client",report.OwnershipQueries==3)
 report.Audit=e:Audit();report.ClientCount=#players
end,debug.traceback)
report.Ok=ok;report.Error=not ok and err or nil
print("SHARED_DEPTH_MULTIPLAYER "..H:JSONEncode(report))
S:EndTest(report)
