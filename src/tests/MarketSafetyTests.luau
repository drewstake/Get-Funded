-- Finite counterparties, real settlement, no live services or capital injections.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local F=require(script.Parent.FundedAccounts)
local Safety=require(script.Parent.MarketSafety)
local Policy=require(script.Parent.PlayerExecution)
local Tests={}
local function copy(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=copy(x)end return t end
local function order(e,id,side,qty,price,extra)
 local r={Contract='BX',Direction=side,Quantity=qty,Type=price and 'Limit'or 'Market',Price=price}
 for k,v in pairs(extra or {})do r[k]=v end
 local ok,result=e:Submit(id,r);assert(ok,tostring(result));return result
end
local function fixture(side,quantity)
 local c=copy(C);c.ContractOrder={'BX'};c.Contracts.BX.Last=5000
 local e=E.new(c,177);local a=e:AddAccount('player',100000000,10000,.8,true)
 local r=e:AddAccount('reserve',5000000,2000,.8,false);r.PolicyCapitalTarget=5000000
 local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(177),Agents={{Id=r.Id,Key='BX',Kind='Reserve',Budget=5000000}}},P)
 if quantity then
  local execution=c.PlayerExecution;c.PlayerExecution=nil
  order(e,r.Id,-side,quantity,5000);order(e,a.Id,side,quantity);c.PlayerExecution=execution
 end
 Safety.Adopt(e,p);return e,a,r,p
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(r or 'Passed')or tostring(r)})end
 test('Repeated resets invalidate the player risk index even when account count stays constant',function()
  local e=fixture();local f=F.new(e,require(game.ReplicatedStorage.MarketReign.ProgressionConfig),e.Config)
  local p=f:Join('reset-index');e:SetConnectedOwners({[p.Account]=true});local retired={}
  for _=1,3 do
   local old=p.Account
   assert(e:OrderCapacity(e.Accounts[old],'BX',1)>0) -- Populate the derived player index.
   local count=#e.AccountOrder
   assert(f:ResetAccount('reset-index',old));assert(p.Account~=old and not e.Accounts[old])
   e:SetConnected(p.Account,true)
   assert(e:OrderCapacity(e.Accounts[p.Account],'BX',1)>0)
   table.insert(retired,old)
   if p.Run>2 then assert(#e.AccountOrder==count,'Fixture must replace a run without growing the account list')end
   e:Audit()
  end
  for _,id in ipairs(retired)do assert(not e.ConnectedOwners[id],'Retired run retains a connection entry')end
 end)
 test('One to nine real bids permit one manual close; cancellation cannot reset the allowance',function()
  for _,side in ipairs({-1,1})do for depth=1,9 do
   local e,a,r=fixture(side,3);order(e,r.Id,side,depth,5000)
   local first=order(e,a.Id,-side,1,nil,{ReduceOnly=true})
   assert(first.Filled==1 and a.Positions.BX.Quantity==2)
   local second=order(e,a.Id,-side,1,nil,{ReduceOnly=true});assert(second.Filled==0)
   if e.Orders[second.Id]then e:Cancel(a.Id,second.Id)end
   assert(order(e,a.Id,-side,1,nil,{ReduceOnly=true}).Filled==0);e:Audit()
  end end
 end)
 test('Stalled manual closes meet opposing market exits, preserve quantity and never reverse',function()
  for _,side in ipairs({-1,1})do
   local e,a,r=fixture(side,30);local volume=e.TotalVolume
   local ok,result=F.Perform(e,a.Id,{Action='Close',Contract='BX'});assert(ok)
   local exit=e.Orders[result.Id];assert(exit.ExitFallback and exit.Type=='Limit'and exit.ReduceOnly)
   assert(e.TotalVolume==volume,'Empty market fabricated a fill')
   order(e,r.Id,side,7,nil,{ReduceOnly=true});assert(a.Positions.BX.Quantity==23 and exit.Remaining==23)
   order(e,r.Id,side,23,nil,{ReduceOnly=true});assert(not a.Positions.BX and not r.Positions.BX and not e.Orders[result.Id])
   e:AdvanceClock(20);e:ProcessPlayerOrders();assert(not next(a.Positions));e:Audit()
  end
 end)
 test('Cancelling a resting close prevents later fills and clears player-close state',function()
  local e,a,r=fixture(1,3);local _,result=F.Perform(e,a.Id,{Action='Close',Contract='BX'})
  assert(F.Perform(e,a.Id,{Action='Cancel',OrderId=result.Id}));assert(not a.Positions.BX.Triggered)
  order(e,r.Id,1,3,nil,{ReduceOnly=true,Immediate=true});e:AdvanceClock(20);e:ProcessPlayerOrders()
  assert(a.Positions.BX.Quantity==3);e:Audit()
 end)
 test('Server Close exits ignore entry throttles; client protective fields never grant that authority',function()
  local e,a,r=fixture(1,12);local state=Policy.State(e)
  state.Owners['player:-1']=e.Config.PlayerExecution.OwnerContracts
  state.Markets['BX:-1']={Limit=0,Used=0}
  order(e,r.Id,1,12,5000,{ReduceOnly=true})
  local fake=order(e,a.Id,-1,12,nil,{ReduceOnly=true,Execution='Immediate',Protection='Player close',ProtectivePosition=a.Positions.BX.Id})
  assert(fake.Filled==0 and a.Positions.BX.Quantity==12)
  local ok,closed=F.Perform(e,a.Id,{Action='Close',Contract='BX'})
  assert(ok and closed.Filled==12 and not a.Positions.BX);e:Audit()
 end)
 test('A protective stop fallback remains tied to its position and retains FIFO when retrying',function()
  local e,a,r,p=fixture(1,3);local pos=a.Positions.BX;pos.Triggered='Stop loss'
  e.PendingStops={{Owner=a.Id,Contract='BX',Position=pos.Id}};e:ProcessStops()
  local id=pos.ExitOrder;assert(e.Orders[id].ExitFallback)
  -- This fixture intentionally has a partial population; serialization still preserves the engine.
  local state=copy(e.Orders[id]);e:AdvanceClock(5);e:ProcessPlayerOrders()
  assert(e.Orders[id].ProtectivePosition==pos.Id and e.Orders[id].Priority==state.Priority)
  order(e,r.Id,1,3,nil,{ReduceOnly=true});assert(not a.Positions.BX);e:Audit()
 end)
 test('Risk caps reserve working orders, related accounts and old oversized positions',function()
  local e,a,r=fixture(1,300);assert(e:OrderCapacity(a,'BX',1)==0)
  assert(e:OrderCapacity(a,'BX',-1)>=300,'Legacy position cannot close')
  local close=order(e,a.Id,-1,300,5000,{ReduceOnly=true});order(e,r.Id,1,300,nil,{ReduceOnly=true})
  assert(not a.Positions.BX and not e.Orders[close.Id])
  a.ProfileId='shared';local b=e:AddAccount('other',1e9,10000,.8,true);b.ProfileId='shared'
  local cap=e:OrderCapacity(a,'BX',1);assert(cap==12,'Funding-derived cap differs')
  order(e,a.Id,1,cap,4999);assert(e:OrderCapacity(b,'BX',1)==0)
  assert(not e:Submit(b.Id,{Contract='BX',Direction=1,Quantity=1,Type='Stop',Price=5001}))
  e:CancelAll(a.Id);assert(e:OrderCapacity(b,'BX',1)==cap)
  local limit=Safety.ReserveLimit(e,r,e.Books.BX);assert(limit==125)
  assert(not e:Submit(r.Id,{Contract='BX',Direction=-1,Quantity=limit+1,Type='Limit',Price=5001}))
  order(e,r.Id,-1,limit,5001);assert(not e:Submit(r.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=5001.25}));e:Audit()
 end)
 test('Rolling bounds block a same-step ratchet and do not reset at a clock boundary',function()
  local e,a,r=fixture();local b=e.Books.BX
  e:AddAccount('buyer',10000000,10000,.8,false);e:AddAccount('seller',10000000,10000,.8,false)
  for i=1,24 do order(e,'seller',-1,1,5000+i*.25);assert(order(e,'buyer',1,1).Filled==1)end
  assert(b.Last*b.Spec.Tick==5006)
  assert(not e:Submit('seller',{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=5006.25}))
  e:AdvanceClock(60);assert(not Policy.Allows(e,b,(5006.25)/.25,1),'Clock boundary reset the band')
  assert(e:OrderCapacity(a,'BX',1)<=12);e:Audit()
 end)
 test('Complete populations retain rolling bounds and pending closes across restart',function()
  local c=copy(C);c.ContractOrder={'BX'};local e=E.new(c,177);local p=P.new(e)
  local a=e:AddAccount('restart-player',100000,100,.8,true)
  local saved=CP.Capture(e,p);local r,rp=CP.Restore(saved,c)
  local lo,hi=Safety.Bounds(e,e.Books.BX);local rlo,rhi=Safety.Bounds(r,r.Books.BX);assert(lo==rlo and hi==rhi)
  for _=1,80 do p:Step();rp:Step()end
  assert(e.TradeHash==r.TradeHash and e.NextTrade==r.NextTrade)
  assert(CP.Capture(r,rp).Version==33);e:Audit();r:Audit()
 end)
 test('A saved fallback resumes without duplication, capital changes or migration fills',function()
  local c=copy(C);c.ContractOrder={'BX'};local e=E.new(c,713);local p=P.new(e)
  for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
  local a=e:AddAccount('resume-player',130000,130,.8,true);local counter=e:AddAccount('resume-counter',1e7,1000,.8,false)
  local price=e.Books.BX.Last*c.Contracts.BX.Tick
  order(e,counter.Id,-1,100,price);assert(order(e,a.Id,1,3).Filled==3);e:CancelAll(counter.Id)
  local _,exit=F.Perform(e,a.Id,{Action='Close',Contract='BX'});assert(e.Orders[exit.Id].ExitFallback)
  local saved=CP.Capture(e,p);local re,rp=CP.Restore(CP.Decode(CP.Encode(saved)),c)
  assert(re.NextTrade==e.NextTrade and re.Accounts[a.Id].Balance==a.Balance and re.Orders[exit.Id].Priority==e.Orders[exit.Id].Priority)
  order(re,counter.Id,1,3,nil,{ReduceOnly=true});assert(not re.Accounts[a.Id].Positions.BX and not re.Orders[exit.Id]);re:Audit()
 end)
 test('New-market demand cannot evade the cap with passive orders or stop amendments',function()
  local e,a,r=fixture();local cap=e:OrderCapacity(a,'BX',1)
  local pending=order(e,a.Id,1,cap,4999)
  assert(not e:AmendOrder(a.Id,{OrderId=pending.Id,Contract='BX',ExpectedPrice=4999,ExpectedQuantity=cap,Price=4999.25,Quantity=cap+1}))
  assert(e.Orders[pending.Id].Remaining==cap and e.Orders[pending.Id].Price==4999/.25)
  order(e,r.Id,-1,100,5000);local fill=order(e,r.Id,-1,cap)
  assert(fill.Filled<=cap and a.Positions.BX and a.Positions.BX.Quantity<=cap)
  assert(e:OrderCapacity(a,'BX',1)==0);e:Audit()
 end)
 test('Stale quotes outside the rolling band cannot permanently block executable prices',function()
  local e,a,r=fixture(1,3);local b=e.Books.BX
  -- A legacy low target must keep its minimum price and become queued, not block all new quotes.
  local execution=e.Config.PlayerExecution;e.Config.PlayerExecution=nil
  local legacy=order(e,a.Id,-1,3,4900,{ReduceOnly=true});e.Config.PlayerExecution=execution
  e.ProcessingParticipants=true;e:AdvanceClock(.25);e.ProcessingParticipants=nil
  assert(e.Orders[legacy.Id]and e.Orders[legacy.Id].Queued and #b.Asks==0)
  order(e,r.Id,1,3,5000,{ReduceOnly=true})
  for _=1,3 do e:AdvanceClock(e.Config.PlayerExecution.WindowSeconds);e:ProcessPlayerOrders()end
  assert(not a.Positions.BX and a.History[1].Exit==5000);e:Audit()
 end)
 test('Nearest passive quotes fit both bands; outer layers cannot form a boundary wall',function()
  for _,side in ipairs({1,-1})do
   local e=fixture();local b=e.Books.BX;local lo,hi=Safety.Bounds(e,b)
   local boundary=side==1 and lo or hi
   b.Last=boundary
   assert(Policy.PassivePrice(e,b,side,boundary-side*9,true)==boundary)
   assert(Policy.PassivePrice(e,b,side,boundary-side*14,false)==nil)
   assert(Policy.Allows(e,b,boundary,-side))
   assert(not Policy.Allows(e,b,boundary-side,-side),'Quote fitting widened a band')
   -- An opposing order at the boundary leaves no legal passive quote on this side.
   b[side==1 and 'Asks'or 'Bids']={{Price=boundary,Orders={}}}
   assert(Policy.PassivePrice(e,b,side,boundary,true)==nil)
   b[side==1 and 'Asks'or 'Bids']={{Price=boundary+side*2,Orders={}}}
   local fitted=Policy.PassivePrice(e,b,side,boundary+side*5,true)
   assert(fitted==boundary+side and Policy.Allows(e,b,fitted,-side))
  end
 end)
 test('Passive quote fitting also respects the per-trade collar',function()
  for _,side in ipairs({1,-1})do
   local e=fixture();local b=e.Books.BX;b.Last=b.Last or b.Reference
   e.Config.PlayerExecution.GuardTicks=2
   local boundary=b.Last-side*2*math.max(1,b.Spec.Scale or 1)
   assert(Policy.PassivePrice(e,b,side,b.Last-side*100,true)==boundary)
   assert(Policy.PassivePrice(e,b,side,b.Last-side*100,false)==nil)
   assert(not Policy.Allows(e,b,boundary-side,-side))
  end
 end)
 test('Reserve quotes repair blocked touch prices without extra funds or lost eligible priority',function()
  for _,side in ipairs({1,-1})do
   local e,a,r,p=fixture();local b=e.Books.BX;b.Last=b.Last or b.Reference;local agent=p.Agents[1]
   agent.Limit=200;agent.Size=10;p.Regime={Liquidity=1}
   p:_reserve(agent);local old=agent.Quotes[side..':1'];assert(old)
   local balance=r.Balance;local trades=e.NextTrade;local capital=e.Capital
   -- Move the band around the last trade, leaving the existing touch quote blocked.
   local width=e.Config.MarketSafety.ShortTicks*math.max(1,b.Spec.Scale or 1)
   b.Safety.History={{Time=e.Time,Price=b.Last+side*width}};e.SafetyBounds=nil
   p:_reserve(agent)
   local id=agent.Quotes[side..':1'];local quote=e.Orders[id]
   assert(quote and id~=old and quote.Price==b.Last and not e.Orders[old])
   assert(quote.Remaining<=agent.Size*e.Config.Reserve.SizeVariation[2])
   assert(Policy.Allows(e,b,quote.Price,-side))
   assert(not agent.Quotes[side..':2']or not e.Orders[agent.Quotes[side..':2']])
   p:_reserve(agent);assert(agent.Quotes[side..':1']==id,'Eligible FIFO was reset')
   assert(r.Balance==balance and e.NextTrade==trades and e.Capital==capital)
   assert(e:OrderCapacity(a,'BX',side)<=12);e:Audit()
  end
 end)
 test('Makers repair blocked prices using their existing replenishment delay and risk sizing',function()
  for _,side in ipairs({1,-1})do
   local c=copy(C);c.ContractOrder={'BX'};local e=E.new(c,177);local p=P.new(e)
   local agent;for _,bot in ipairs(p.Agents)do if bot.Kind=='Maker'then agent=bot;break end end;assert(agent)
   for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
   agent.Quotes={};agent.ReplenishAt={}
   p:_maker(agent);local old=agent.Quotes[side..':1'];assert(old)
   local account=e.Accounts[agent.Id];local balance=account.Balance;local b=e.Books.BX
   local width=c.MarketSafety.ShortTicks*math.max(1,b.Spec.Scale or 1)
   b.Safety.History={{Time=e.Time,Price=b.Last+side*width}};e.SafetyBounds=nil
   p:_maker(agent);assert(not e.Orders[old]and not agent.Quotes[side..':1'])
   local ready=agent.ReplenishAt[side..':1'];assert(ready>e.Time)
   e.Time=ready-.001;p:_maker(agent);assert(not agent.Quotes[side..':1'])
   e.Time=ready;p:_maker(agent);local quote=e.Orders[agent.Quotes[side..':1']]
   assert(quote and quote.Price==b.Last and Policy.Allows(e,b,quote.Price,-side))
   assert(account.Balance==balance and quote.Remaining<=agent.Limit);e:Audit()
  end
 end)
 return rows
end
return Tests
