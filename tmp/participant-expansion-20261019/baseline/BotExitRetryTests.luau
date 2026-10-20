local Engine=require("./MarketEngine")
local Participants=require("./Participants")
local Checkpoint=require("./WorldCheckpoint")
local Scheduler=require("./SimulationScheduler")
local Config=require("./MarketConfig")
local Tests={}
local function copy(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=copy(x)end return r end
function Tests.Fixture(count)
 -- Legacy collar fixtures retain their explicit reference; V22 public reference is covered by OrderFlowMarketTests.
 local c=copy(Config);c.OrderFlowMarket=nil;c.BotPopulation=nil;c.Contracts.BX.Last=5230.25
 local e=Engine.new(c,73015);local b=e.Books.BX;b.FairReference=5230.25/b.Spec.Tick
 e:AddAccount("player",20000000,20000,.8,true)
 assert(e:Submit("player",{Contract="BX",Direction=1,Quantity=13000,Type="Limit",Price=5230.25}))
 for i=1,count do
  local id="short:"..i;e:AddAccount(id,100000,100,.8,false)
  local ok,result=e:Submit(id,{Contract="BX",Direction=-1,Quantity=10,Type="Market"});assert(ok and result.Filled==10)
  local p=e.Accounts[id].Positions.BX;p.Triggered="Stop loss"
 end
 for _,price in ipairs({5282.5,5284.75})do assert(e:Submit("player",{Contract="BX",Direction=-1,Quantity=1300,Type="Limit",Price=price}))end
 b.FairReference=5202.25/b.Spec.Tick
 return e,c
end
function Tests.Benchmark(steps)
 local e=Tests.Fixture(55);local first=e.NextOrder;local prunes=0;local old=e._pruneBook
 e._pruneBook=function(self,book)prunes+=1;return old(self,book)end
 local start=os.clock()
 for _=1,steps or 256 do e:AdvanceClock(e.Config.StepSeconds)end
 return {Steps=steps or 256,Milliseconds=(os.clock()-start)*1000,NewOrders=e.NextOrder-first,BookScans=prunes,ContractsStillHeld=e.Accounts.player.Positions.BX.Quantity}
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("55 blocked exits behind a 13000-contract bid create no repeated orders or full-book scans",function()
  local r=Tests.Benchmark(256);assert(r.NewOrders==0 and r.BookScans==0);assert(r.ContractsStillHeld==550)
 end)
 test("New executable quote wakes a blocked exit and fills only available contracts",function()
  local e=Tests.Fixture(1);e:AdvanceClock(.25)
  local p=e.Accounts['short:1'].Positions.BX;assert(p.BotExitRetry)
  for id in pairs(e.Accounts.player.OpenOrders)do local o=e.Orders[id];if o.Direction==1 then e:Cancel('player',id)end end
  e:AddAccount('new-seller',100000,100,.8,false)
  -- New liquidity must be inside the same guard for bots and players.
  assert(e:Submit('new-seller',{Contract='BX',Direction=-1,Quantity=3,Type='Limit',Price=5203}))
  e:AdvanceClock(.25);assert(p.Quantity==7 and #e.Accounts['short:1'].History==1)
  local trade=e.Trades[#e.Trades];assert(trade.Price==5203 and trade.Quantity==3)
  e:AdvanceClock(.25);assert(p.Quantity==7);e:Audit()
 end)
 test("Fair-value change wakes eligible player liquidity before retry deadline",function()
  local e=Tests.Fixture(1);e:AdvanceClock(.25)
  e.Books.BX.FairReference=5280/e.Books.BX.Spec.Tick
  e:AdvanceClock(.25);assert(not e.Accounts['short:1'].Positions.BX)
  assert(e.Trades[#e.Trades].Price==5282.5);e:Audit()
 end)
 test("Blocked retry state survives checkpoint round trip and resumes identically",function()
  local e,c=Tests.Fixture(3);e:AdvanceClock(.25)
  local population=setmetatable({Engine=e,Config=c,Random=Participants.RNG.new(73015),Agents={}},Participants)
  local snap=Checkpoint.Capture(e,population);local restored=Checkpoint.Restore(snap,c)
  assert(restored.Books.BX.ExitLiquidityRevision==e.Books.BX.ExitLiquidityRevision)
  for _=1,20 do e:AdvanceClock(.25);restored:AdvanceClock(.25)end
  assert(e.NextOrder==restored.NextOrder and e.TradeHash==restored.TradeHash)
  e:Audit();restored:Audit()
 end)
 test("Bot risk repair does not submit a second exit while a stop owns the position",function()
  local e,c=Tests.Fixture(1);local a=e.Accounts['short:1'];a.Limit=1
  local p=setmetatable({Engine=e,Config=c},Participants);local n=e.NextOrder
  assert(p:_repairRisk({Id='short:1'}));assert(e.NextOrder==n)
 end)
 test("Timed scalper exits reuse retry controls while the only ask is blocked",function()
  local e,c=Tests.Fixture(1);local account=e.Accounts['short:1'];local position=account.Positions.BX;position.Triggered=nil
  local population=setmetatable({Engine=e,Config=c},Participants)
  local agent={Id=account.Id,Key='BX',PositionId=position.Id,OpenedAt=-100,MaxHold=1}
  local n=e.NextOrder
  for _=1,20 do population:_scalper(agent);e:AdvanceClock(.25)end
  assert(e.NextOrder==n and position.Quantity==10)
  e.Books.BX.FairReference=5280/.25;population:_scalper(agent)
  assert(not account.Positions.BX);e:Audit()
 end)
 test("Bot take-profit limits still rest without opposing liquidity",function()
  local e=Tests.Fixture(1);local p=e.Accounts['short:1'].Positions.BX
  p.Triggered='Take profit';p.Target=5220
  e:AdvanceClock(.25);assert(p.ExitOrder and e.Orders[p.ExitOrder].Type=='Limit')
  assert(e.Orders[p.ExitOrder].Price*e.Books.BX.Spec.Tick==5220);e:Audit()
 end)
 test("Guard-blocked bot target retains one queued order and recovers without reversing",function()
  local e=Tests.Fixture(1);local p=e.Accounts['short:1'].Positions.BX
  p.Triggered='Take profit';p.Target=5290
  e:AdvanceClock(.25);local id=p.ExitOrder;assert(id and e.Orders[id].Queued)
  local n=e.NextOrder
  for _=1,20 do e:AdvanceClock(.25);e:ProcessPlayerOrders()end
  assert(e.NextOrder==n and e.Orders[id].Remaining==10)
  e.Books.BX.FairReference=5280/e.Books.BX.Spec.Tick;e:AdvanceClock(.25);e:ProcessPlayerOrders()
  assert(not e.Accounts['short:1'].Positions.BX and not e.Orders[id]);e:Audit()
 end)
 test("Time budget yields after atomic steps and carries every unprocessed step",function()
  local time=0;local completed=0;local c={StepSeconds=.25,MaxCatchupSteps=32,SimulationFrameBudgetMs=8}
  local remaining,steps,limited=Scheduler.Advance(8,c,function()completed+=1;time+=.003 end,function()return time end)
  assert(steps==3 and completed==3 and remaining==7.25 and limited)
  while remaining>=.25 do remaining=Scheduler.Advance(remaining,c,function()completed+=1;time+=.003 end,function()return time end)end
  assert(completed==32 and remaining==0)
 end)
 test("One slow atomic step cannot trigger a 32-step catch-up batch",function()
  local time=0;local c={StepSeconds=.25,MaxCatchupSteps=32,SimulationFrameBudgetMs=8}
  local remaining,steps,limited=Scheduler.Advance(8,c,function()time+=.65 end,function()return time end)
  assert(remaining==7.75 and steps==1 and limited)
 end)
 test("Unavailable exchange preserves backlog and never reports a completed step",function()
  local remaining,steps=Scheduler.Advance(.5,{StepSeconds=.25,MaxCatchupSteps=32},function()return false end,function()return 0 end)
  assert(remaining==.5 and steps==0)
 end)
 test("Partial tick and maximum catch-up limits remain intact",function()
  local c={StepSeconds=.25,MaxCatchupSteps=2,SimulationFrameBudgetMs=8};local calls=0
  local remaining,steps=Scheduler.Advance(.24,c,function()calls+=1 end,function()return 0 end)
  assert(calls==0 and steps==0 and remaining==.24)
  remaining,steps=Scheduler.Advance(.8,c,function()calls+=1 end,function()return 0 end)
  assert(steps==2 and calls==2 and math.abs(remaining-.3)<1e-9)
 end)
 return rows
end
return Tests
