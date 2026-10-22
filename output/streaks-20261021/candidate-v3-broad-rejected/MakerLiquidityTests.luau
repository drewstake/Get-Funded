local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Tests={}
local function clone(v)
 if type(v)~="table"then return v end
 local out={}for k,x in pairs(v)do out[k]=clone(x)end return out
end
local function equal(a,b)
 assert(type(a)==type(b),"State type changed")
 if type(a)~="table"then assert(a==b,"State value changed");return end
 for k,v in pairs(a)do equal(v,b[k])end
 for k in pairs(b)do assert(a[k]~=nil,"Unexpected state key")end
end
local function fixture(count,multiplier)
 local config=clone(C);config.MakerQuoteSizeMultiplier=multiplier or 3
 local e=E.new(config,7251)
 local p=setmetatable({Engine=e,Config=config,Random=P.RNG.new(7251),Agents={},Markets={},
  Regime={Volatility=1,Liquidity=1,Activity=1},NewsUntil=0},P)
 for _,key in ipairs(config.ContractOrder)do p.Markets[key]={Fair=e.Books[key].Reference}end
 for i=1,count do
  local a=p:_agent("BX","Maker",i);a.Size=6
  p:_maker(a)
 end
 e:AddAccount("taker",1000000,1000,1,true)
 return e,p,p.Agents[1]
end
function Tests.Run()
 local results={}
 local function test(name,fn)local ok,result=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})end
 test("Larger real quotes fill a 143-contract market order in both directions",function()
  local report={}
  for _,side in ipairs({1,-1})do
   local old=fixture(3,1)
   local _,before=old:Submit("taker",{Contract="BX",Direction=side,Quantity=143,Type="Market"})
   local e=fixture(3,3)
   local ok,after=e:Submit("taker",{Contract="BX",Direction=side,Quantity=143,Type="Market"})
   assert(ok and after.Filled==143 and after.Cancelled==0)
   assert(before.Filled<143 and before.Cancelled>0)
   assert(e.Accounts.taker.Positions.BX.Quantity==143 and e.TotalVolume==143)
   old:Audit();e:Audit()
   table.insert(report,{Direction=side,Before=before.Filled,After=after.Filled})
  end
  return report
 end)
 test("Consumed quotes replenish after a short delay; partial quotes retain priority",function()
  local e,p,a=fixture(1);local bidId=a.Quotes["1:1"];local askId=a.Quotes["-1:1"]
  local bid=e.Orders[bidId];local ask=e.Orders[askId];local qty=ask.Remaining
  assert(e:Submit("taker",{Contract="BX",Direction=-1,Quantity=bid.Remaining,Type="Market"}))
  assert(e:Submit("taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
  local priority=ask.Priority;local refill=C.MakerReplenishSeconds*(a.QuoteRefillFactor or 1)
  p:_maker(a)
  assert(not a.Quotes["1:1"] and a.ReplenishAt["1:1"]==e.Time+refill)
  e:AdvanceClock(refill-.25);p:_maker(a)
  assert(not a.Quotes["1:1"],"Replenished before cooldown")
  e:AdvanceClock(.25);p:_maker(a)
  assert(a.Quotes["1:1"] and a.Quotes["1:1"]~=bidId,"Depleted slot not replenished")
  assert(a.Quotes["-1:1"]==askId and ask.Remaining==qty-1 and ask.Priority==priority,"Partial quote lost FIFO")
  e:Audit();return tostring(C.MakerReplenishSeconds).."-second refill delay; existing partial quote preserved"
 end)
 test("Larger quotes fit available inventory and capital without resetting balances",function()
  local e,p,a=fixture(1);e:CancelAll(a.Id);a.QuotePolicy=nil
  local account=e.Accounts[a.Id];account.Limit=5;a.Limit=5;a.Size=9
  local balance,base=account.Balance,account.Base
  p:_maker(a)
  local buy,sell=0,0
  for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o.Direction==1 then buy+=o.Remaining else sell+=o.Remaining end end
  assert(buy==5 and sell==5,"Did not size quotes to the remaining inventory allowance")
  assert(account.Balance==balance and account.Base==base and e:Exposure(account,"BX",1,0))
  e:CancelAll(a.Id);a.QuotePolicy=nil;account.Risk=0
  p:_maker(a);assert(not next(account.OpenOrders),"Posted without risk capacity")
  e:Audit();return "Quotes capped at five per side; no quotes with zero buying power"
 end)
 test("Thin liquidity regimes retain smaller finite depth",function()
  local e,p,a=fixture(1);e:CancelAll(a.Id);a.QuotePolicy=nil
  p.Regime.Liquidity=.22;p:_maker(a)
  local n=0;for id in pairs(e.Accounts[a.Id].OpenOrders)do
   n+=1;assert(e.Orders[id].Remaining<=4,"Thin market received full-sized quotes")
  end
  assert(n==2,"Thin market should have one level per side")
  e:Audit();return "Stress still reduces size and depth"
 end)
 test("Makers distribute finite quotes across configured price lanes",function()
  local c=clone(C);local e=E.new(c,891)
  local p=setmetatable({Engine=e,Config=c,Random=P.RNG.new(891),Agents={},Markets={},
   Regime={Volatility=1,Liquidity=1,Activity=1}},P)
  for _,key in ipairs(c.ContractOrder)do
   p.Markets[key]={};local b=e.Books[key];local prices={}
   for i=1,c.MakerLanes.Count do
    local a=p:_agent(key,'Maker',i);p:_maker(a)
    local o=assert(e.Orders[a.Quotes['-1:1']]);prices[i]=o.Price
    if i>1 then assert(prices[i]-prices[i-1]==c.MakerLanes.SpacingTicks[key])end
   end
   assert(e.TotalVolume==0 and b.Last==nil)
  end
  e:Audit()
 end)
 test("Old worlds adopt tuning without altering accounts, tape or resting orders during restore",function()
  local old=clone(C);old.MakerQuotePolicyVersion=2
  old.MakerQuoteSizeMultiplier=nil;old.MakerReplenishSeconds=nil;old.MakerDecisionMultiplier=nil
  local e=E.new(old,7282);local p=P.new(e)
  for _=1,200 do p:Step()end
  local before=Checkpoint.Capture(e,p)
  local restored,agents=Checkpoint.Restore(before,C)
  local after=Checkpoint.Capture(restored,agents)
  equal(before.Engine,after.Engine);equal(before.Population,after.Population)
  assert(after.Config.MakerQuoteSizeMultiplier==C.MakerQuoteSizeMultiplier and after.Config.MakerReplenishSeconds==C.MakerReplenishSeconds and after.Config.MakerDecisionMultiplier==.5)
  local resumed,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(after)),C)
  equal(after,Checkpoint.Capture(resumed,rp))
  for _=1,400 do agents:Step();rp:Step()end
  equal(Checkpoint.Capture(restored,agents),Checkpoint.Capture(resumed,rp))
  local migrated=0;for _,a in ipairs(agents.Agents)do if a.Kind=="Maker" and a.QuotePolicy==C.MakerQuotePolicyVersion then migrated+=1 end end
  assert(migrated==180);restored:Audit();resumed:Audit()
  return "Restore preserves history and accounts; makers adopt the policy on their next turn; replay remains exact"
 end)
 test("Repricing withdraws first and waits for an individual replacement clock",function()
  local e,p,a=fixture(1);local b=e.Books.BX;local slot='-1:1';local id=a.Quotes[slot]
  local old=e.Orders[id];local cash=e.Accounts[a.Id].Balance;local volume=e.TotalVolume;local last=b.Last
  -- A wider quoted spread tests repricing without fabricating a trade or editing the book.
  p.Regime.Volatility=8;e.Time=C.MakerMinRestSeconds+1
  p:_maker(a)
  assert(not e.Orders[id]and not a.Quotes[slot]);local due=a.ReplenishAt[slot];assert(due>e.Time)
  p:_maker(a);assert(not a.Quotes[slot]);assert(e.TotalVolume==volume and b.Last==last and e.Accounts[a.Id].Balance==cash)
  e.Time=due;p:_maker(a);assert(a.Quotes[slot]and a.Quotes[slot]~=id);e:Audit()
 end)
 test("Maker refill profiles are diverse, repeatable and do not draw shared randomness",function()
  local e,p,a=fixture(1);local factors={};local n=0
  for i=2,20 do local agent=p:_agent('BX','Maker',i);local before=p.Random.State;p:_maker(agent);assert(before==p.Random.State)
   assert(agent.QuoteRefillFactor>=.6 and agent.QuoteRefillFactor<=1.4)
   local bucket=math.floor(agent.QuoteRefillFactor*10);if not factors[bucket]then factors[bucket]=true;n+=1 end
   local value=agent.QuoteRefillFactor;agent.QuoteRefillFactor=nil;p:_maker(agent);assert(agent.QuoteRefillFactor==value)
  end
  assert(n>=4);e:Audit()
 end)
 test("Maker adoption preserves manual exits, stop removal, balances and live inventory",function()
  local e,p,a=fixture(1);local b=e.Books.BX;local ac=e.Accounts[a.Id]
  assert(e:Submit('taker',{Contract='BX',Direction=-1,Quantity=2,Type='Market'}))
  local pos=ac.Positions.BX;assert(pos and pos.Direction==1);pos.Stop=nil;pos.ManualStop=true
  local ok,result=e:Submit(a.Id,{Contract='BX',Direction=-1,Quantity=1,Type='Limit',Price=(b.Last+50)*b.Spec.Tick,ReduceOnly=true});assert(ok)
  local before=clone(pos);local cash=ac.Balance;local volume=e.TotalVolume;a.QuotePolicy=7;p:_maker(a)
  equal(before,pos);assert(e.Orders[result.Id]and ac.Balance==cash and e.TotalVolume==volume);e:Audit()
 end)
 test("V27 policy migration is economically read-only and refuses policy downgrade",function()
  local e=E.new(clone(C),71);local p=P.new(e);local saved=Checkpoint.Capture(e,p)
  saved.Version=27;saved.Config.MakerQuotePolicyVersion=7;saved.Config.MakerRepricePause=nil;saved.Config.BotMomentum.Version=1
  local before=clone(saved);local re,rp=Checkpoint.Restore(saved,C)
  equal(saved,before);equal(saved.Engine,Checkpoint.Capture(re,rp).Engine)
  assert(re.Config.MakerQuotePolicyVersion==8 and re.Config.BotMomentum.Version==3)
  local old=clone(C);old.MakerQuotePolicyVersion=7;assert(not pcall(Checkpoint.Restore,Checkpoint.Capture(re,rp),old));re:Audit()
 end)
 test("Pending staggered Maker replacements survive a complete checkpoint replay",function()
  local e=E.new(clone(C),7919);local p=P.new(e)
  for _,a in ipairs(p.Agents)do if a.Kind=='Maker'then
   local id=a.Quotes['1:1'];if id then e:Cancel(a.Id,id);p:_maker(a)end
  end end
  local saved=Checkpoint.Decode(Checkpoint.Encode(Checkpoint.Capture(e,p)));local re,rp=Checkpoint.Restore(saved,C)
  for i=1,100 do p:Step();rp:Step()end
  equal(Checkpoint.Capture(e,p),Checkpoint.Capture(re,rp));e:Audit();re:Audit()
 end)

 return results
end
return Tests
