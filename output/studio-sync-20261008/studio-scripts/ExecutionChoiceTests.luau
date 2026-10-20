local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Client=require(game.ReplicatedStorage.MarketReign.MarketClient)
local F=require(script.Parent.FundedAccounts)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function fresh()
 local c=clone(C);c.PlayerExecution.SliceContracts=2;c.PlayerExecution.OwnerContracts=8;c.PlayerExecution.MarketContracts=20
 local e=E.new(c,937);e:AddAccount("user",1000000,1000,.8,true);e:AddAccount("maker",1000000,1000,.8,false)
 local price=c.Contracts.BX.Last
 assert(e:Submit("maker",{Contract="BX",Type="Limit",Direction=-1,Quantity=100,Price=price}))
 return e,c,price
end
local function submit(e,mode,kind,price)
 return e:Submit("user",{Contract="BX",Direction=1,Quantity=20,Type=kind or "Market",Price=price,Execution=mode})
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(r)})end
 test("Default market fills immediately within budget, cancels remainder and never resumes",function()
  local e,c=fresh();local ok,r=submit(e);assert(ok and r.Filled==8 and r.Cancelled==12 and r.Remaining==0 and not r.Queued)
  assert(not e.Orders[r.Id]);e:AdvanceClock(c.PlayerExecution.WindowSeconds);e:ProcessPlayerOrders()
  assert(e.Accounts.user.Positions.BX.Quantity==8);e:Audit()
 end)
 test("Explicit slicing continues and cancellation stops later fills",function()
  local e,c=fresh();local ok,r=submit(e,"Sliced");assert(ok and r.Filled==2 and r.Remaining==18 and r.Queued)
  e:ProcessPlayerOrders();assert(e.Accounts.user.Positions.BX.Quantity==4)
  assert(e:Cancel("user",r.Id));e:AdvanceClock(c.PlayerExecution.WindowSeconds);e:ProcessPlayerOrders()
  assert(e.Accounts.user.Positions.BX.Quantity==4);e:Audit()
 end)
 test("Changing modes never resets the shared allowance",function()
  local e=fresh();assert(submit(e,"Immediate"));local ok,r=submit(e,"Sliced")
  assert(ok and r.Filled==0 and r.Queued);assert(e.Accounts.user.Positions.BX.Quantity==8);e:Audit()
 end)
 test("Empty market cancels standard order and retains explicitly sliced order",function()
  local e=fresh();e:CancelAll("maker");local ok,r=submit(e,"Immediate")
  assert(ok and r.Filled==0 and r.Cancelled==20 and not e.Orders[r.Id])
  local yes,s=submit(e,"Sliced");assert(yes and s.Queued and s.Remaining==20);e:Audit()
 end)
 test("Standard marketable limits reject blocked submissions without creating an order",function()
  local e,c,price=fresh();local ok,r=submit(e,"Immediate","Limit",price)
  assert(not ok and r:find("No order placed",1,true)and not next(e.Accounts.user.OpenOrders)and not next(e.Accounts.user.Positions));e:Audit()
  local yes,passive=submit(e,"Immediate","Limit",price-c.Contracts.BX.Tick)
  assert(yes and not passive.Queued and passive.Remaining==20 and #e.Books.BX.Bids==1);e:Audit()
 end)
 test("Sliced limits preserve execution choice when amended",function()
  local e,c,price=fresh();local ok,r=submit(e,"Sliced","Limit",price-c.Contracts.BX.Tick);assert(ok and not r.Queued)
  assert(e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=price-c.Contracts.BX.Tick,ExpectedQuantity=20,Price=price}))
  assert(e.Orders[r.Id].Queued and e.Orders[r.Id].Execution=="Sliced");e:Audit()
 end)
 test("Limit amendment reports partial fills, retained remainders and full fills",function()
  local function amend(e,r,old,price,quantity)
   local ok,result=e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=old,ExpectedQuantity=quantity,Price=price})
   assert(ok and type(result)=="table"and result.Amended);return result,F.Describe(result)
  end
  -- Standard consumes the eligible liquidity and keeps the unfilled remainder on the book.
  local e,c,price=fresh();e:CancelAll("maker")
  assert(e:Submit("maker",{Contract="BX",Direction=-1,Quantity=8,Type="Limit",Price=price}))
  local _,r=submit(e,"Immediate","Limit",price-2*c.Contracts.BX.Tick)
  local result,message=amend(e,r,price-2*c.Contracts.BX.Tick,price,20)
  assert(result.Filled==8 and result.Cancelled==0 and result.Remaining==12 and not result.Queued)
  assert(message:find("Partially filled 8 of 20",1,true)and message:find("12 still working",1,true));e:Audit()
  -- No cross: the order remains working and the message includes the quantity.
  local a,config,p=fresh();local _,passive=submit(a,"Immediate","Limit",p-2*config.Contracts.BX.Tick)
  local idle,text=amend(a,passive,p-2*config.Contracts.BX.Tick,p-config.Contracts.BX.Tick,20)
  assert(idle.Filled==0 and idle.Remaining==20 and text:find("20 still working",1,true));a:Audit()
  -- Full fill: only a genuinely completed fill receives that description.
  config.PlayerExecution.OwnerContracts=100;config.PlayerExecution.MarketContracts=100
  local full,confirmation=amend(a,passive,p-config.Contracts.BX.Tick,p,20)
  assert(full.Filled==20 and full.Cancelled==0 and full.Remaining==0 and confirmation:find("Filled 20 @",1,true));a:Audit()
 end)
 test("Blocked buy and sell amendments preserve order identity, FIFO, protection and quantity",function()
  for _,side in ipairs({1,-1})do
   local e,c,price=fresh();e:CancelAll("maker")
   assert(e:Submit("maker",{Contract="BX",Direction=-side,Quantity=100,Type="Limit",Price=price}))
   local old=price-side*c.Contracts.BX.Tick
   local ok,r=e:Submit("user",{Contract="BX",Direction=side,Quantity=20,Type="Limit",Price=old,Execution="Immediate",StopTicks=10,TargetTicks=20});assert(ok)
   local o=e.Orders[r.Id];local before=clone(o);local revision=e.Accounts.user.Revision;local nextPriority=e.NextPriority
   local accepted,message=e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=old,ExpectedQuantity=20,Price=price})
   assert(not accepted and message:find("original limit order is unchanged",1,true))
   for k,v in pairs(before)do assert(o[k]==v,k)end
   assert(e.Orders[r.Id]==o and e.Accounts.user.Revision==revision and e.NextPriority==nextPriority and not next(e.Accounts.user.Positions))
   local levels=side==1 and e.Books.BX.Bids or e.Books.BX.Asks;assert(levels[1].Orders[1]==o);e:Audit()
  end
 end)
 test("Exhausted budgets and price guards reject moves before any fill or self-trade cancellation",function()
  local e,c,price=fresh();assert(submit(e,"Immediate"))
  local old=price-2*c.Contracts.BX.Tick;local ok,r=submit(e,"Immediate","Limit",old);assert(ok)
  local selfOk,selfOrder=e:Submit("user",{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=price-c.Contracts.BX.Tick,Execution="Immediate"});assert(selfOk)
  assert(not e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=old,ExpectedQuantity=20,Price=price}))
  assert(e.Orders[r.Id].Remaining==20 and e.Orders[r.Id].Price==old/c.Contracts.BX.Tick and e.Accounts.user.Positions.BX.Quantity==8)
  assert(e.Orders[selfOrder.Id]and e.Orders[selfOrder.Id].Remaining==1,"Rejected move cancelled a self-owned quote")
  e.Books.BX.FairReference=e.Books.BX.Reference
  local tooFar=price+(c.PlayerExecution.GuardTicks+1)*c.Contracts.BX.Tick
  assert(not e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=old,ExpectedQuantity=20,Price=tooFar}))
  assert(e.Orders[r.Id].Price==old/c.Contracts.BX.Tick);e:Audit()
 end)
 test("Standard limit remainder stays on book, fills on later orders and survives restore",function()
  for _,side in ipairs({1,-1})do
   local e,c,price=fresh();e:CancelAll("maker")
   assert(e:Submit("maker",{Contract="BX",Direction=-side,Quantity=8,Type="Limit",Price=price}))
   local ok,r=e:Submit("user",{Contract="BX",Direction=side,Quantity=20,Type="Limit",Price=price,Execution="Immediate"})
   assert(ok and r.Filled==8 and r.Remaining==12 and r.Cancelled==0 and not r.Queued);e:Audit()
   local pop=setmetatable({Engine=e,Config=c,Random=P.RNG.new(937),Agents={}},P)
   local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),c)
   local o=restored.Orders[r.Id];assert(o and o.Remaining==12 and not o.Queued and o.Execution=="Immediate")
   local filled,result=restored:Submit("maker",{Contract="BX",Direction=-side,Quantity=12,Type="Market"})
   assert(filled and result.Filled==12 and not restored.Orders[r.Id]);restored:Audit()
  end
 end)
 test("Repeated sliced amendments report new fills without counting previous executions again",function()
  local e,c,price=fresh();local _,r=submit(e,"Sliced","Limit",price)
  assert(r.Filled==2 and r.Remaining==18)
  local ok,result=e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=price,ExpectedQuantity=18,Price=price+c.Contracts.BX.Tick})
  assert(ok and result.Filled==2 and result.Remaining==16 and result.Cancelled==0 and result.Queued)
  assert(F.Describe(result):find("2 filled, 16 remaining",1,true));assert(e.Orders[r.Id].Filled==4);e:Audit()
 end)
 test("Moving a partially filled limit without new matches never reports historical fills as new",function()
  local e,c,price=fresh();local _,r=submit(e,"Sliced","Limit",price)
  local ok,result=e:AmendOrder("user",{Contract="BX",OrderId=r.Id,ExpectedPrice=price,ExpectedQuantity=18,Price=price-c.Contracts.BX.Tick})
  assert(ok and result.Filled==0 and result.Remaining==18 and not result.Queued and result.Average==nil)
  assert(F.Describe(result):find("No new fills · 18 still working",1,true));e:Audit()
 end)
 test("Triggered stops honor standard versus sliced execution",function()
  for _,mode in ipairs({"Immediate","Sliced"})do
   local e,c,price=fresh();local ok,r=submit(e,mode,"Stop",price+c.Contracts.BX.Tick);assert(ok)
   e.Orders[r.Id].Triggered=e.Time;e:ProcessStops()
   assert((e.Orders[r.Id]~=nil)==(mode=="Sliced"));assert(e.Accounts.user.Positions.BX.Quantity==(mode=="Sliced"and 2 or 8));e:Audit()
  end
 end)
 test("Invalid execution mode cannot create orders or fills",function()
  local e=fresh();local before=e.NextOrder
  for _,mode in ipairs({"Unlimited","",true,7,{}})do assert(not submit(e,mode))end
  assert(e.NextOrder==before and not next(e.Accounts.user.OpenOrders));e:Audit()
 end)
 test("Execution choice and existing queued orders survive checkpoint restore",function()
  local e,c,price=fresh();local _,r=submit(e,"Sliced")
  local pop=setmetatable({Engine=e,Config=c,Random=P.RNG.new(937),Agents={}},P)
  local saved=CP.Capture(e,pop);local restored=CP.Restore(saved,c)
  assert(restored.Orders[r.Id].Execution=="Sliced"and restored.Orders[r.Id].Queued);restored:Audit()
  for _,o in ipairs(saved.Engine.Orders)do if o.Id==r.Id then o.Execution=nil end end
  local legacy=CP.Restore(saved,c);assert(legacy.Orders[r.Id].Execution=="Sliced"and legacy.Orders[r.Id].Queued)
 end)
 test("Client forwards selection and defaults to standard",function()
  local s=Client.New(10000,true);s.Ready=true;local sent
  s.Send=function(_,action,request)assert(action=="Place");sent=request;return true end
  assert(s:Place("BX",1,20,"Market"));assert(sent.Execution=="Immediate")
  assert(s:Place("BX",1,20,"Market",nil,nil,nil,"Sliced"));assert(sent.Execution=="Sliced")
  s:Destroy()
 end)
 test("Triggered take profits stay labelled as closing protection through partial fills and restore",function()
  for _,side in ipairs({-1,1})do
   local e,c,price=fresh();e:CancelAll("maker");e:AddAccount("trigger",1000000,1000,.8,false)
   assert(e:Submit("maker",{Contract="BX",Direction=-side,Quantity=3,Type="Limit",Price=price}))
   local ok,entry=e:Submit("user",{Contract="BX",Direction=side,Quantity=3,Type="Market",TargetTicks=4});assert(ok and entry.Filled==3)
   local p=e.Accounts.user.Positions.BX;local target=p.Target
   -- An unrelated trade touches TP but consumes the available counterpart liquidity.
   assert(e:Submit("maker",{Contract="BX",Direction=side,Quantity=1,Type="Limit",Price=target}))
   assert(e:Submit("trigger",{Contract="BX",Direction=-side,Quantity=1,Type="Market"}))
   e:ProcessStops();assert(p.Triggered=="Take profit"and p.ExitOrder)
   local exit=e.Orders[p.ExitOrder];assert(exit.ReduceOnly and exit.Direction==-side and exit.Type=="Limit")
   local function check(engine,quantity)
    local snapshot=engine:Snapshot("user","BX","1m",false);assert(#snapshot.Orders==1)
    local order=snapshot.Orders[1]
    assert(order.Protection=="Target"and order.Closing and order.Quantity==quantity and order.Type==nil)
    assert(order.Kind==(side==-1 and "Take profit · closing short"or "Take profit · closing long"))
    assert(snapshot.Positions.BX.Direction==side and snapshot.Positions.BX.Quantity==quantity)
   end
   check(e,3);e:Audit()
   local pop=setmetatable({Engine=e,Config=c,Random=P.RNG.new(937),Agents={}},P)
   local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),c);check(restored,3)
   local filled,r=restored:Submit("maker",{Contract="BX",Direction=side,Quantity=1,Type="Market"});assert(filled and r.Filled==1)
   check(restored,2)
   local done,result=restored:Submit("maker",{Contract="BX",Direction=side,Quantity=2,Type="Market"});assert(done and result.Filled==2)
   local snapshot=restored:Snapshot("user","BX","1m",false)
   assert(not snapshot.Positions.BX and #snapshot.Orders==0,"Protective exit left or reversed the position");restored:Audit()
  end
 end)
 test("Trillion-dollar settlement does not accumulate balance rounding drift",function()
  local c=clone(C);c.PlayerExecution=nil
  local e=E.new(c,91);local a=e:AddAccount("large",1e12,100000,.8,true);e:AddAccount("counter",1e11,100000,.8,false)
  local price=c.Contracts.BG.Last;local tick=c.Contracts.BG.Tick
  local function fill(side,qty,p)
   assert(e:Submit("counter",{Contract="BG",Direction=-side,Quantity=qty,Type="Limit",Price=p}))
   local ok,r=e:Submit("large",{Contract="BG",Direction=side,Quantity=qty,Type="Market"});assert(ok and r.Filled==qty)
  end
  for _=1,1000 do fill(1,1,price);fill(1,2,price+tick);fill(-1,3,price+tick)end
  assert(math.abs(a.Balance-a.Base-a.Realized)<.001);e:Audit()
 end)
 test("Restore repairs only sub-cent large-account drift and still rejects larger discrepancies",function()
  local e,c=fresh();local a=e.Accounts.user;a.Base=1e12;a.Balance=1e12
  local pop=setmetatable({Engine=e,Config=c,Random=P.RNG.new(937),Agents={}},P)
  local saved=CP.Capture(e,pop)
  for _,account in ipairs(saved.Engine.Accounts)do if account.Id=="user"then account.Balance+=.0011 end end
  local restored=CP.Restore(saved,c);assert(restored.Accounts.user.Balance==1e12);restored:Audit()
  for _,account in ipairs(saved.Engine.Accounts)do if account.Id=="user"then account.Balance+=.1 end end
  assert(not pcall(function()CP.Restore(saved,c)end))
 end)
 return rows
end
return Tests
