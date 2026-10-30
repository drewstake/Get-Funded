local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local R=require(script.Parent.BotInventory)
local V=require(script.Parent.BotValue)
local L=require(script.Parent.BotLiquidity)
local CP=require(script.Parent.WorldCheckpoint)
local T=require(script.Parent.TestLiquidity)
local Tests={}
local function copy(x)if type(x)~='table'then return x end;local r={}for k,v in pairs(x)do r[k]=copy(v)end;return r end
local function same(a,b)
 assert(type(a)==type(b),'Type changed');if type(a)~='table'then assert(a==b,'Value changed');return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,'Extra field')end
end
local function fixture(kind)
 local c=copy(C);local e=E.new(c,709);local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(709),Agents={},Markets={},
  Regime={Volatility=1,Liquidity=1,Activity=1}},P)
 for _,key in ipairs(c.ContractOrder)do p.Markets[key]={}end
 local a=p:_agent('BX',kind,1);a.Size=3;a.EntryBuffer=2;a.Belief=e.Books.BX.Reference
 e:AddAccount('buyer',1e7,1000,1,false);e:AddAccount('seller',1e7,1000,1,false)
 return e,p,a,e.Books.BX,e.Accounts[a.Id]
end
local function quote(e,b,side,tick,qty)
 local ok,r=e:Submit(side==1 and 'buyer'or 'seller',{Contract='BX',Direction=side,Quantity=qty or 10,Type='Limit',Price=tick*b.Spec.Tick})
 assert(ok,tostring(r));return r
end
local function open(e,a,b,side,qty)
 T.FillAt(e,a.Id,{Contract='BX',Direction=side,Quantity=qty,Type='Market',StopTicks=24},b.Reference*b.Spec.Tick)
 return e.Accounts[a.Id].Positions.BX
end
local function history(e,p,b,side,turn)
 e.Time=60;b.Last=b.Reference
 p.Markets.BX.SignalHistory={{Time=0,Price=b.Last+side*10},{Time=30,Price=b.Last+side*8},
  {Time=57,Price=b.Last+(turn and -side*2 or side*2)},{Time=60,Price=b.Last}}
end
function Tests.Run()
 local out={};local function test(name,fn)local ok,r=pcall(fn);table.insert(out,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(r)})end
 test('Liquidity exits retain price and FIFO on favorable moves in both directions',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,ac=fixture('Liquidity');open(e,a,b,side,2)
   quote(e,b,1,b.Reference-2);quote(e,b,-1,b.Reference+2);L.Step(p,a)
   local id=assert(a.LiquidityQuotes[tostring(-side)]);local o=assert(e.Orders[id]);local price,priority=o.Price,o.Priority
   e:CancelAll('buyer');e:CancelAll('seller')
   quote(e,b,1,b.Reference+side*2-1);quote(e,b,-1,b.Reference+side*2+1)
   e:AdvanceClock(7);L.Step(p,a)
   assert(e.Orders[id]==o and o.Price==price and o.Priority==priority and not o.Expires,'Favorable price chased the exit away')
   e:Audit()
  end
 end)
 test('Partial liquidity exits preserve realized P&L, residual quantity and queue priority',function()
  local e,p,a,b,ac=fixture('Liquidity');open(e,a,b,1,2);L.Step(p,a)
  local id=assert(a.LiquidityQuotes['-1']);local o=e.Orders[id];local priority=o.Priority
  local yes,r=e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=o.Price*b.Spec.Tick});assert(yes and r.Filled==1)
  local realized=ac.Realized;L.Step(p,a)
  assert(ac.Positions.BX.Quantity==1 and e.Orders[id]==o and o.Priority==priority and o.Remaining==1 and ac.Realized==realized)
  assert(e:Submit('buyer',{Contract='BX',Direction=1,Quantity=1,Type='Limit',Price=o.Price*b.Spec.Tick}))
  assert(not ac.Positions.BX and not e.Orders[id]and ac.Realized>realized);e:Audit()
 end)
 test('Timed liquidity exits wait for finite counterpart depth and never reverse',function()
  local e,p,a,b,ac=fixture('Liquidity');open(e,a,b,1,2);L.Step(p,a)
  e:AdvanceClock(C.BotLiquidity.MaxHoldSeconds+1);local volume=e.TotalVolume;L.Step(p,a)
  assert(ac.Positions.BX.Quantity==2 and e.TotalVolume==volume,'Empty book fabricated a fill')
  quote(e,b,1,b.Reference-1,1);L.Step(p,a)
  assert(ac.Positions.BX.Quantity==1,'Partial finite exit not respected')
  quote(e,b,1,b.Reference-1,1);L.Step(p,a)
  assert(not ac.Positions.BX);e:Audit()
 end)
 test('Liquidity withdraws only the side facing a continuing adverse public move',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,ac=fixture('Liquidity');quote(e,b,1,b.Reference-2);quote(e,b,-1,b.Reference+2)
   L.Step(p,a);local adverse=assert(a.LiquidityQuotes[tostring(side)])
   history(e,p,b,side,false);L.Step(p,a)
   assert(not e.Orders[adverse]);assert(e.Orders[a.LiquidityQuotes[tostring(-side)]]);e:Audit()
  end
 end)
 test('Liquidity spreads account for a volatile public window without inventing fills',function()
  local e,p,a,b,ac=fixture('Liquidity');quote(e,b,1,b.Reference-2);quote(e,b,-1,b.Reference+2)
  e.Time=60;b.Last=b.Reference
  p.Markets.BX.SignalHistory={{Time=30,Price=b.Last},{Time=45,Price=b.Last+10},{Time=57,Price=b.Last-10},{Time=60,Price=b.Last}}
  local volume=e.TotalVolume;local base=ac.Base;L.Step(p,a)
  local bid=e.Orders[assert(a.LiquidityQuotes['1'])];local ask=e.Orders[assert(a.LiquidityQuotes['-1'])]
  assert(bid.Price<=b.Last-10 and ask.Price>=b.Last+10,'Fast tape still received narrow entry quotes')
  assert(e.TotalVolume==volume and ac.Base==base);e:Audit()
 end)
 test('Value refuses continuing falls/rises and caps entry cost after a confirmed turn',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,ac=fixture('Value');quote(e,b,1,b.Reference-1);quote(e,b,-1,b.Reference+1)
   a.Belief=b.Reference+side*12;a.Aggression=1
   history(e,p,b,side,false);V.Step(p,a);assert(not next(ac.OpenOrders)and not ac.Positions.BX)
   history(e,p,b,side,true)
   local submit=e.Submit;local requests={};e.Submit=function(self,id,r,...)
    if id==a.Id then table.insert(requests,copy(r))end;return submit(self,id,r,...)
   end
   V.Step(p,a);assert(#requests==1)
   local r=requests[1];assert(r.Type=='Limit'and r.Direction==side and r.StopTicks and not r.ReduceOnly)
   assert((a.Belief-r.Price/b.Spec.Tick)*side>=a.EntryBuffer,'Entry paid beyond valuation')
   assert((r.Price/b.Spec.Tick-b.Reference)*side<=2,'Entry has uncapped slippage')
   assert(ac.Positions.BX and ac.Positions.BX.Quantity<=a.Size);e:Audit()
  end
 end)
 test('Value exits existing inventory without warmup or a new entry signal',function()
  local e,p,a,b,ac=fixture('Value');local pos=open(e,a,b,1,2);a.Belief=b.Reference+4
  V.Step(p,a);local id=next(ac.OpenOrders);assert(id and e.Orders[id].ReduceOnly)
  local price,priority=e.Orders[id].Price,e.Orders[id].Priority;a.Belief+=20;V.Step(p,a)
  assert(e.Orders[id].Price==price and e.Orders[id].Priority==priority and pos.Quantity==2);e:Audit()
 end)
 test('Risk capacity includes pending entry contracts and shrinks without new money',function()
  local e,p,a,b,ac=fixture('Maker');R.Manage(p,a);local ticks=R.StopTicks(p,a)
  local cap=R.Capacity(p,a,ticks);assert(cap>0 and cap<a.Limit)
  local cash,base=ac.Balance,ac.Base
  assert(e:Submit(a.Id,{Contract='BX',Direction=1,Quantity=cap,Type='Limit',Price=(b.Reference-4)*b.Spec.Tick}))
  assert(R.Fit(p,a,1,10,cap)==0)
  a.InventoryRisk.LossStreak=3;R.Manage(p,a)
  local pending=0;for id in pairs(ac.OpenOrders)do pending+=e.Orders[id].Remaining end
  assert(pending<=R.Capacity(p,a,ticks)and ac.Balance==cash and ac.Base==base);e:Audit()
 end)
 test('Maker inventory exits are reduce-only and cannot be chased farther away',function()
  local e,p,a,b,ac=fixture('Maker');open(e,a,b,1,3);p:_maker(a)
  local id=assert(a.Quotes['-1:1']);local old=e.Orders[id];assert(old.ReduceOnly)
  local price=old.Price;e:AdvanceClock(C.MakerMinRestSeconds+1);b.Last=b.Reference+1;p:_maker(a)
  local nextOrder=e.Orders[a.Quotes['-1:1']];assert(nextOrder and nextOrder.Price<=price and nextOrder.ReduceOnly)
  e:Audit()
 end)
 test('Deep entry lanes do not strand a maker inventory exit',function()
  local e,p,_,b=fixture('Maker');local a=p:_agent('BX','Maker',10);a.Size=3
  open(e,a,b,1,3);b.Last=b.Reference-10;p:_maker(a)
  local exit=e.Orders[assert(a.Quotes['-1:1'])]
  assert(exit.ReduceOnly and exit.Price<=b.Last+3,'Exit inherited the distant entry lane');e:Audit()
 end)
 test('Position stops and manual removal survive risk adoption; legacy stops never widen',function()
  local e,p,a,b,ac=fixture('Maker');local pos=open(e,a,b,1,2)
  local stop=pos.Stop;R.Manage(p,a);assert(pos.Stop==stop)
  pos.Stop=nil;pos.ManualStop=true;a.InventoryRisk=nil;R.Manage(p,a);assert(not pos.Stop)
  pos.ManualStop=nil;R.Manage(p,a);assert(pos.Stop);e:Audit()
 end)
 test('Timed inventory reduction supersedes a patient partial target without over-closing',function()
  local e,p,a,b,ac=fixture('Value');local pos=open(e,a,b,1,2);R.Manage(p,a)
  pos.Target=(b.Reference+20)*b.Spec.Tick;pos.Triggered='Take profit'
  table.insert(e.PendingStops,{Owner=a.Id,Contract='BX',Position=pos.Id});e:ProcessStops();local id=assert(pos.ExitOrder)
  e:AdvanceClock(C.BotInventory.Kinds.Value.MaxHoldSeconds+1);local realized=ac.Realized;R.Manage(p,a)
  assert(not e.Orders[id]and not pos.Target and not pos.ExitOrder and ac.Realized==realized and pos.Quantity==2)
  quote(e,b,1,b.Reference-1,1);R.Manage(p,a);assert(pos.Quantity==1)
  quote(e,b,1,b.Reference-1,1);R.Manage(p,a);assert(not ac.Positions.BX);e:Audit()
 end)
 test('A stop-out between decisions causes bounded cooldown and smaller subsequent risk',function()
  local e,p,a,b,ac=fixture('Maker');R.Manage(p,a);local cap=R.Capacity(p,a,R.StopTicks(p,a))
  open(e,a,b,1,1);quote(e,b,1,b.Reference-2,1)
  assert(e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Market',ReduceOnly=true}))
  assert(R.Manage(p,a)and a.InventoryRisk.LossStreak==1)
  assert(R.Capacity(p,a,R.StopTicks(p,a))<cap);local cash=ac.Balance
  p:_maker(a);assert(not next(ac.OpenOrders)and ac.Balance==cash)
  e.Time=a.InventoryRisk.ReadyAt;p:_maker(a);assert(next(ac.OpenOrders),'Loss cooldown permanently disabled the maker');e:Audit()
 end)
 test('Loss backoff retains an affordable minimum lot but never bypasses risk capacity',function()
  local e,p,a,b,ac=fixture('Value');a.Limit=4;ac.Limit=4;R.Manage(p,a)
  local ticks=R.StopTicks(p,a);assert(R.Capacity(p,a,ticks)==1)
  a.InventoryRisk.LossStreak=C.BotInventory.MaxLossStreak
  assert(R.Capacity(p,a,ticks)==1,'Affordable minimum lot became permanently inactive')
  ac.Risk=0;assert(R.Capacity(p,a,ticks)==0,'Minimum lot bypassed the real margin budget');e:Audit()
 end)
 test('Saved policy upgrade changes no economics and retains cooldowns across exact replay',function()
  local old=copy(C);old.BotInventory=nil;old.BotValue=nil;old.BotLiquidity.Version=2;old.BotLiquidity.ExitPolicy=nil
  local e=E.new(old,765);local p=P.new(e);for _=1,160 do p:Step()end
  local saved=CP.Capture(e,p);local untouched=copy(saved);local re,rp=CP.Restore(saved,C)
  same(saved,untouched);same(saved.Engine,CP.Capture(re,rp).Engine);same(saved.Population,CP.Capture(re,rp).Population)
  for _=1,240 do rp:Step()end
  local cooled
  for _,a in ipairs(rp.Agents)do if a.Kind=='Maker'and not re.Accounts[a.Id].Positions[a.Key]then
   R.Manage(rp,a);a.InventoryRisk.ReadyAt=re.Time+300;a.InventoryRisk.LossStreak=2;cooled=a.Id;break
  end end
  assert(cooled,'Fixture needs a flat maker for persisted cooldown')
  local snapshot=CP.Capture(re,rp);local rr,pr=CP.Restore(CP.Decode(CP.Encode(snapshot)),C);same(snapshot,CP.Capture(rr,pr))
  for _=1,240 do rp:Step();pr:Step()end
  same(CP.Capture(re,rp),CP.Capture(rr,pr));re:Audit();rr:Audit()
  local downgrade=copy(C);downgrade.BotInventory=nil;assert(not pcall(CP.Restore,snapshot,downgrade))
  downgrade=copy(C);downgrade.BotValue=nil;assert(not pcall(CP.Restore,snapshot,downgrade))
 end)
 return out
end
return Tests
