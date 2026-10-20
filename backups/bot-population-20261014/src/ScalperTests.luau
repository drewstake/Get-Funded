local Default=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(v)
 if type(v)~="table" then return v end
 local out={} for k,x in pairs(v)do out[k]=clone(x)end return out
end
local function equal(a,b)
 assert(type(a)==type(b),"Different state types")
 if type(a)~="table"then assert(a==b,"State differs");return end
 for k,v in pairs(a)do equal(v,b[k])end
 for k in pairs(b)do assert(a[k]~=nil,"Unexpected state key")end
end
local function fixture()
 local e=Engine.new(clone(Default),921)
 local p=Participants.new(e)
 for _,id in ipairs(e.AccountOrder)do e:CancelAll(id)end
 e:AddAccount("fixture-buyer",10000000,1000,1,false)
 e:AddAccount("fixture-seller",10000000,1000,1,false)
 local a for _,agent in ipairs(p.Agents)do if agent.Key=="BX" and agent.Kind=="Scalper"then a=agent;break end end
 return e,p,a
end
local function quote(e,side,ticks,quantity)
 assert(e:Submit(side==1 and "fixture-buyer" or "fixture-seller",{Contract="BX",Direction=side,Quantity=quantity or 10,Type="Limit",Price=ticks*e.Books.BX.Spec.Tick}))
end
function Tests.Run()
 local report={}
 local function test(name,fn)
  local ok,result=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})
 end
 test("Population, independent styles and strict inventory caps",function()
  local e,p=fixture()
  for _,key in ipairs(Default.ContractOrder)do
   local count,momentum,reversion=0,0,0
   for _,a in ipairs(p.Agents)do if a.Key==key and a.Kind=="Scalper"then
    count+=1;if a.Style=="Momentum"then momentum+=1 else reversion+=1 end
    assert(a.Size>=1 and a.Size<=2 and a.Limit==a.Size)
    assert(e.Accounts[a.Id].Limit==a.Size)
   end end
   assert(count==18 and momentum==9 and reversion==9)
  end
  local rng=p.Random.State;assert(p:EnsureScalpers(Default.ContractOrder,18)==0 and p.Random.State==rng)
  return "54 scalpers, balanced styles, one/two-contract caps and idempotent top-up"
 end)
 test("Missing quotes, wide spreads and cooldowns suppress entries",function()
  local e,p,a=fixture();local orders=e.NextOrder
  p:_scalper(a);assert(e.NextOrder==orders)
  local last=e.Books.BX.Last;quote(e,1,last-10);quote(e,-1,last+10)
  orders=e.NextOrder;p:_scalper(a);assert(e.NextOrder==orders)
  a.ReadyAt=e.Time+60;p:_scalper(a);assert(e.NextOrder==orders)
  e:Audit();return "No entries without a two-sided book, through a wide spread or during cooldown"
 end)
 test("Partial entry is capped, target keeps priority and timed exit is reduce-only",function()
  local e,p,a=fixture();local b=e.Books.BX local last=b.Last
  a.Size=2;a.Limit=2;e.Accounts[a.Id].Limit=2;a.Bias=100
  p.Config.Scalper.AggressiveChance=1
  quote(e,1,last-1);quote(e,-1,last+1,1)
  p:_scalper(a)
  local account=e.Accounts[a.Id];local held=assert(account.Positions.BX)
  assert(held.Quantity==1 and held.Stop and not next(account.OpenOrders),"Partial entry remainder survived")
  p:_scalper(a)
  local target=assert(e.Orders[next(account.OpenOrders)])
  assert(target.ReduceOnly and target.Direction==-held.Direction and target.Quantity==nil and target.Remaining==1)
  local priority=target.Priority;local id=target.Id
  p:_scalper(a);assert(e.Orders[id] and e.Orders[id].Priority==priority)
  e:AdvanceClock(a.MaxHold+1);p:_scalper(a)
  assert(not account.Positions.BX and not next(account.OpenOrders),"Timed exit left exposure or stale target")
  local orders=e.NextOrder;p:_scalper(a)
  assert(a.ReadyAt>e.Time and e.NextOrder==orders)
  e:Audit();return "Partial fills never pyramid; target retains FIFO; timed exit closes without reversing"
 end)
 test("Passive entries expire without accumulating orders",function()
  local e,p,a=fixture();local last=e.Books.BX.Last
  a.Bias=100;p.Config.Scalper.AggressiveChance=0
  quote(e,1,last-1);quote(e,-1,last+1)
  p:_scalper(a)
  local account=e.Accounts[a.Id];local id=assert(next(account.OpenOrders))
  assert(not account.Positions.BX)
  local n=e.NextOrder;p:_scalper(a);assert(e.NextOrder==n)
  e:AdvanceClock(a.Patience+1);e:_pruneBook(e.Books.BX)
  assert(not e.Orders[id] and not next(account.OpenOrders))
  e:Audit();return "One pending entry, bounded lifetime"
 end)
 test("Old checkpoints gain scalpers once without rewriting market history",function()
  local config=clone(Default);config.ScalperPopulationVersion=nil;config.ScalpersPerInstrument=nil;config.Scalper=nil
  config.Contracts.RTY=clone(config.LegacyContracts.RTY);table.insert(config.ContractOrder,"RTY")
  local e=Engine.new(config,4407);local p=Participants.new(e)
  for _=1,100 do p:Step()end
  e:AddAccount("bot:BX:Scalper:1",10000,2,1,false)
  local before=Checkpoint.Capture(e,p);before.Version=10
  local restored,agents=Checkpoint.Restore(before,Default)
  local after=Checkpoint.Capture(restored,agents)
  for key,value in pairs(before.Engine)do if key~="Accounts"then equal(value,after.Engine[key])end end
  for i,a in ipairs(before.Engine.Accounts)do equal(a,after.Engine.Accounts[i])end
  for i,a in ipairs(before.Population.Agents)do equal(a,after.Population.Agents[i])end
  assert(#after.Engine.Accounts==#before.Engine.Accounts+54)
  for i=#p.Agents+1,#agents.Agents do local a=agents.Agents[i]
   assert(a.Kind=="Scalper" and a.Key~="RTY" and a.Next>restored.Time and a.Id~="bot:BX:Scalper:1")
  end
  local resumed,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(after)),Default)
  equal(after,Checkpoint.Capture(resumed,rp))
  for _=1,400 do agents:Step();rp:Step()end
  equal(Checkpoint.Capture(restored,agents),Checkpoint.Capture(resumed,rp))
  restored:Audit();resumed:Audit()
  return "V10 upgrade preserves tape/accounts, skips retired markets and occupied IDs; V11 resume is exact"
 end)
 test("Longer simulation preserves inventory limits and accounting",function()
  local e=Engine.new(clone(Default),5501);local p=Participants.new(e)
  for step=1,2400 do
   p:Step()
   for _,a in ipairs(p.Agents)do if a.Kind=="Scalper"then
    local account=e.Accounts[a.Id];local held=account.Positions[a.Key]
    assert(not held or held.Quantity<=a.Limit,"Scalper exceeded inventory cap")
    local count=0;for _ in pairs(account.OpenOrders)do count+=1 end
    assert(count<=1,"Scalper accumulated orders")
   end end
   if step%400==0 then e:Audit()end
  end
  local closed=0;for _,a in ipairs(p.Agents)do if a.Kind=="Scalper"then closed+=e.Accounts[a.Id].CompletedTrades or 0 end end
  assert(closed>0);return {ClosedScalperTrades=closed,Audit=e:Audit()}
 end)
 return report
end
return Tests
