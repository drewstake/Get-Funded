local fs=require('@lune/fs');local serde=require('@lune/serde');local env=require('./environment')
local saved=env.game:GetService('HttpService'):JSONDecode(fs.readFile('backups/execution-integrity-20261015/private-live-capture.json'))
local variants={baseline={require('./baseline/WorldCheckpoint'),require('./baseline/MarketConfig')},candidate={require('./candidate/WorldCheckpoint'),require('./candidate/MarketConfig')}}
local report={SourceStep=saved.Step,Runs={},Trace={},Audits={}}
local function run(name,steps,verify)
 local modules=variants[name];local e,p=modules[1].Restore(saved.Snapshot,modules[2]);e.ConnectedOwners=saved.ConnectedOwners
 local costs={};local scans,submits,retries=0,0,0;local retryReasons={}
 local prune=e._pruneBook;e._pruneBook=function(self,b)scans+=1;return prune(self,b)end
 local submit=e.Submit;e.Submit=function(self,owner,request,...)
  local pos=self.Accounts[owner].Positions[request.Contract];local reason=(pos and pos.Triggered or 'Voluntary')..':'..request.Type
  submits+=1;local ok,result=submit(self,owner,request,...)
  if request.ReduceOnly and (not ok or result.Filled==0)then retries+=1;retryReasons[reason]=(retryReasons[reason]or 0)+1 end
  return ok,result
 end
 local violations={};local trade=e._trade
 if verify then e._trade=function(self,b,incoming,resting,qty)
  local a=self.Accounts[incoming.Owner];local r=self.Accounts[resting.Owner]
  local function before(account)
   local pos=account.Positions[b.Key]
   return {Net=pos and pos.Direction*pos.Quantity or 0,Cash=account.CashFlow,Realized=account.Realized,Entry=pos and pos.Entry}
  end
  local aa,rr=before(a),before(r);local price=resting.Price*b.Spec.Tick
  local tp=self.Orders[saved.Target.Id]
  if b.Key=='BX'and incoming.Direction==1 and tp and not tp.Queued and tp.Remaining>0 and resting~=tp
   and (resting.Price>tp.Price or resting.Price==tp.Price and resting.Priority>tp.Priority)then
   table.insert(violations,{TradeId=self.NextTrade+1,Step=self.Step,Price=price,Quantity=qty,Fair=b.FairReference*b.Spec.Tick,Target=tp.Price*b.Spec.Tick})
  end
  trade(self,b,incoming,resting,qty)
  for _,pair in ipairs({{a,aa,incoming.Direction},{r,rr,resting.Direction}})do
   local account,old,side=pair[1],pair[2],pair[3];local pos=account.Positions[b.Key]
   assert((pos and pos.Quantity*pos.Direction or 0)==old.Net+qty*side,'Fill inventory mismatch')
   assert(math.abs(account.CashFlow-(old.Cash-price*qty*side*b.Spec.Multiplier))<.001,'Fill cash mismatch')
   local closed=old.Net*side<0 and math.min(math.abs(old.Net),qty)or 0
   local realized=closed>0 and(price-old.Entry)*closed*math.sign(old.Net)*b.Spec.Multiplier or 0
   assert(math.abs(account.Realized-old.Realized-realized)<.001,'Fill realized P&L mismatch')
   assert(math.abs(account.Balance-account.Base-account.Realized)<.001,'Balance mismatch')
  end
 end end
 local firstOrder,firstTrade,firstVolume=e.NextOrder,e.NextTrade,e.TotalVolume
 local started=os.clock()
 for i=1,steps do
  local at=os.clock();p:Step()
  if i%6==0 then e:Snapshot(saved.Target.Owner,'BX','1m',false)end
  table.insert(costs,(os.clock()-at)*1000)
 end
 local elapsed=(os.clock()-started)*1000;table.sort(costs)
 local result={Variant=name,Steps=steps,TotalMs=elapsed,MeanMs=elapsed/steps,P95Ms=costs[math.ceil(steps*.95)],MaxMs=costs[steps],ThroughputStepsPerSecond=steps/elapsed*1000,
  FullBookScans=scans,SubmitCalls=submits,RejectedSubmissions=e.ExecutionDiagnostics and e.ExecutionDiagnostics.RejectedCount or 0,FailedExitAttempts=retries,RetryReasons=retryReasons,NewOrders=e.NextOrder-firstOrder,NewTrades=e.NextTrade-firstTrade,Volume=e.TotalVolume-firstVolume,Hash=e.TradeHash}
 if verify then
  report.Trace[name]=violations;report.Audits[name]=e:Audit()
  if name=='candidate'then assert(#violations==0,'Better TP bypassed in captured-state continuation')end
 else table.insert(report.Runs,result)end
 return result,e,p
end
run('baseline',512,true);local _,e1=run('candidate',512,true);local _,e2=run('candidate',512,true)
assert(e1.TradeHash==e2.TradeHash and e1.NextOrder==e2.NextOrder and e1.TotalVolume==e2.TotalVolume,'Captured continuation is not deterministic')
report.Deterministic={Steps=512,Hash=e1.TradeHash,Orders=e1.NextOrder,Volume=e1.TotalVolume}
for _,variant in ipairs({'baseline','candidate','candidate','baseline','baseline','candidate'})do print(serde.encode('json',run(variant,512,false)))end
fs.writeFile('output/execution-integrity-20261015/captured-replay-benchmark.json',serde.encode('json',report))
print('Baseline bypasses',#report.Trace.baseline,'Candidate bypasses',#report.Trace.candidate)
