-- Temporary Play-only fixture, installed in an isolated DataStore namespace and removed before save.
return function(command,world,engine,funded,clients,emit)
 if not engine then return {Mode=world.Mode,Error=world.LastError}end
 local player=game.Players:GetPlayers()[1];local uid=tostring(player.UserId);local owner=funded:Owner(uid)
 if command=="Freeze"then
  world.Population.Step=function()end
  for _,id in ipairs(engine.AccountOrder)do if not engine.Accounts[id].Player then engine:CancelAll(id)end end
 elseif command=="TP"or command=="SL"or command=="DuplicateTP"or command=="DuplicateSL"then
  local p=assert(engine.Accounts[owner].Positions.BX,"No BX position")
  local target=command:find("TP")and p.Target or p.Stop;assert(target,"Protection disabled")
  engine:AddAccount("qa-maker",1e9,10000,.99,false);engine:AddAccount("qa-taker",1e9,10000,.99,false)
  assert(engine:Submit("qa-maker",{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=target}))
  assert(engine:Submit("qa-taker",{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=target}))
  assert(p.Triggered,"Protection did not trigger")
  assert(not funded:Profile(uid).Events[1],"Should not announce a trigger before a fill")
  engine:ProcessStops()
  if command:find("Duplicate")then
   local events=funded:Profile(uid).Events
   local packet={StatusOnly=true,CanTrade=true,ConnectionStatus=world:Label(),Events=events}
   game.ReplicatedStorage.MarketReign.MarketUpdate:FireClient(player,packet)
   game.ReplicatedStorage.MarketReign.MarketUpdate:FireClient(player,packet)
  end
  emit(player,clients[player])
 elseif command=="Save"then assert(world:Save(false),world.LastError)
 end
 return {Mode=world.Mode,Error=world.LastError,Profile=funded:Profile(uid),View=funded:View(uid),
  Position=engine.Accounts[owner].Positions.BX,History=engine.Accounts[owner].History,Audit=engine:Audit(),Step=engine.Step,
  Store=world.Settings.StoreName,Key=world.Settings.WorldKey}
end
