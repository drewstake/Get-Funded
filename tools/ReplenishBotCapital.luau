-- One-time maintenance transform. Run through World:TransformSaved, never a raw datastore write.
-- Supply a unique operation ID; the saved receipt makes retries of this operation harmless.
return function(engine,population,operationId)
 assert(type(operationId)=="string" and #operationId>0,"Operation ID required")
 local previous=population.BotReplenishment
 if previous and previous.Id==operationId then return previous end
 local receipt={Id=operationId,Time=engine.Time,Step=engine.Step,Count=0,Unchanged=0,Amount=0,Accounts={},Markets={}}
 local seen={}
 for _,agent in ipairs(population.Agents)do
  local book=engine.Books[agent.Key]
  if not book or book.Spec.CloseOnly or agent.Retiring then continue end
  local account=assert(engine.Accounts[agent.Id],"Bot account missing")
  assert(not seen[agent.Id] and not account.Player and not account.House and not account.Archive,"Invalid bot account")
  seen[agent.Id]=true
  assert(type(agent.Budget)=="number" and agent.Budget>0 and agent.Budget<math.huge,"Invalid starting capital")
  local amount=math.max(0,agent.Budget-account.Balance)
  if amount<=0 then receipt.Unchanged+=1;continue end
  -- Capital deposits raise both base and balance. Realized P&L and the trade cash ledger stay intact.
  local before=account.Balance
  account.StartingCapital=account.StartingCapital or account.Base
  account.NetCapitalAdjustments=(account.NetCapitalAdjustments or 0)+amount
  account.CapitalAdjustments=account.CapitalAdjustments or {}
  table.insert(account.CapitalAdjustments,{OperationId=operationId,Time=engine.Time,Amount=amount,Reason="Manual bot replenishment"})
  account.Base+=amount
  account.Balance=account.Base+(account.PnlBaseline or 0)+account.Realized
  account.LossLimit=account.Base
  account.Revision+=1
  assert(math.abs(account.Balance-agent.Budget)<0.001,"Refill accounting mismatch")
  receipt.Count+=1
  receipt.Amount+=amount
  receipt.Markets[agent.Key]=(receipt.Markets[agent.Key] or 0)+amount
  receipt.Accounts[agent.Id]={Before=before,After=account.Balance,Amount=amount}
 end
 population.BotReplenishment=receipt
 engine:Audit()
 return receipt
end
