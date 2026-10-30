"""Execute the current server source against fake services, remotes and two isolated players."""
from pathlib import Path
prefix=Path('output/security-audit-2026-09-30/server-boundary-harness.luau').read_text(encoding='utf-8').split('-- BEGIN UNCHANGED MarketServer.server.luau')[0]
prefix=prefix.replace('local modules={config=', 'local modules={ReplyBuffer=require(Server.ReplyBuffer),WorldConfig=require(Server.WorldConfig),config=')
prefix=prefix.replace('local script={Parent={WorldService=', 'local script={Parent={ReplyBuffer="ReplyBuffer",WorldConfig="WorldConfig",WorldService=')
prefix=prefix.replace('Maintain=function()end}', 'Maintain=function()end,HasCapacity=function()return true end}')
prefix=prefix.replace('local os={clock=', 'local debug={profilebegin=function()end,profileend=function()end}\nlocal os={clock=')
suffix=r'''
local function frame(dt)fakeRun.Heartbeat.Callback(dt or AuditConfig.StepSeconds/AuditConfig.SimulationSpeed+.000001)end
frame()
local nextId=0
local function send(player,req)
 now+=1;nextId+=1;req.Id=nextId;remoteMap.OrderRequest.OnServerEvent.Callback(player,req);frame()
 local pending=clients[player].Replies
 local delivered=remoteMap.MarketUpdate.LastPacket and remoteMap.MarketUpdate.LastPacket.Replies or {}
 return pending[#pending] or delivered[#delivered]
end
local results={}
local function check(name,fn)local ok,err=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and 'Passed' or tostring(err)})end
check('New players land with one account without a Start request',function()
 assert(clients[auditPlayer].Owner and clients[otherPlayer].Owner)
 assert(AuditEngine.Accounts[clients[auditPlayer].Owner].Balance==5000)
end)
check('Removed Account, Copy, Purchase and Activate actions never enter the queue',function()
 for _,action in ipairs({'Account','Copy','Purchase','Activate'}) do
  now+=1;nextId+=1;remoteMap.OrderRequest.OnServerEvent.Callback(auditPlayer,{Id=nextId,Action=action,Key=clients[otherPlayer].Owner})
  assert(not clients[auditPlayer].Seen[nextId] and #queue==0)
 end
end)
check('Owner, balance, fill price and reward fields cannot be forged',function()
 local id=clients[auditPlayer].Owner;local other=clients[otherPlayer].Owner
 local r=send(auditPlayer,{Action='Place',ExpectedAccount=id,Owner=other,Balance=999999,FillTicks=1,Awards={Balance100K=true},Contract='BX',Direction=1,Quantity=1,Type='Market'})
 assert(r.Ok and AuditEngine.Accounts[id].Positions.BX and not AuditEngine.Accounts[other].Positions.BX)
 assert(AuditEngine.Accounts[id].Balance==5000 and not next(funded:Profile('901').Awards))
 assert(send(auditPlayer,{Action='Close',ExpectedAccount=id,Contract='BX'}).Ok)
end)
check('Other-player tokens and foreign cancellation are rejected',function()
 local id=clients[auditPlayer].Owner;local other=clients[otherPlayer].Owner
 assert(not send(auditPlayer,{Action='Place',ExpectedAccount=other,Contract='BX',Direction=1,Quantity=1,Type='Market'}).Ok)
 local o=send(otherPlayer,{Action='Place',ExpectedAccount=other,Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=AuditConfig.Contracts.BX.Last-100})
 assert(o.Ok);assert(not send(auditPlayer,{Action='Cancel',ExpectedAccount=id,OrderId=o.Result.Id}).Ok)
 assert(AuditEngine.Orders[o.Result.Id])
end)
check('Restart validates failed run, current token and queue owner; duplicate cannot grant twice',function()
 local id=clients[auditPlayer].Owner
 assert(not send(auditPlayer,{Action='Restart',ExpectedAccount=id}).Ok)
 local a=AuditEngine.Accounts[id];local b=AuditEngine.Books.BX;b.Last=24000;b.Bids={};b.Asks={}
 assert(AuditEngine:Submit(id,{Contract='BX',Direction=1,Quantity=1,Type='Market'}));b.Last-=400
 AuditEngine:AdvanceClock(.25);funded:Evaluate('901');assert(a.Depleted)
 assert(not send(auditPlayer,{Action='Restart',ExpectedAccount=clients[otherPlayer].Owner}).Ok)
 now+=1
 for _,req in ipairs({{Action='Restart'},{Action='Restart'},{Action='Place',Contract='BX',Direction=1,Quantity=1,Type='Market'}}) do
  nextId+=1;req.Id=nextId;req.ExpectedAccount=id;remoteMap.OrderRequest.OnServerEvent.Callback(auditPlayer,req)
 end
 frame();local current=clients[auditPlayer].Owner;assert(current~=id)
 assert(AuditEngine.Accounts[current].Balance==5000 and not next(AuditEngine.Accounts[current].Positions))
 assert(funded:Profile('901').Run==2 and funded:Earned(funded:Profile('901'))==-5000)
end)
check('New connection keeps account, run and restart budget',function()
 local p=funded:Profile('901');local id=p.Account;local tokens=p.Limits.Reset.Tokens
 clients[auditPlayer]=nil;fakePlayers.PlayerAdded.Callback(auditPlayer);frame()
 assert(clients[auditPlayer].Owner==id and funded:Profile('901').Run==2 and p.Limits.Reset.Tokens==tokens)
end)
check('Deduplicated requests and input validation preserve limits',function()
 local id=clients[auditPlayer].Owner;now+=1;nextId+=1
 local req={Id=nextId,Action='Place',ExpectedAccount=id,Contract='BX',Direction=1,Quantity=1,Type='Market'}
 remoteMap.OrderRequest.OnServerEvent.Callback(auditPlayer,req);remoteMap.OrderRequest.OnServerEvent.Callback(auditPlayer,req);frame()
 assert(AuditEngine.Accounts[id].Positions.BX.Quantity==1)
 for _,value in ipairs({math.huge,0/0,{},true}) do
  now+=1;nextId+=1;remoteMap.OrderRequest.OnServerEvent.Callback(auditPlayer,{Id=nextId,Action='Place',Quantity=value})
  assert(not clients[auditPlayer].Seen[nextId])
 end
end)
check('Paused exchange refuses restarts and trades',function()
 auditWorld.CanRun=function()return false end
 local id=clients[auditPlayer].Owner
 assert(not send(auditPlayer,{Action='Restart',ExpectedAccount=id}).Ok)
 assert(not send(auditPlayer,{Action='Place',ExpectedAccount=id,Contract='BX',Direction=1,Quantity=1,Type='Market'}).Ok)
 assert(clients[auditPlayer].Owner==id)
end)
AuditEngine:Audit()
return results
'''
Path('output/single-account-20261001/server-boundary.luau').write_text(prefix+'\n'+Path('src/server/MarketServer.server.luau').read_text(encoding='utf-8')+'\n'+suffix,encoding='utf-8')
