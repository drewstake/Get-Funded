local Default=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local Policy=require(script.Parent.PlayerExecution)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local F=require(script.Parent.FundedAccounts)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local t={}for k,x in pairs(v)do t[k]=clone(x)end return t end
local function equal(a,b)
 assert(type(a)==type(b),"State types differ")
 if type(a)~="table"then assert(a==b,"State differs: "..tostring(a).." / "..tostring(b));return end
 for k,v in pairs(a)do equal(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Unexpected key "..tostring(k))end
end
local function fixture()
 local c=clone(Default);c.ParticipantsPerInstrument=0;c.MakersPerInstrument=0;c.ScalpersPerInstrument=0;c.WhaleFrequency=0;c.NewsFrequency=0
 -- Deliberately deep fixture for arithmetic/queue ceiling tests, not production depth.
 -- Production quote realism and depth-limited execution are covered by DepthRealismTests.
 c.Reserve.QuoteSize=100000;c.Reserve.QuoteSizes=nil;c.Reserve.SizeVariation=nil
 c.Reserve.Offsets={2,4,8,12,16};c.Reserve.SpacingTicks=nil;c.Reserve.DepthGrowth=.5
 c.Regimes={{Name="Fixed",Weight=1,Volatility=0,Liquidity=1,Activity=1,Trend=0}}
 local e=E.new(c,7411);local p=P.new(e)
 return e,p,c
end
local function player(e,id,balance,profile)
 local a=e:AddAccount(id,balance or 1000000000,10000000,.8,true);a.ProfileId=profile or id;return a
end
local function submit(e,id,key,side,qty,kind,price)
 local ok,r=e:Submit(id,{Contract=key,Direction=side,Quantity=qty,Type=kind or"Market",Price=price,Execution="Sliced"})
 assert(ok,tostring(r));return r
end
local function refill(e,p)
 for _,a in ipairs(p.Agents)do if a.Kind=="Reserve"then p:_reserve(a)end end
end
local function window(e,p)
 e:AdvanceClock(e.Config.PlayerExecution.WindowSeconds);refill(e,p)
 for _=1,8 do e:ProcessPlayerOrders()end
end
function Tests.Run()
 local results={};local function test(name,fn)local ok,r=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and r or tostring(r)})end
 test("Billion-dollar balances retain buying power while spam shares one allowance",function()
  local e,p,c=fixture();local a=player(e,"whale",10000000000,"same-user")
  assert(e:ContractLimit(a)==10000000)
  for _=1,40 do
   local r=submit(e,a.Id,"BX",1,10000);if r.Remaining>0 then e:Cancel(a.Id,r.Id)end
  end
  assert(a.Positions.BX.Quantity==c.PlayerExecution.OwnerContracts,"Spam exceeded owner allowance")
  local other=player(e,"alternate",10000000000,"same-user")
  local r=submit(e,other.Id,"BT",1,10000)
  assert(r.Filled==0 and r.Queued,"Account/instrument switch reset budget")
  assert(#e.Books.BX.Asks>0 and #e.Books.BX.Bids>0)
  assert(e.Books.BX.Last<=e.Books.BX.FairReference+2,"One player walked reserve depth")
  e:Audit();return {Balance=a.Base,AllowedHoldings=a.Limit,SpamFills=a.Positions.BX.Quantity,Attempts=40}
 end)
 test("One-million-contract order fills progressively and closes without reversal",function()
  local e,p=fixture();local a=player(e,"billion")
  local r=submit(e,a.Id,"BX",1,1000000);assert(r.Queued and r.Filled==5000)
  for _=1,55 do window(e,p)end
  assert(not e.Orders[r.Id]and a.Positions.BX.Quantity==1000000)
  local ok,close=F.Perform(e,a.Id,{Action="Close",Contract="BX"})
  assert(ok and close.Queued and close.Remaining+close.Filled==1000000)
  for _=1,55 do window(e,p)end
  assert(not a.Positions.BX and not next(a.OpenOrders),"Close left or reversed exposure")
  assert(a.Realized<=0,"Repeated buy/sell generated profit at fixed fair value")
  e:Audit();return {Contracts=1000000,Realized=a.Realized,Audit=e:Audit()}
 end)
 test("Thirty-two players get turns without draining the book",function()
  local e,p,c=fixture();local accounts={}
  for i=1,32 do local a=player(e,string.format("player-%02d",i));table.insert(accounts,a);submit(e,a.Id,"BX",1,100000)end
  for _=1,8 do e:ProcessPlayerOrders()end
  local total=0;for _,a in ipairs(accounts)do local held=a.Positions.BX;total+=held and held.Quantity or 0 end
  assert(total<=c.PlayerExecution.MarketContracts,"Market-wide budget exceeded")
  for _=1,2 do window(e,p)end
  local served=0;for _,a in ipairs(accounts)do if a.Positions.BX then served+=1 end end
  assert(served==32,"Older players starved others")
  assert(#e.Books.BX.Bids>0 and #e.Books.BX.Asks>0)
  e:Audit();return {Players=served,FirstWindowContracts=total}
 end)
 test("Ten-billion-dollar account can execute and close ten million gold contracts",function()
  local e,p=fixture();local a=player(e,"large-gold",10000000000)
  local r=submit(e,a.Id,"BG",1,10000000)
  for _=1,505 do window(e,p)end
  assert(not e.Orders[r.Id]and a.Positions.BG.Quantity==10000000)
  e:Audit();assert(F.Perform(e,a.Id,{Action="Close",Contract="BG"}))
  for _=1,505 do window(e,p)end
  assert(not a.Positions.BG and not next(a.OpenOrders))
  return {Contracts=10000000,Audit=e:Audit()}
 end)
 test("Marketable limits, amendments and triggered large stops use paced execution",function()
  local e,p,c=fixture();local a=player(e,"limit")
  local price=(e.Books.BX.Reference+15)*c.Contracts.BX.Tick
  local r=submit(e,a.Id,"BX",1,100000,"Limit",price)
  assert(r.Queued and r.Filled==5000)
  local o=e.Orders[r.Id]
  assert(e:AmendOrder(a.Id,{Contract="BX",OrderId=o.Id,Price=price+c.Contracts.BX.Tick,ExpectedPrice=price,ExpectedQuantity=o.Remaining}))
  assert(a.Positions.BX.Quantity<=10000);e:Audit()
  local stopOwner=player(e,"stop")
  local trigger=(e.Books.BX.Last+1)*c.Contracts.BX.Tick
  local stop=submit(e,stopOwner.Id,"BX",1,100000,"Stop",trigger)
  e.Orders[stop.Id].Triggered=e.Time -- Isolate conversion after the normal trigger latch.
  e:ProcessStops()
  assert(e.Orders[stop.Id]and e.Orders[stop.Id].Type=="Market" and e.Orders[stop.Id].Queued)
  assert(#stopOwner.Triggers==1 and stopOwner.Triggers[1].Queued)
  e:Cancel(a.Id,r.Id);e:Cancel(stopOwner.Id,stop.Id);e:Audit()
  return "Large limit/stop paths cannot bypass execution budgets or cross the resting book"
 end)
 test("Guard refuses adverse distant prices and cancellation releases only the order",function()
  local e,p,c=fixture();local a=player(e,"guard")
  for _,agent in ipairs(p.Agents)do e:CancelAll(agent.Id)end
  local provider=e.Accounts[p.Agents[1].Id]
  local tick=e.Books.BX.FairReference+100
  submit(e,provider.Id,"BX",-1,100000,"Limit",tick*c.Contracts.BX.Tick)
  local last=e.Books.BX.Last
  local r=submit(e,a.Id,"BX",1,10000)
  assert(r.Queued and r.Filled==0 and e.Books.BX.Last==last)
  e:Cancel(a.Id,r.Id);assert(not next(a.OpenOrders))
  local small=submit(e,a.Id,"BX",1,100)
  assert(small.Queued)
  e:CancelAll(provider.Id);e:AdvanceClock(c.PlayerExecution.WindowSeconds);e:ProcessPlayerOrders()
  assert(e.Orders[small.Id]and e.Orders[small.Id].Queued,"Queued small order disappeared during a liquidity gap")
  e:Cancel(a.Id,small.Id)
  local restored=Checkpoint.Restore(Checkpoint.Capture(e,p),c)
  equal(e.Execution,restored.Execution);restored:Audit()
  return "Orders wait at the independent fair-value guard; no fabricated fills"
 end)
 test("Remote limit quotes cannot pump a bot fill; voluntary queued closes can be cancelled",function()
  local e,p,c=fixture();local a=player(e,"quote-guard")
  for _,agent in ipairs(p.Agents)do e:CancelAll(agent.Id)end
  local b=e.Books.BX;local price=(b.FairReference+100)*b.Spec.Tick
  local r=submit(e,a.Id,"BX",1,10000,"Limit",price)
  assert(r.Queued and #b.Bids==0,"Aggressive out-of-band quote rested in empty book")
  e:Cancel(a.Id,r.Id)
  local ask=submit(e,a.Id,"BX",-1,10000,"Limit",price)
  assert(not ask.Queued and #b.Asks==1)
  local provider=e.Accounts[p.Agents[1].Id];local bot=submit(e,provider.Id,"BX",1,1)
  assert(bot.Filled==0 and b.Last==nil,"Bot used distant player quote to mark up the market")
  e:Cancel(a.Id,ask.Id);refill(e,p);e:AdvanceClock(c.PlayerExecution.WindowSeconds)
  local buy=submit(e,a.Id,"BX",1,10000);e:ProcessPlayerOrders()
  e:CancelAll(a.Id)
  local ok,close=F.Perform(e,a.Id,{Action="Close",Contract="BX"});assert(ok and close.Queued)
  assert(e:Cancel(a.Id,close.Id));local quantity=a.Positions.BX.Quantity
  window(e,p);assert(a.Positions.BX.Quantity==quantity and not next(a.OpenOrders),"Cancelled close restarted")
  e:Audit();return "Outlying player quotes cannot force prices; cancelled voluntary exits stay cancelled"
 end)
 test("Queued markets and limits survive restart with budgets and FIFO state",function()
  local e,p,c=fixture();local a=player(e,"saved")
  local r=submit(e,a.Id,"BX",1,1000000)
  local b=player(e,"saved-limit")
  submit(e,b.Id,"BX",1,1000000,"Limit",(e.Books.BX.Reference+15)*c.Contracts.BX.Tick)
  local captured=Checkpoint.Capture(e,p)
  local restored,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(captured)),c)
  equal(captured,Checkpoint.Capture(restored,rp))
  for _=1,4 do window(e,p);window(restored,rp)end
  equal(Checkpoint.Capture(e,p),Checkpoint.Capture(restored,rp))
  assert(restored.Orders[r.Id].Remaining>0)
  restored:SetConnectedOwners({[a.Id]=true,[b.Id]=true})
  restored:SetConnected(a.Id,false);assert(not restored.Orders[r.Id],"Disconnect retained queued entry")
  e:Audit();restored:Audit();return "Exact replay, saved allowances, cancellable/disconnect-safe queues"
 end)
 test("Pre-reserve saves gain institutions without changing existing accounts or history",function()
  local c=clone(Default);c.Reserve=nil;c.ReservePopulationVersion=nil;c.PlayerExecution=nil
  local e=E.new(c,924);local p=P.new(e)
  for _=1,40 do p:Step()end
  local before=Checkpoint.Capture(e,p);before.Version=11
  local restored,rp=Checkpoint.Restore(before,Default);local after=Checkpoint.Capture(restored,rp)
  for i,a in ipairs(before.Engine.Accounts)do equal(a,after.Engine.Accounts[i])end
  for k,v in pairs(before.Engine)do if k~="Accounts"then equal(v,after.Engine[k])end end
  assert(#after.Engine.Accounts==#before.Engine.Accounts+18)
  local n=0;for _,a in ipairs(rp.Agents)do if a.Kind=="Reserve"then n+=1;assert(a.Next>restored.Time)end end
  assert(n==18);restored:Audit();return "18 funded reserves added once; existing balances, tape and positions preserved"
 end)
 return results
end
return Tests
