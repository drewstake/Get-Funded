-- Finite counterparties, real partial executions, and detached saved-state replay.
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Health=require(script.Parent.BotParticipation)
local Prices=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Tests={}
local function clone(v)if type(v)~='table'then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function order(e,id,side,qty,price,extra)
 local r={Contract='BX',Direction=side,Quantity=qty,Type=price and 'Limit'or 'Market',Price=price}
 for k,v in pairs(extra or {})do r[k]=v end
 local ok,result=e:Submit(id,r);assert(ok,tostring(result));return result
end
local function fixture(player,side)
 local c=clone(Config);c.BotPopulation=nil;c.OrderFlowMarket=nil
 local e=E.new(c,731);local a=e:AddAccount('subject',1000000,1000,.8,player)
 e:AddAccount('maker',1e9,10000,.9,false);e:AddAccount('taker',1e9,10000,.9,false)
 order(e,'maker',-side,5,5825);assert(order(e,a.Id,side,5,nil,{StopTicks=8,TargetTicks=4}).Filled==5)
 local pop=setmetatable({Engine=e,Config=c,Random=P.RNG.new(731),Agents={}},P)
 return e,a,a.Positions.BX,pop
end
local function partial(e,a,p)
 local target=p.Target
 if not a.Player then
  order(e,'maker',-p.Direction,1,target);order(e,'taker',p.Direction,1);e:ProcessStops()
 end
 order(e,'maker',p.Direction,2,target);e:ProcessStops()
 assert(p.Quantity==3 and p.Triggered=='Take profit','Fixture must execute exactly two TP contracts')
end
local function restored(e,pop)
 local re,rp=CP.Restore(CP.Decode(CP.EncodeWorld(e,pop)),e.Config)
 return re,re.Accounts.subject,re.Accounts.subject.Positions.BX,rp
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,result=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and 'Passed'or tostring(result)})end
 for _,side in ipairs({-1,1})do for _,save in ipairs({false,true})do
  local label=side..' / restored '..tostring(save)
  test(label..': move residual SL then TP and fully execute the new target',function()
   local e,a,p,pop=fixture(true,side);partial(e,a,p)
   if save then e,a,p,pop=restored(e,pop)end
   local realized,entry,filled,history=a.Realized,p.Entry,p.TargetFilled,clone(a.History)
   local old=e.Orders[p.TargetOrder];local priority=old.Priority;local stop=p.Stop
   local snap=e:Snapshot(a.Id,'BX','1m',true)
   if Prices.CanEdit then assert(Prices.CanEdit(snap.Positions.BX),'Client drag eligibility rejects a partial target')end
   assert(e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Stop',Price=stop+side*.25,ExpectedPrice=stop,ExpectedQuantity=3}))
   assert(e.Orders[old.Id]==old and old.Priority==priority,'SL move replaced TP priority')
   local target=p.Target+side*.5
   assert(e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Target',Price=target,ExpectedPrice=p.Target,ExpectedQuantity=3}))
   local replacement=e.Orders[p.TargetOrder]
   assert(not e.Orders[old.Id]and replacement and replacement.Remaining==3 and replacement.Priority>priority)
   assert(p.Entry==entry and p.TargetFilled==filled and a.Realized==realized and #a.History==#history)
   for i,row in ipairs(history)do assert(row.Pnl==a.History[i].Pnl and row.TradeId==a.History[i].TradeId and row.Quantity==a.History[i].Quantity)end
   assert(not e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Stop',Price=p.Stop+side*.25,ExpectedPrice=p.Stop,ExpectedQuantity=5}))
   order(e,'maker',side,3,target);e:ProcessStops()
   assert(not a.Positions.BX and not next(a.OpenOrders),'Target overclosed or left an orphan exit')
   assert(math.abs(a.Realized-realized-(target-entry)*side*3*e.Books.BX.Spec.Multiplier)<.0001)
   assert(not e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Stop',Price=stop,ExpectedPrice=stop}))
   e:Audit()
  end)
  test(label..': moved stop executes residual after a partial target without reversing',function()
   local e,a,p,pop=fixture(true,side);partial(e,a,p)
   if save then e,a,p,pop=restored(e,pop)end
   local realized=a.Realized;local stop=p.Stop+side*.25;local entry=p.Entry;local tp=p.TargetOrder
   assert(e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Stop',Price=stop,ExpectedPrice=p.Stop,ExpectedQuantity=3}))
   order(e,'maker',side,4,stop);order(e,'taker',-side,1);e:ProcessStops();e:ProcessPlayerOrders()
   assert(not a.Positions.BX and not e.Orders[tp]and not next(a.OpenOrders))
   assert(a.History[1].Reason=='Stop loss'and a.History[1].Quantity==3)
   assert(math.abs(a.Realized-realized-(stop-entry)*side*3*e.Books.BX.Spec.Multiplier)<.0001);e:Audit()
  end)
  test(label..': bot partial target keeps stop and urgent exit replaces the resting limit',function()
   local e,a,p,pop=fixture(false,side);local stop=p.Stop;partial(e,a,p)
   assert(p.Stop==stop,'Bot TP disarmed the stop')
   if save then e,a,p,pop=restored(e,pop)end
   local tp=p.ExitOrder;assert(tp and e.Orders[tp]);local realized=a.Realized
   order(e,'maker',side,2,stop);order(e,'taker',-side,1);e:ProcessStops()
   assert(p.Triggered=='Stop loss'and p.Quantity==2 and not e.Orders[tp],'Profit target blocked urgent stop')
   assert(not Prices.CanEdit(p,a));assert(a.Realized~=realized)
   order(e,'maker',side,2,stop);e:AdvanceClock(.25)
   assert(not a.Positions.BX and not next(a.OpenOrders));e:Audit()
  end)
 end end
 test('Partial target cancellations and genuine liquidation restrictions',function()
  local e,a,p=fixture(true,1);partial(e,a,p);local id=p.TargetOrder
  a.Liquidating=true;assert(not Prices.CanEdit(e:Snapshot(a.Id,'BX','1m',true).Positions.BX))
  assert(not e:AmendProtection(a.Id,{Contract='BX',OrderId=p.Id,Protection='Stop',Price=p.Stop-.25,ExpectedPrice=p.Stop}))
  assert(not e:CancelProtection(a.Id,p.Id,'Target'));a.Liquidating=nil
  assert(e:CancelProtection(a.Id,p.Id,'Target'));assert(not p.Triggered and not p.ExitOrder and not e.Orders[id]and p.Stop and p.Quantity==3)
  for _,reason in ipairs({'Stop loss','Player close','Account depleted','Margin liquidation','Account reset'})do
   p.Triggered=reason;assert(not Prices.CanEdit(p,a));assert(not e:CancelProtection(a.Id,p.Id,'Stop'))
  end
 end)
 test('Legacy target cannot indefinitely block recovery; missing exit reference retries',function()
  for _,missing in ipairs({false,true})do
   local e,a,p,pop=fixture(false,1);partial(e,a,p);local old=p.ExitOrder
   p.Stop=nil -- Old installed TP behavior erased this information.
   e,a,p,pop=restored(e,pop);a=e.Accounts.subject;p=a.Positions.BX
   if missing then e:Cancel(a.Id,p.ExitOrder);p.Triggered=nil end
   e.Config.BotPopulation=clone(Config.BotPopulation)
   local agent={Id=a.Id,Key='BX',Kind='Value',Budget=250000,Size=2,RecoveryReadyAt=e.Time-1}
   pop.Agents={agent}
   local balance,realized,volume=a.Balance,a.Realized,e.TotalVolume
   Health.Step(pop,agent)
   assert(not e.Orders[old]and not p.ExitOrder and not p.Triggered,'Recovery retained a target or stale reference')
   assert(p.Quantity==3 and e.TotalVolume==volume and a.Realized==realized and a.Balance==balance,'Empty book fabricated a fill or capital')
   order(e,'maker',1,1,5825);e:AdvanceClock(.25);Health.Step(pop,agent)
   assert(p.Quantity==2,'New finite liquidity failed to wake recovery')
   order(e,'maker',1,2,5825);e:AdvanceClock(.25);Health.Step(pop,agent)
   assert(not a.Positions.BX and not next(a.OpenOrders));assert(a.Balance==balance+(a.Realized-realized));e:Audit()
  end
 end)
 test('Healthy bot target stays patient and retains price/time priority',function()
  local e,a,p,pop=fixture(false,-1);partial(e,a,p);local id=p.ExitOrder;local o=e.Orders[id];local n=e.NextOrder
  for _=1,24 do e:AdvanceClock(.25)end
  assert(p.Quantity==3 and e.Orders[id]==o and e.NextOrder==n)
  order(e,'maker',-1,3,p.Target);assert(not a.Positions.BX);e:Audit()
 end)
 return rows
end
return Tests
