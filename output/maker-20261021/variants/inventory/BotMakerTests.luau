local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local M=require(script.Parent.BotMaker)
local CP=require(script.Parent.WorldCheckpoint)
local T={}
local function copy(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=copy(x)end;return t end
local function equal(a,b,path)
 path=path or 'state';assert(type(a)==type(b),path..' type')
 if type(a)~='table'then assert(a==b,path..' differs');return end
 for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
end
local function fixture()
 local c=copy(C);local e=E.new(c,123);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(123),Agents={},Markets={BX={},BT={},BG={}},Regime={Volatility=1,Liquidity=1,Activity=1}},P)
 local a=p:_agent('BX','Maker',1);a.Size=6;a.Limit=40;local ac=e.Accounts[a.Id];ac.Limit=40
 e:AddAccount('buyer',1e8,100000,1,false);e:AddAccount('seller',1e8,100000,1,false)
 local s=M.Adopt(p,a);s.Soft=.65;s.Hard=.8;s.Resume=.25;s.MaxAge=100;s.MinRest=20;s.Refill=8
 return e,p,a,e.Books.BX,s
end
local function quote(e,b,side,qty,tick)
 local ok,r=e:Submit(side==1 and 'buyer'or 'seller',{Contract=b.Key,Direction=side,Quantity=qty or 100,Type='Limit',Price=(tick or (b.Last or b.Reference)-side)*b.Spec.Tick});assert(ok,tostring(r));return r
end
local function position(e,p,a,b,side,qty)
 e:CancelAll(a.Id);a.Quotes={};a.ReplenishAt={};quote(e,b,-side,qty)
 local ok,r=e:Submit(a.Id,{Contract=b.Key,Direction=side,Quantity=qty,Type='Market'});assert(ok and r.Filled==qty)
 M.Step(p,a);return e.Accounts[a.Id].Positions[b.Key]
end
local function entries(e,a,side)
 local qty=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o and not o.ReduceOnly and(not side or o.Direction==side)then qty+=o.Remaining end end;return qty
end
function T.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Stable heterogeneous profiles use no shared RNG',function()
  local e,p,a,b,s=fixture();local ages,delays={},{}
  for i=2,40 do local agent=p:_agent('BX','Maker',i);local before=p.Random.State;local q=M.Adopt(p,agent);assert(p.Random.State==before);ages[math.floor(q.MaxAge/100)]=true;delays[math.floor(q.Refill*4)]=true end
  local n=0;for _ in pairs(ages)do n+=1 end;assert(n>=4);local n=0;for _ in pairs(delays)do n+=1 end;assert(n>=4);e:Audit()
 end)
 test('Flat makers post finite funded passive quotes without changing price or balances',function()
  local e,p,a,b,s=fixture();local ac=e.Accounts[a.Id];local balance=ac.Balance;M.Step(p,a)
  assert(e.NextTrade==0 and b.Last==nil and ac.Balance==balance and ac.NetCapitalAdjustments==0)
  assert(entries(e,a,1)>0 and entries(e,a,-1)>0 and entries(e,a,1)<=math.floor(M.Capacity(p,a)*s.Hard))
  assert(e:Exposure(ac,'BX',1,0));e:Audit()
 end)
 test('Small long and short inventories retain ordinary two-sided quotes with symmetric skew',function()
  for _,side in ipairs({1,-1})do local e,p,a,b,s=fixture();position(e,p,a,b,side,20)
   s.Anchor=b.Last;local plan=M.Plan(p,a,s);assert((plan.Center-b.Last)*side<0)
   local closing=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];assert(not o.ReduceOnly);if o.Direction==-side then closing+=o.Remaining end end
   assert(closing>0 and entries(e,a,side)<closing);e:Audit()
  end
 end)
 test('Soft inventory pressure withdraws adding quotes while retaining passive exits',function()
  for _,side in ipairs({1,-1})do local e,p,a,b,s=fixture();position(e,p,a,b,side,28)
   assert(entries(e,a,side)==0 and next(e.Accounts[a.Id].OpenOrders));e:Audit()
  end
 end)
 test('Unwind hysteresis clears only below the resume threshold',function()
  local e,p,a,b,s=fixture();position(e,p,a,b,1,34);assert(s.Mode=='Unwind')
  e:CancelAll('buyer');quote(e,b,1,100,math.min(b.Last-1,b.Asks[1].Price-1));assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=20,Type='Market',ReduceOnly=true}));M.Step(p,a)
  assert(s.Mode=='Unwind'and entries(e,a,1)==0)
  assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=6,Type='Market',ReduceOnly=true}));M.Step(p,a)
  assert(s.Mode=='Normal'and s.InventorySince==e.Time);e:Audit()
 end)
 test('Aged inventory unwinds with passive reduce-only orders and cannot reverse',function()
  local e,p,a,b,s=fixture();position(e,p,a,b,1,20);e:AdvanceClock(101);local volume=e.TotalVolume;M.Step(p,a)
  assert(s.Mode=='Unwind'and entries(e,a,1)==0 and e.TotalVolume==volume)
  e:AdvanceClock(6);M.Step(p,a);local closing=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];assert(o.ReduceOnly);closing+=o.Remaining end
  assert(closing>0 and closing<=20)
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=100,Type='Market'}))
  local pos=e.Accounts[a.Id].Positions.BX;assert(not pos or pos.Direction==1);e:Audit()
 end)
 test('Unchanged and partially filled quotes retain FIFO priority',function()
  local e,p,a,b,s=fixture();M.Step(p,a);local id=a.Quotes['-1:1'];local order=e.Orders[id];local priority=order.Priority;local remaining=order.Remaining
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Market'}));M.Step(p,a)
  assert(a.Quotes['-1:1']==id and order.Priority==priority and order.Remaining==remaining-1);e:Audit()
 end)
 test('Full fills and expiry have real nonzero refill delays',function()
  local e,p,a,b,s=fixture();M.Step(p,a);local id=a.Quotes['-1:1'];local qty=e.Orders[id].Remaining
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=qty,Type='Market'}));M.Step(p,a)
  assert(not a.Quotes['-1:1']and a.ReplenishAt['-1:1']>e.Time);local deadline=a.ReplenishAt['-1:1'];M.Step(p,a);assert(a.ReplenishAt['-1:1']==deadline)
  e:AdvanceClock(deadline-e.Time-.25);M.Step(p,a);assert(not a.Quotes['-1:1']);e:Audit()
  local se,sp,sa,sb,ss=fixture();M.Step(sp,sa);local bid=se.Orders[sa.Quotes['1:1']];se:AdvanceClock(bid.Expires-se.Time);M.Step(sp,sa)
  assert(not sa.Quotes['1:1']and sa.ReplenishAt['1:1']>se.Time and se.TotalVolume==0);se:Audit()
 end)
 test('Public price shock fixture withdraws stale quotes without instant replacement or trades',function()
  local e,p,a,b,s=fixture();M.Step(p,a);local old=copy(a.Quotes);local volume=e.TotalVolume
  -- Isolated observed-price shock fixture; the production strategy never writes Last.
  b.Last=b.Reference+20;e:AdvanceClock(.25);M.Step(p,a)
  for slot,id in pairs(old)do if slot:sub(1,2)=='-1'then assert(not e.Orders[id]and not a.Quotes[slot]and a.ReplenishAt[slot]>e.Time)end end
  assert(e.TotalVolume==volume);e:Audit()
 end)
 test('Capacity reductions withdraw oversized working risk before the minimum rest',function()
  local e,p,a,b,s=fixture();M.Step(p,a);e.Accounts[a.Id].Limit=5;a.Limit=5;M.Step(p,a)
  assert(entries(e,a,1)<=4 and entries(e,a,-1)<=4);e:Audit()
  e:AdvanceClock(6);M.Step(p,a);assert(entries(e,a,1)<=4 and entries(e,a,-1)<=4);assert(e:Exposure(e.Accounts[a.Id],'BX',1,0));e:Audit()
 end)
 test('Existing manual reducing orders share inventory budget and survive adoption',function()
  local e,p,a,b,s=fixture();position(e,p,a,b,1,4);e:CancelAll(a.Id);a.Quotes={}
  local ok,r=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=3,Type='Limit',Price=(b.Last+50)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local pos=copy(e.Accounts[a.Id].Positions);local balance=e.Accounts[a.Id].Balance;local volume=e.TotalVolume
  a.Maker=nil;M.Adopt(p,a);assert(e.Orders[r.Id]);equal(pos,e.Accounts[a.Id].Positions);assert(e.Accounts[a.Id].Balance==balance and e.TotalVolume==volume)
  a.Maker.Mode='Unwind';a.Maker.Resume=0;e:AdvanceClock(20);M.Step(p,a);local qty=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do local o=e.Orders[id];if o.ReduceOnly then qty+=o.Remaining end end
  assert(qty<=4 and e.Orders[r.Id]);e:Audit()
 end)
 test('Locked, liquidating, retiring and triggered accounts cannot add exposure',function()
  for _,condition in ipairs({'Locked','Liquidating','Retiring','Triggered'})do local e,p,a,b,s=fixture();position(e,p,a,b,1,4)
   if condition=='Retiring'then a.Retiring=true elseif condition=='Triggered'then e.Accounts[a.Id].Positions.BX.Triggered='Stop loss'else e.Accounts[a.Id][condition]=true end
   local volume=e.TotalVolume;M.Step(p,a);assert(entries(e,a)==0 and volume==e.TotalVolume);e:Audit()
  end
 end)
 test('Zero buying power and an empty book cannot create funding or fills',function()
  local e,p,a,b,s=fixture();e.Accounts[a.Id].Risk=0;local balance=e.Accounts[a.Id].Balance
  M.Step(p,a);assert(not next(e.Accounts[a.Id].OpenOrders)and e.TotalVolume==0 and b.Last==nil and balance==e.Accounts[a.Id].Balance);e:Audit()
 end)
 test('Thin regimes keep limited depth and fill pressure decays on simulation time',function()
  local e,p,a,b,s=fixture();p.Regime.Liquidity=.22;M.Step(p,a);local count=0;for _ in pairs(e.Accounts[a.Id].OpenOrders)do count+=1 end;assert(count==2)
  s.Sides['1'].Pressure=2;local before=s.Sides['1'].Pressure;e:AdvanceClock(30);M.Step(p,a);assert(s.Sides['1'].Pressure<before and s.Sides['1'].Pressure>0);e:Audit()
 end)
 test('V27 migration preserves economic state and refuses policy downgrades',function()
  local old=copy(C);old.BotMaker=nil;local e=E.new(old,7919);local p=P.new(e);for _=1,40 do p:Step()end
  local saved=CP.Capture(e,p);saved.Version=27;local before=copy(saved);local re,rp=CP.Restore(saved,C);equal(saved,before)
  equal(saved.Engine,CP.Capture(re,rp).Engine);equal(saved.Population,CP.Capture(re,rp).Population)
  assert(CP.Version==28 and re.Config.BotWhale.Version==old.BotWhale.Version and re.Config.BotMomentum.Version==old.BotMomentum.Version and re.Config.NewsFrequency==0)
  assert(not pcall(CP.Restore,CP.Capture(re,rp),old));local future=CP.Capture(re,rp);future.Config.BotMaker.Version+=1;assert(not pcall(CP.Restore,future,C));re:Audit()
 end)
 test('Unobserved partial fills, quote cooldowns and unwind state serialize exactly',function()
  for _,mode in ipairs({'Partial','Cooldown','Unwind'})do
   local e=E.new(copy(C),1729);local p=P.new(e);local a
   for _,agent in ipairs(p.Agents)do if agent.Kind=='Maker'and agent.Key=='BX'then a=agent;break end end
   local s=M.Adopt(p,a)
   if mode=='Partial'then
    for _,id in ipairs(e.AccountOrder)do if id~=a.Id then e:CancelAll(id,'BX')end end
    e:AddAccount('counterparty',1e8,100000,1,false)
    local id=assert(a.Quotes['-1:1']);local q=e.Orders[id];assert(q.Remaining>1)
    assert(e:Submit('counterparty',{Contract='BX',Direction=1,Quantity=1,Type='Market'}))
   elseif mode=='Cooldown'then local id=a.Quotes['1:1'];e:Cancel(a.Id,id);M.Step(p,a)
   else
    local ac=e.Accounts[a.Id]
    if not ac.Positions.BX then local ok,r=e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=1,Type='Market'});assert(ok and r.Filled==1)end
    s.PositionId=ac.Positions.BX.Id;s.Mode='Unwind';s.Resume=0;s.InventorySince=e.Time-1000
   end
   local re,rp=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,p))),C)
   for _=1,100 do p:Step();rp:Step()end
   equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
  end
 end)
 return out
end
return T
