-- Contract tests: isolated accounts, real two-sided settlement, no live state/services.
local E=require(script.Parent.MarketEngine)
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
local function fresh()
 local c=copy(C);c.BotPopulation=nil;c.Contracts.BX.Last=5230.25
 local e=E.new(c,10315)
 for _,id in ipairs({'player','player2','maker','buyer','other'})do
  local a=e:AddAccount(id,1000000000,1000000,.8,id:sub(1,6)=='player');a.LiquidityProvider=true
 end
 return e,c
end
local function order(e,owner,side,quantity,price,extra)
 local request={Contract='BX',Direction=side,Quantity=quantity,Type=price and 'Limit'or 'Market',Price=price}
 for k,v in pairs(extra or {})do request[k]=v end
 local ok,result=e:Submit(owner,request);assert(ok,tostring(result));return result
end
local function position(quantity)
 local e,c=fresh();local policy=c.PlayerExecution;c.PlayerExecution=nil
 order(e,'maker',-1,quantity,5230.25)
 order(e,'player',1,quantity,nil,{TargetTicks=18,StopTicks=20})
 c.PlayerExecution=policy
 return e,c,e.Accounts.player.Positions.BX
end
local function pop(e,c)return setmetatable({Engine=e,Config=c,Random=P.RNG.new(10315),Agents={}},P)end
function Tests.Run(yieldBetween)
 local rows={};local function test(name,fn)if yieldBetween then yieldBetween()end;local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Captured BX TP: 7946 at 5234.75 cannot be bypassed by bot ask 5235.25 at fair 5181.50',function()
  local e,_,p=position(7946);local target=e.Orders[p.TargetOrder];local priority=target.Priority
  e.Books.BX.FairReference=5181.5/.25;e.Time=2177372.75;e.Step=8709491
  local worse=order(e,'other',-1,2,5235.25);local n=e.NextTrade
  local result=order(e,'buyer',1,91)
  assert(result.Filled==0 and e.NextTrade==n,'Out-of-band bot trade bypassed the TP')
  assert(target.Remaining==7946 and target.Filled==0 and target.BlockedReason=='Waiting · price safeguard')
  assert(target.StatusHistory[#target.StatusHistory].Reason==target.BlockedReason)
  local status=e:Snapshot('player','BX','1m',false).Orders[2]
  assert(status and status.Status:find('price safeguard',1,true),'TP must explain its blocking reason')
  e.Books.BX.FairReference=5234.75/.25
  local filled=order(e,'buyer',1,2)
  assert(filled.Filled==2 and filled.Average==5234.75 and p.Quantity==7944)
  assert(target.Priority==priority and target.Remaining==7944 and e.Orders[worse.Id].Remaining==2)
  e:Audit()
 end)
 test('Player and bot resting liquidity use identical collars for buy and sell aggressors',function()
  for _,side in ipairs({1,-1})do for _,owner in ipairs({'player','maker'})do
   local e=fresh();local price=5230.25+side*8
   order(e,owner,-side,3,price);order(e,'other',-side,3,price+side*.25)
   e.Books.BX.FairReference=5230.25/.25
   local r=order(e,'buyer',side,6)
   assert(r.Filled==0 and e.NextTrade==0,'Participant type changed execution eligibility');e:Audit()
  end end
 end)
 test('Rejected aggressive limits record a bounded reason for players and bots',function()
  local e=fresh();e.Books.BX.FairReference=5230.25/.25
  for i=1,80 do
   local ok=e:Submit(i%2==0 and 'player'or 'maker',{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=5240})
   assert(not ok)
  end
  assert(e.NextOrder==0 and e.ExecutionDiagnostics.RejectedCount==80 and #e.ExecutionDiagnostics.RecentRejections==64)
  assert(e.ExecutionDiagnostics.RecentRejections[64].Reason:find('No order placed',1,true));e:Audit()
 end)
 test('Best eligible price then FIFO, independent of participant type, with partial chunks',function()
  for _,first in ipairs({'player','maker'})do
   local e=fresh();local second=first=='player'and 'maker'or 'player'
   local a=order(e,first,-1,3,5231);local b=order(e,second,-1,4,5231);local worse=order(e,'other',-1,5,5231.25)
   local r=order(e,'buyer',1,5)
   assert(r.Filled==5 and r.Average==5231 and not e.Orders[a.Id]and e.Orders[b.Id].Remaining==2)
   assert(e.Orders[worse.Id].Remaining==5 and e.Trades[1].Quantity==3 and e.Trades[2].Quantity==2)
   e:Audit()
  end
 end)
 test('Amendment no-op retains FIFO; reprice loses priority; cancellation removes exactly one order',function()
  local e=fresh();local a=order(e,'player',-1,3,5231);local b=order(e,'player2',-1,3,5231)
  local priority=e.Orders[a.Id].Priority
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231}))
  assert(e.Orders[a.Id].Priority==priority)
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231.25}))
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231.25,ExpectedQuantity=3,Price=5231}))
  order(e,'buyer',1,3);assert(not e.Orders[b.Id]and e.Orders[a.Id].Remaining==3)
  assert(e:Cancel('player',a.Id));assert(not e:Cancel('player',a.Id));assert(#e.Books.BX.Asks==0);e:Audit()
 end)
 test('TP/SL race cancels residual target and cannot reverse after a partial target fill',function()
  local e,_,p=position(8000);local target=p.TargetOrder
  order(e,'buyer',1,3000,5234.75);assert(p.Quantity==5000 and e.Orders[target].Remaining==5000)
  order(e,'other',1,6000,5225.25)
  order(e,'maker',-1,1);e:ProcessStops();e:ProcessPlayerOrders()
  assert(not e.Accounts.player.Positions.BX and not e.Orders[target])
  for id in pairs(e.Accounts.player.OpenOrders)do assert(not e.Orders[id].Protection,'Orphan protective order')end
  e:Audit()
 end)
 test('Quantity reduction retains FIFO; increase loses FIFO and reserves new capacity',function()
  local e=fresh();local a=order(e,'player',-1,5,5231);local b=order(e,'player2',-1,5,5231)
  local priority=e.Orders[a.Id].Priority
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=5,Price=5231,Quantity=3}))
  assert(e.Orders[a.Id].Priority==priority and e.Orders[a.Id].Remaining==3)
  assert(e:AmendOrder('player',{Contract='BX',OrderId=a.Id,ExpectedPrice=5231,ExpectedQuantity=3,Price=5231,Quantity=6}))
  assert(e.Orders[a.Id].Priority>e.Orders[b.Id].Priority)
  order(e,'buyer',1,6);assert(not e.Orders[b.Id]and e.Orders[a.Id].Remaining==5);e:Audit()
 end)
 test('Bot margin eligibility is rechecked before a resting quote can execute',function()
  local e=fresh();local q=order(e,'maker',-1,10,5231)
  e.Accounts.maker.Balance=1;e.Accounts.maker.Realized=1-e.Accounts.maker.Base
  local r=order(e,'buyer',1,10)
  assert(r.Filled==0 and not e.Orders[q.Id])
  local archived=e.OrderArchive[#e.OrderArchive-1]
  assert(archived.BlockedReason=='Insufficient margin or inventory capacity')
 end)
 test('Snapshot filters ineligible liquidity without retiring or reprioritizing an order',function()
  local e=fresh();local r=order(e,'player',-1,10,5231);local o=e.Orders[r.Id];local priority=o.Priority
  e.Accounts.player.Balance=1000;e.Accounts.player.Realized=1000-e.Accounts.player.Base
  local n=e.NextOrder;local snapshot=e:Snapshot('player2','BX','1m',false)
  assert(#snapshot.Quotes.BX.Depth.Asks==0 and e.Orders[r.Id]==o and o.Priority==priority and e.NextOrder==n)
 end)
 for _,quantity in ipairs({8000,13000,50000})do
  test(quantity..'-contract TP uses matched chunks, tracks residual and never reverses',function()
   local e,_,p=position(quantity);local child=e.Orders[p.TargetOrder];local n=e.NextTrade
   order(e,'buyer',1,quantity-1,5234.75)
   assert(p.Quantity==1 and child.Remaining==1 and e.NextTrade==n+1,'Quantity was split per contract')
   order(e,'other',1,2,5234.75)
   assert(not e.Accounts.player.Positions.BX and not e.Orders[child.Id]and e.NextTrade==n+2)
   assert(e.Accounts.other.Positions.BX.Quantity==1);e:Audit()
  end)
 end
 test('Sparse liquidity preserves an active target and later arrival gets only available quantity',function()
  local e,_,p=position(13000);local id=p.TargetOrder;local priority=e.Orders[id].Priority
  for _=1,10 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(p.Quantity==13000 and e.Orders[id].Priority==priority)
  order(e,'buyer',1,7,5234.75);assert(p.Quantity==12993 and e.Orders[id].Remaining==12993);e:Audit()
 end)
 test('Checkpoint preserves blocked TP priority and exact continuation, independent of snapshot reads',function()
  local e,c,p=position(13000);e.Books.BX.FairReference=5181.5/.25
  order(e,'buyer',1,1);local id=p.TargetOrder
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop(e,c)))),c)
  assert(restored.Orders[id].Priority==e.Orders[id].Priority and restored.Orders[id].Remaining==13000)
  for _,engine in ipairs({e,restored})do engine.Books.BX.FairReference=5234.75/.25 end
  for i=1,8 do
   e:Snapshot('player','BX','1m',false)
   for _,engine in ipairs({e,restored})do engine:AdvanceClock(.25);order(engine,'buyer',1,i,5234.75)end
  end
  assert(e.TradeHash==restored.TradeHash and e.NextOrder==restored.NextOrder)
  assert(e.Accounts.player.Positions.BX.Quantity==restored.Accounts.player.Positions.BX.Quantity)
  e:Audit();restored:Audit()
 end)
 test('Self-trade prevention cancels own older quote and never creates a fill',function()
  local e=fresh();local q=order(e,'player',-1,10,5231);local n=e.NextTrade
  local r=order(e,'player',1,10);assert(r.Filled==0 and e.NextTrade==n and not e.Orders[q.Id]);e:Audit()
 end)
 test('Closing notification failure cannot interrupt settlement between the two counterparties',function()
  local e,_,p=position(2)
  e.OnFundedClose=function()error('Injected presentation callback failure')end
  order(e,'buyer',1,2,5234.75)
  assert(not e.Accounts.player.Positions.BX and e.CloseNotificationErrors==1)
  assert(e.LastCloseNotificationError.TradeId==e.NextTrade and not e.Orders[p.TargetOrder]);e:Audit()
 end)
 test('Atomic save encoding matches detached capture and cannot change after later fills',function()
  local e,c,p=position(8000);local population=pop(e,c)
  local detached=CP.Capture(e,population)
  local record=CP.EncodeWorld(e,population);local saved=CP.Decode(record)
  local function equal(a,b)
   if type(a)~='table'then assert(a==b);return end
   for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil)end
  end
  equal(detached,saved)
  order(e,'buyer',1,2,5234.75)
  equal(detached,CP.Decode(record))
  assert(e.Accounts.player.Positions.BX.Quantity==7998 and p.Quantity==7998)
 end)
 return rows
end
return Tests
