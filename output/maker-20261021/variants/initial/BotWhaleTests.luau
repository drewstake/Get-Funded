local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local W=require(script.Parent.BotWhale)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture(side,passive)
 local c=copy(C);c.BotWhale.AggressiveProbability=passive and {0,0}or {1,1};c.BotWhale.SliceSeconds={1,1};c.BotWhale.RefillSeconds={3,3}
 local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}}},P)
 local a=p:_agent('BX','Whale',1);a.Size=40;a.Limit=40;e.Accounts[a.Id].Limit=40
 local b=e.Books.BX;e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=W.Adopt(p,a);s.CooldownUntil=0;s.BuildSeconds=100;s.HoldSeconds=50;s.ReduceSeconds=40;s.TargetFraction=.5;s.Participation=.1;s.PriceTolerance=10
 W.Step(p,a);s.Side=side or 1;s.Target=s.Quantity*s.Side;s.StartSideFills=0
 return e,p,a,b,s
end
local function quote(e,b,side,qty,tick)
 local ok,r=e:Submit(side==1 and 'buyer'or 'seller',{Contract=b.Key,Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or (b.Last or b.Reference)-side)*b.Spec.Tick})
 assert(ok,tostring(r));return r
end
local function advance(e,p,a,seconds)e:AdvanceClock(seconds or 5);W.Step(p,a)end
local function enter(side,passive)
 local e,p,a,b,s=fixture(side,passive);quote(e,b,1);quote(e,b,-1);advance(e,p,a,10);return e,p,a,b,s
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Profiles are deterministic, staggered and consume no shared RNG',function()
  local e,p,a,b,s=fixture();local durations,sides={},{}
  for i=2,37 do local agent=p:_agent('BX','Whale',i);local before=p.Random.State;local st=W.Adopt(p,agent);assert(before==p.Random.State)
   durations[math.floor(st.BuildSeconds/100)]=true;st.CooldownUntil=0;W.Step(p,agent);sides[st.Side]=true
  end
  local n=0;for _ in pairs(durations)do n+=1 end;assert(n>=4 and sides[1]and sides[-1]);e:Audit()
 end)
 test('Buys and sells use genuine funded capped fills; no grants or opposite positions',function()
  for _,side in ipairs({1,-1})do local e,p,a,b,s=enter(side,false);local ac=e.Accounts[a.Id]
   assert(ac.Positions.BX.Direction==side and s.Filled==1 and e.TotalVolume==1)
   assert(ac.Base==a.Budget and ac.NetCapitalAdjustments==0 and not next(ac.OpenOrders));assert(e:Exposure(ac,'BX',side,0));e:Audit()
  end
 end)
 test('Own fills cannot unlock participation and quiet allowance is bounded',function()
  local e,p,a,b,s=enter(1,false);local budget,external,allowed=W.Budget(p,a,s)
  assert(external==0 and allowed==1 and budget==0)
  for _=1,5 do advance(e,p,a,3)end;assert(s.Filled==1)
  advance(e,p,a,10);assert(s.Filled==2);assert(select(2,W.Budget(p,a,s))==0);e:Audit()
 end)
 test('External matched volume unlocks only the configured participation share',function()
  local e,p,a,b,s=enter(1,false)
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=20,Type='Market'}))
  advance(e,p,a,10);local budget,external,allowed=W.Budget(p,a,s)
  assert(external==20 and allowed==3 and s.Filled==3 and budget==0);e:Audit()
 end)
 test('Passive child retains FIFO and cannot reserve duplicate parent quantity',function()
  local e,p,a,b,s=enter(1,true);local id=assert(s.ChildId);local order=e.Orders[id];local priority=order.Priority;local count=e.NextOrder
  for _=1,5 do W.Step(p,a)end
  assert(s.ChildId==id and order.Priority==priority and e.NextOrder==count and s.Filled==0)
  assert(e:Exposure(e.Accounts[a.Id],'BX',1,0));e:Audit()
 end)
 test('Delayed partial and complete passive fills count exactly without order archive',function()
  local e,p,a,b,s=fixture(1,true);s.Participation=1
  quote(e,b,-1);assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=20,Type='Market'}));quote(e,b,1)
  advance(e,p,a,25);local id=assert(s.ChildId);local order=e.Orders[id];assert(order.Remaining>1)
  e:CancelAll('buyer');assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=1,Type='Market'}));W.Step(p,a)
  assert(s.Filled==1 and s.ChildId==id)
  local remaining=order.Remaining;assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=remaining,Type='Market'}));e.OrderArchive={}
  W.Step(p,a);assert(s.Filled==1+remaining and not s.ChildId and s.NextChildAt>e.Time)
  local n=e.NextOrder;W.Step(p,a);assert(e.NextOrder==n);e:Audit()
 end)
 test('Expired children wait before replenishing and do not fabricate fills',function()
  local e,p,a,b,s=enter(1,true);local deadline=e.Orders[s.ChildId].Expires;local volume=e.TotalVolume
  advance(e,p,a,deadline-e.Time);assert(not s.ChildId and s.NextChildAt>e.Time and s.Filled==0 and e.TotalVolume==volume);e:Audit()
 end)
 test('No liquidity means no execution, no price movement and no spent mandate',function()
  local e,p,a,b,s=fixture();local last=b.Last;local base=e.Accounts[a.Id].Balance
  for _=1,5 do advance(e,p,a,10)end
  assert(e.TotalVolume==0 and b.Last==last and s.Filled==0 and e.Accounts[a.Id].Balance==base);e:Audit()
 end)
 test('Arrival tolerance and child slippage cap reject distant liquidity',function()
  local e,p,a,b,s=fixture();quote(e,b,-1,100,b.Reference+15);advance(e,p,a,25);assert(e.TotalVolume==0)
  e:CancelAll('seller');quote(e,b,-1,1,b.Reference+1);quote(e,b,-1,100,b.Reference+15)
  s.Participation=1;advance(e,p,a,40);assert(e.TotalVolume==1 and b.Last==b.Reference+1 and not next(e.Accounts[a.Id].OpenOrders));e:Audit()
 end)
 test('Expired partial mandate holds; it never rushes to complete or reverses',function()
  local e,p,a,b,s=enter(1,false);local qty=e.Accounts[a.Id].Positions.BX.Quantity;local volume=e.TotalVolume
  advance(e,p,a,s.Deadline-e.Time);assert(s.Phase=='Holding'and e.TotalVolume==volume and e.Accounts[a.Id].Positions.BX.Quantity==qty)
  advance(e,p,a,20);assert(s.Phase=='Holding'and e.TotalVolume==volume);e:Audit()
 end)
 test('Time distribution is reduce-only and waits for liquidity without forcing a fill',function()
  local e,p,a,b,s=enter(-1,false);advance(e,p,a,s.Deadline-e.Time);advance(e,p,a,50)
  assert(s.Phase=='Reducing');e:CancelAll('buyer');e:CancelAll('seller');local volume=e.TotalVolume
  advance(e,p,a,20);assert(e.TotalVolume==volume and e.Accounts[a.Id].Positions.BX.Direction==-1)
  quote(e,b,-1);advance(e,p,a,5);assert(not e.Accounts[a.Id].Positions.BX and s.Phase=='Waiting'and s.CooldownUntil>e.Time);e:Audit()
 end)
 test('Stops, external closures and recovery invalidate pending entry mandates',function()
  for _,recovery in ipairs({false,true})do local e,p,a,b,s=enter(1,false)
   assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Market',ReduceOnly=true}))
   if recovery then e.Accounts[a.Id].ParticipationRecoveries=1 end
   local volume=e.TotalVolume;W.Step(p,a);assert(s.Phase=='Waiting'and e.TotalVolume==volume and s.CooldownUntil>e.Time);e:Audit()
  end
 end)
 test('Passive entry filled and closed between decisions cannot be resurrected',function()
  local e,p,a,b,s=enter(1,true);e:CancelAll('buyer');assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=1,Type='Market'}))
  quote(e,b,1);assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Market',ReduceOnly=true}))
  assert(not s.PositionId);local volume=e.TotalVolume;W.Step(p,a)
  assert(s.Phase=='Waiting'and e.TotalVolume==volume and not s.ChildId);e:Audit()
 end)
 test('Locked, liquidating, retiring and triggered accounts withdraw entry children',function()
  for _,condition in ipairs({'Locked','Liquidating','Retiring','Triggered'})do local e,p,a,b,s=enter(1,true)
   if condition=='Retiring'then a.Retiring=true elseif condition=='Triggered'then
    e:CancelAll('buyer');assert(e:Submit('seller',{Contract='BX',Direction=-1,Quantity=1,Type='Market'}));e.Accounts[a.Id].Positions.BX.Triggered='Stop loss'
   else e.Accounts[a.Id][condition]=true end
   local volume=e.TotalVolume;W.Step(p,a);assert(e.TotalVolume==volume and not next(e.Accounts[a.Id].OpenOrders));e:Audit()
  end
 end)
 test('Adoption preserves existing inventory, stops, reduce-only exits and balances',function()
  local e,p,a,b,s=enter(1,false);local ac=e.Accounts[a.Id]
  local ok,x=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Last+20)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local pos=copy(ac.Positions);local balance=ac.Balance;local volume=e.TotalVolume;a.Whale=nil;W.Adopt(p,a)
  equal(pos,ac.Positions);assert(e.Orders[x.Id]and ac.Balance==balance and e.TotalVolume==volume and a.Whale.Phase=='Holding');e:Audit()
 end)
 test('Risk reduction ignores participation budget but cannot reverse or exceed a child cap',function()
  local e,p,a,b,s=enter(1,false);a.Budget=e.Accounts[a.Id].Balance*2;s.Participation=0
  W.Step(p,a);assert(s.Phase=='Reducing'and s.ExitReason=='Risk');advance(e,p,a,5)
  assert(not e.Accounts[a.Id].Positions.BX and s.Phase=='Waiting');e:Audit()
 end)
 test('V26 migration is read-only and downgrade readers fail closed',function()
  local old=copy(C);old.BotWhale=nil;local e=E.new(old,7919);local p=P.new(e);for _=1,40 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=26;local before=copy(saved);local re,rp=CP.Restore(saved,C);equal(saved,before)
  assert(re.NextTrade==e.NextTrade and re.TotalVolume==e.TotalVolume and re.Time==e.Time)
  for id,ac in pairs(e.Accounts)do local new=re.Accounts[id];assert(new.Base==ac.Base and new.Balance==ac.Balance and new.Realized==ac.Realized);equal(new.Positions,ac.Positions)end
  assert(CP.Version==28 and re.Config.BotMomentum.Version==old.BotMomentum.Version and re.Config.NewsFrequency==0)
  assert(not pcall(CP.Restore,CP.Capture(re,rp),old));local future=CP.Capture(re,rp);future.Config.BotWhale.Version+=1;assert(not pcall(CP.Restore,future,C));re:Audit()
 end)
 test('Checkpoint between passive fill and observation preserves exact remaining parent budget',function()
  local e=E.new(copy(C),1729);local p=P.new(e);local a
  for _,agent in ipairs(p.Agents)do if agent.Kind=='Whale'and agent.Key=='BX'then a=agent;break end end
  for _,id in ipairs(e.AccountOrder)do e:CancelAll(id,'BX')end
  e:AddAccount('counterparty',1e8,100000,1,false)
  local s=W.Adopt(p,a);s.CooldownUntil=0;W.Step(p,a);s.Side=1;s.Target=s.Quantity;s.StartSideFills=0
  local tick=e.Books.BX.Reference
  local ok,r=e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=2,Type='Limit',Price=tick*e.Books.BX.Spec.Tick,StopTicks=a.Stop,Expires=e.Time+45});assert(ok)
  s.ChildId=r.Id;s.ChildAt=e.Time;s.ChildPrice=tick
  assert(e:Submit('counterparty',{Contract='BX',Direction=-1,Quantity=1,Type='Market'}));assert(s.Filled==0 and e.Orders[r.Id].Remaining==1)
  local re,rp=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),C);local ra
  for _,agent in ipairs(rp.Agents)do if agent.Id==a.Id then ra=agent;break end end
  W.Step(p,a);W.Step(rp,ra)
  assert(s.Filled==1 and ra.Whale.Filled==1 and s.ChildId==r.Id);equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
 end)
 test('Active passive child, holding, reduction and cooldown serialize and replay exactly',function()
  for _,name in ipairs({'Building','Holding','Reducing','Waiting'})do
   local e=E.new(copy(C),1729);local p=P.new(e);local a
   for _,agent in ipairs(p.Agents)do if agent.Kind=='Whale'and agent.Key=='BX'then a=agent;break end end
   local s=W.Adopt(p,a);s.CooldownUntil=0;W.Step(p,a)
   local ac=e.Accounts[a.Id];local bid,ask=e:PublicPrices('BX')
   if name=='Building'then
    local ok,r=e:Submit(a.Id,{Contract='BX',Direction=s.Side,Quantity=1,Type='Limit',Price=s.Side==1 and bid or ask,StopTicks=a.Stop,Expires=e.Time+45});assert(ok)
    s.ChildId=r.Id;s.ChildAt=e.Time;s.ChildPrice=(s.Side==1 and bid or ask)/e.Books.BX.Spec.Tick
   elseif name~='Waiting'then
    local ok,r=e:Submit(a.Id,{Contract='BX',Direction=s.Side,Quantity=1,Type='Market',StopTicks=a.Stop});assert(ok and r.Filled==1)
    s.PositionId=ac.Positions.BX.Id;s.Phase='Holding';s.HoldUntil=e.Time+(name=='Reducing'and -1 or 100);W.Step(p,a)
   else s.Phase='Waiting';s.CooldownUntil=e.Time+100 end
   local re,rp=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),C)
   for _=1,100 do p:Step();rp:Step()end
   equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
  end
 end)
 return out
end
return T
