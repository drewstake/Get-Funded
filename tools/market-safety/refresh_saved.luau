-- Owner refresh is modeled only in a detached copy, after the saved exit clears.
local fs=require('@lune/fs');local serde=require('@lune/serde')
local env=require('./environment');local http=env.game:GetService('HttpService')
local CP=require('./candidate/WorldCheckpoint');local C=require('./candidate/MarketConfig')
local F=require('./candidate/FundedAccounts');local Refresh=require('./candidate/BotRefresh')
local Policy=require('./candidate/PlayerExecution')
local output=__OUTPUT__;local export=http:JSONDecode(fs.readFile(__SNAPSHOT__))
local e,p=CP.Restore(CP.Decode(export.Checkpoint),C);local a=assert(e.Accounts[__PLAYER__])
for _=1,2400 do p:Step()end
assert(not next(a.Positions),'Saved exit did not clear before refresh')
local balance=a.Balance
local receipt=Refresh.Apply(e,p,Refresh.Prepare(e,p,(p.BotRefreshReceipt and p.BotRefreshReceipt.Sequence or 0)+1,42875739))
assert(a.Balance==balance and not next(a.Positions),'Bot refresh touched the player')
local result={Scope='Detached saved-world refresh and repeat attack',PlayerBalanceBefore=balance,
 SimulatedOwnerRefreshAmount=receipt.Amount,MaxPlayerContracts=0,MinReserveEquity=math.huge,
 Accepted=0,Rejected=0,SimulatedSeconds=1800}
local trade=e._trade
e._trade=function(self,b,incoming,resting,qty)
 assert(Policy.Allows(self,b,resting.Price,incoming.Direction),'Fill escaped price controls')
 trade(self,b,incoming,resting,qty)
 for _,pos in pairs(a.Positions)do
  result.MaxPlayerContracts=math.max(result.MaxPlayerContracts,pos.Quantity)
  assert(pos.Quantity<=C.MarketSafety.PlayerContracts,'Saved rich account bypassed new exposure limit')
 end
end
for i=1,7200 do
 if i%16==1 then
  for _,key in ipairs(C.ContractOrder)do local pos=a.Positions[key]
   if not(pos and pos.Triggered)then
    e:CancelAll(a.Id,key)
    local qty=e:OrderCapacity(a,key,1)
    assert(qty<=C.MarketSafety.PlayerContracts,'Saved rich account received excess entry capacity')
    if qty>0 then for _=1,4 do
     local ok,r=e:Submit(a.Id,{Contract=key,Direction=1,Quantity=qty,Type='Market',Execution='Sliced'})
     if ok then result.Accepted+=1;if e.Orders[r.Id]and not e.Orders[r.Id].ReduceOnly then e:Cancel(a.Id,r.Id)end
     else result.Rejected+=1 end
    end end
   end
  end
 end
 p:Step()
 if i%120==0 then
  for _,agent in ipairs(p.Agents)do if agent.Kind=='Reserve'then
   local equity=e:Summary(e.Accounts[agent.Id]).Equity
   result.MinReserveEquity=math.min(result.MinReserveEquity,equity)
   assert(equity>0,'Repeat attack depleted a refreshed reserve')
  end end
  e:Audit()
 end
end
assert(result.MaxPlayerContracts>0,'Repeat attack did not exercise any entries')
for key in pairs(a.Positions)do assert(F.Perform(e,a.Id,{Action='Close',Contract=key}))end
local started=e.Time
for _=1,2400 do if not next(a.Positions)then break end;p:Step()end
assert(not next(a.Positions),'Saved rich account became stuck again after refresh')
result.Passed=true;result.SecondsUntilFlat=e.Time-started;result.PlayerBalanceAfter=a.Balance
result.Audit=e:Audit();result.NoLiveDataWrites=true
fs.writeFile(output..'/saved-refresh-results.json',serde.encode('json',result,true))
print('SAVED REFRESH PASS; max player',result.MaxPlayerContracts,'min reserve equity',result.MinReserveEquity,'close seconds',result.SecondsUntilFlat)
