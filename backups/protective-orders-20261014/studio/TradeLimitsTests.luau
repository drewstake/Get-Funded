local Liquidity=require(script.Parent.TestLiquidity)
-- In-memory regression tests only: no DataStore, real player, or live exchange access.
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Ladder=table.clone(require(game.ReplicatedStorage.MarketReign.ProgressionConfig))
-- Small-balance fixtures exercise the five-contract floor; growth cases below cover larger balances.
Ladder.Tiers={{Id="Single",Size=5000,MaxContracts=5,Short="$5K trading account"}}
local T={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function fresh(tier)
 local e=E.new(Config,4527)
 e:AddAccount("maker",1e9,10000,.99,false)
 local a=e:AddAccount("test",tier.Size,tier.MaxContracts,Ladder.MarginUse,true)
 return e,a
end
local function request(side,qty,price,key)
 return {Action="Place",Contract=key or "BT",Direction=side,Quantity=qty,Type=price and "Limit"or"Market",Price=price,StopTicks=40,TargetTicks=120}
end
local function submit(e,id,r)local ok,v=Liquidity.Submit(e,id,r);assert(ok,tostring(v));return v end
local function quote(e,side,qty,price,key)
 local r=request(side,qty,price or Config.Contracts[key or "BT"].Last,key);r.StopTicks=nil;r.TargetTicks=nil
 return submit(e,"maker",r)
end
-- One participant-to-participant execution at `price`: the only way the market price moves.
local function trade(e,price,key)
 e:AddAccount("t:seller",1e9,10000,.99,false);e:AddAccount("t:buyer",1e9,10000,.99,false);e:CancelAll("maker")
 submit(e,"t:seller",{Contract=key or "BT",Direction=-1,Quantity=1,Type="Limit",Price=price})
 local r=submit(e,"t:buyer",{Contract=key or "BT",Direction=1,Quantity=1,Type="Limit",Price=price})
 assert(r.Filled==1,"Market trade did not print at "..price)
end
local function rejected(e,a,r,max,reason)
 local ok,msg=e:Submit(a.Id,r)
 assert(not ok,"Excess order accepted")
 assert(msg:find("Maximum currently available: "..max.." "..r.Contract,1,true),msg)
 if reason then assert(msg:lower():find(reason,1,true),msg)end
end
function T.Run()
 local results={}
 local function test(name,fn)local ok,msg=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and (msg or "Passed")or tostring(msg)})end
 for i,tier in ipairs(Ladder.Tiers)do
  for _,side in ipairs({1,-1})do
   test(tier.Short..(side==1 and " long "or" short ")..tier.MaxContracts.." BT with default protection",function()
    assert(tier.MaxContracts==({5,10,25,50,100})[i])
    local e,a=fresh(tier)
    rejected(e,a,request(side,tier.MaxContracts+1),tier.MaxContracts,"limit")
    quote(e,-side,tier.MaxContracts)
    local r=submit(e,a.Id,request(side,tier.MaxContracts))
    assert(r.Filled==tier.MaxContracts and a.Positions.BT.Quantity==tier.MaxContracts)
    local p=a.Positions.BT;assert(p.Direction==side and p.Stop and p.Target)
    assert(math.abs(p.Entry-p.Stop)==40*.25 and math.abs(p.Entry-p.Target)==120*.25)
    assert(Config.Contracts.BT.Multiplier==20 and Config.Contracts.BT.Tick==.25)
    rejected(e,a,request(side,1),0,"limit")
    e:AdvanceClock(.25);assert(a.Positions.BT and not a.Liquidating)
    e:Audit()
   end)
  end
 end
 test("Existing exposure, mixed instruments, pending orders and cancellation reserve total capacity",function()
  local e,a=fresh(Ladder.Tiers[1]);quote(e,-1,2);submit(e,a.Id,request(1,2))
  local pending=submit(e,a.Id,request(1,1,20480))
  rejected(e,a,request(1,3),2,"limit")
  submit(e,a.Id,request(1,1,5800,"BX"))
  rejected(e,a,request(1,2),1,"limit") -- 2 held + 1 pending BT + 1 pending BX = 4; the account total is 5
  assert(e:Cancel(a.Id,pending.Id));assert(e:OrderCapacity(a,"BT",1,40)==2) -- 5 total minus the BX entry minus 2 held
  e:CancelAll(a.Id);assert(e:OrderCapacity(a,"BT",1,40)==3)
 end)
 test("Both directions reserve worst-case entries; reduce-only exits do not reserve new exposure",function()
  local e,a=fresh(Ladder.Tiers[1]);submit(e,a.Id,request(1,5,20480));submit(e,a.Id,request(-1,5,20490))
  rejected(e,a,request(1,1),0);rejected(e,a,request(-1,1),0)
  e:CancelAll(a.Id);quote(e,-1,5);submit(e,a.Id,request(1,5))
  local close=request(-1,5,20490);close.ReduceOnly=true;submit(e,a.Id,close)
  assert(e:OrderCapacity(a,"BT",-1,40)==10)
  rejected(e,a,request(1,1),0)
 end)
 test("Below $5K the five-contract minimum remains; $0 equity still stops new entries",function()
  local e,a=fresh(Ladder.Tiers[1]);a.Balance=1000;a.Realized=1000-a.Base -- a starter account reduced to $1,000
  for _,key in ipairs(Config.ContractOrder)do
   assert(e:OrderCapacity(a,key,1)==5 and e:OrderCapacity(a,key,-1)==5,"Low equity reduced "..key.." capacity")
   local snap=e:Snapshot(a.Id,key,"1m",false);assert(snap.Capacity[key].Buy==5 and snap.Capacity[key].Sell==5,"UI capacity")
  end
  rejected(e,a,request(1,6),5,"limit")
  local r=request(1,5);r.StopTicks=1000;quote(e,-1,5)
  assert(submit(e,a.Id,r).Filled==5 and a.Positions.BT.Quantity==5,"5 BT rejected on a $1,000 balance")
  rejected(e,a,request(1,1),0,"limit")
  assert(Liquidity.Perform(e,a.Id,{Action="Close",Contract="BT"}));assert(not a.Positions.BT)
  a.Balance=0;a.Realized=-a.Base;rejected(e,a,request(-1,1),0,"$0")
  e:AdvanceClock(.25);assert(a.Locked);rejected(e,a,request(-1,1),0,"account failed")
  a.Balance=a.Base;a.Realized=0
 end)
 for _,key in ipairs(Config.ContractOrder)do
  for _,side in ipairs({1,-1})do
   test(key.." wide stops allow entry and dragging; depletion still liquidates "..side,function()
    local e,a=fresh(Ladder.Tiers[1]);local spec=Config.Contracts[key];local qty=2
    e:AddAccount("taker",1e9,10000,.99,false)
    local function tickPrice(price)return math.round(price/spec.Tick)*spec.Tick end
    local function mark(price)
     e:CancelAll("maker") -- player fills never consume quotes; clear them so the next print sets the price
     quote(e,side,1,price,key)
     local r=request(-side,1,nil,key);r.StopTicks=nil;r.TargetTicks=nil
     submit(e,"taker",r)
    end
    quote(e,-side,qty,spec.Last,key)
    local entry=request(side,qty,nil,key)
    entry.StopTicks=math.ceil(a.Base*1.5/(qty*spec.Multiplier*spec.Tick))
    assert(submit(e,a.Id,entry).Filled==qty,"Wide initial stop rejected")
    local p=a.Positions[key];local target=p.Target;local initial=p.Stop
    local wide=tickPrice(p.Entry-side*a.Base*2/(qty*spec.Multiplier))
    assert(e:AmendProtection(a.Id,{Contract=key,OrderId=p.Id,Protection="Stop",Price=wide,ExpectedPrice=initial}))
    assert(p.Stop==wide and p.Target==target and math.abs(p.Entry-wide)*qty*spec.Multiplier>a.Base)
    assert(not e:AmendProtection(a.Id,{Contract=key,OrderId=p.Id,Protection="Stop",Price=wide,ExpectedPrice=initial}),"Stale drag accepted")
    local pending=submit(e,a.Id,request(side,1,wide,key))
    mark(tickPrice(p.Entry-side*(a.Base-250)/(qty*spec.Multiplier)))
    assert(e:Summary(a).Equity>0 and e:Summary(a).Equity<e:Summary(a).Margin)
    e:AdvanceClock(.25)
    assert(a.Positions[key]==p and not p.Triggered and not a.Locked and not a.Liquidating,"Positive equity liquidated")
    assert(e:OrderCapacity(a,key,side)==2,"Low equity must not reduce the contract limit (2 held + 1 working of 5)")
    -- Alternate exact-zero and negative-equity boundaries across long/short cases.
    local beyond=side==1 and 0 or 250
    local exit=tickPrice(p.Entry-side*(a.Base+beyond)/(qty*spec.Multiplier))
    mark(exit)
    assert(a.Locked and p.Triggered=="Account depleted" and not p.Stop and not p.Target,"Depletion did not latch")
    local lastTick,volume=e.Books[key].Last,e.Books[key].Volume
    Liquidity.Offer(e,key,side,qty,exit)
    e:AdvanceClock(.25)
    -- Post executable exit liquidity; liquidation retries if the book is empty.
    assert(not e.Orders[pending.Id] and not a.Positions[key] and a.Locked,"Liquidation must cancel entries and close at the market")
    assert(e.Books[key].Last==lastTick and e.Books[key].Volume==volume+qty,"Liquidation must consume and print actual exit liquidity")
    rejected(e,a,request(side,1,nil,key),0,"account failed")
    -- The exit is tick-rounded, so on a 0.1-tick market (BG) the loss can differ from Base+beyond by under a tick per contract.
    local loss=(p.Entry-exit)*side*qty*spec.Multiplier
    assert(loss>=a.Base and math.abs(loss-(a.Base+beyond))<=qty*spec.Tick*spec.Multiplier and #a.History==1)
    assert(math.abs(a.Realized+loss)<1e-5 and math.abs(a.Balance-(a.Base-loss))<1e-5)
    e:Audit()
   end)
  end
 end
 -- Consistent 5-contract minimum on $5K for every market (equal $750 simulated margin).
 for _,key in ipairs(Config.ContractOrder)do
  for _,side in ipairs({1,-1})do
   test("$5K "..key..(side==1 and " long"or" short").." reaches exactly 5 contracts; the 6th is rejected",function()
    assert(Config.Contracts[key].Margin==750,"Unequal market margin")
    local e,a=fresh(Ladder.Tiers[1]);local last=Config.Contracts[key].Last
    assert(e:OrderCapacity(a,key,side)==5,"Fresh $5K capacity for "..key.." is "..e:OrderCapacity(a,key,side))
    rejected(e,a,request(side,6,nil,key),5,"limit")
    quote(e,-side,5,last,key);local r=submit(e,a.Id,request(side,5,nil,key))
    assert(r.Filled==5 and a.Positions[key].Quantity==5)
    rejected(e,a,request(side,1,nil,key),0,"limit")
    local snap=e:Snapshot(a.Id,key,"1m",false)
    assert(snap.Capacity[key][side==1 and "Buy" or "Sell"]==0 and snap.Capacity[key][side==1 and "Sell" or "Buy"]==10 and snap.Limit==5,"Snapshot capacity for the UI")
    e:Audit()
   end)
  end
 end
 test("Stop entries validate side, tick, band and account; they arm off-book and reserve the cap",function()
  local e,a=fresh(Ladder.Tiers[1]);local last=Config.Contracts.BX.Last
  local function stop(side,qty,price)local r=request(side,qty,price,"BX");r.Type="Stop";return r end
  assert(not e:Submit(a.Id,stop(1,1,last-1)),"Stop buy below market accepted")
  assert(not e:Submit(a.Id,stop(-1,1,last+1)),"Stop sell above market accepted")
  assert(not e:Submit(a.Id,stop(1,1,last)),"Stop buy at market accepted")
  assert(not e:Submit(a.Id,stop(1,1,last+0.1)),"Off-tick stop accepted")
  assert(not e:Submit(a.Id,stop(1,1,last*1.2)),"Stop outside the price band accepted")
  local reduce=stop(-1,1,last-5);reduce.ReduceOnly=true;assert(not e:Submit(a.Id,reduce),"Reduce-only stop accepted")
  local r=submit(e,a.Id,stop(1,3,last+5))
  assert(r.Status=="Stop armed" and r.Filled==0 and e.Orders[r.Id].Type=="Stop" and #e.Books.BX.Bids==0 and #e.Books.BX.Asks==0,"Stop rested in the book")
  rejected(e,a,request(1,3,nil,"BX"),2,"limit") -- 3 armed + 3 would exceed 5
  local sell=submit(e,a.Id,stop(-1,5,last-5)) -- opposite side is independently worst-case
  rejected(e,a,request(-1,1,last+50,"BX"),0,"limit")
  local snap=e:Snapshot(a.Id,"BX","1m",false)
  local kinds={} for _,o in ipairs(snap.Orders)do kinds[o.Kind]=o.Status end
  assert(kinds["Stop Buy"]=="Armed" and kinds["Stop Sell"]=="Armed","Orders tab labels")
  assert(e:Cancel(a.Id,sell.Id) and e:Cancel(a.Id,r.Id) and e:OrderCapacity(a,"BX",1)==5,"Cancel released capacity")
  e:Audit()
 end)
 test("A stop triggers on the trade that reaches it, fills at market with SL/TP, and reports once",function()
  local e,a=fresh(Ladder.Tiers[1]);e:AddAccount("taker",1e9,10000,.99,false);local last=Config.Contracts.BX.Last
  local r=request(1,2,last+2,"BX");r.Type="Stop";local armed=submit(e,a.Id,r)
  quote(e,-1,1,last+1,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"});e:ProcessStops()
  assert(e.Orders[armed.Id] and not a.Positions.BX,"Triggered before the stop price")
  quote(e,-1,1,last+2,"BX");quote(e,-1,5,last+3,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"})
  assert(e.Orders[armed.Id].Triggered,"Did not latch on the reaching trade")
  e:ProcessStops()
  assert(not e.Orders[armed.Id] and a.Positions.BX and a.Positions.BX.Quantity==2 and a.Positions.BX.Stop and a.Positions.BX.Target,"Stop did not become a protected market entry")
  assert(a.Triggers[1].Id==armed.Id and a.Triggers[1].Ok and a.Triggers[1].Filled==2 and #a.Triggers==1,"Trigger report")
  e:ProcessStops();assert(#a.Triggers==1,"Reported twice")
  local s=request(-1,1,a.Positions.BX.Entry-20,"BX");s.Type="Stop";submit(e,a.Id,s)
  e:Audit()
 end)
 test("A triggered stop waits for executable liquidity and never fabricates a fill",function()
  local e,a=fresh(Ladder.Tiers[1]);e:AddAccount("taker",1e9,10000,.99,false);local last=Config.Contracts.BX.Last
  local r=request(1,2,last+2,"BX");r.Type="Stop";local armed=submit(e,a.Id,r)
  quote(e,-1,1,last+2,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"})
  e:ProcessStops();assert(e.Orders[armed.Id]and not a.Positions.BX,"Empty book fabricated a fill")
  quote(e,-1,2,last+2.25,"BX");e:ProcessStops()
  assert(not e.Orders[armed.Id]and a.Positions.BX.Quantity==2 and a.Triggers[1].Filled==2)
  e:Audit()
 end)
 test("Triggered stops re-validate the balance-based cap after closed losses",function()
  local e,a=fresh(Ladder.Tiers[1]);e:AddAccount("taker",1e9,10000,.99,false);local last=Config.Contracts.BX.Last
  a.Balance=10000;a.Realized=10000-a.Base
  local r=request(1,8,last+2,"BX");r.Type="Stop";local armed=submit(e,a.Id,r)
  -- Closed losses elsewhere reduce capacity while the stop waits.
  a.Balance=5000;a.Realized=5000-a.Base
  quote(e,-1,10,last+2,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"});e:ProcessStops()
  assert(not e.Orders[armed.Id] and not a.Positions.BX,"Stop filled past the contract limit")
  assert(a.Triggers[1].Ok==false and tostring(a.Triggers[1].Message):find("Maximum currently available: 5 BX",1,true),"Rejection not reported: "..tostring(a.Triggers[1].Message))
  e:CancelAll("maker");local r2=request(1,4,last+4,"BX");r2.Type="Stop";local second=submit(e,a.Id,r2)
  a.Balance=1000;a.Realized=1000-a.Base -- the five-contract minimum remains
  quote(e,-1,10,last+4,"BX");submit(e,"taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"});e:ProcessStops()
  assert(not e.Orders[second.Id] and a.Positions.BX and a.Positions.BX.Quantity==4 and a.Triggers[1].Ok,"Low balance blocked a stop within the limit")
  a.Balance=a.Base;a.Realized=0;e:Audit()
 end)
 test("Armed stops survive a checkpoint round trip off-book and still trigger",function()
  local e=E.new(Config,3131);local population=P.new(e);for _=1,120 do population:Step() end
  local f=F.new(e,Ladder,Config);f:Start("stops");local id=f:Owner("stops")
  local last=e.Books.BX.Last*e.Books.BX.Spec.Tick
  local r=request(1,2,last+50,"BX");r.Type="Stop";local armed=submit(e,id,r)
  local snapshot=Checkpoint.Capture(e,population);assert(snapshot.Version==Checkpoint.Version)
  local restored,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(snapshot)),Config)
  local o=restored.Orders[armed.Id];assert(o and o.Type=="Stop" and restored.Accounts[id].OpenOrders[armed.Id],"Stop lost on restore")
  for _,side in ipairs({"Bids","Asks"})do for _,l in ipairs(restored.Books.BX[side])do for _,x in ipairs(l.Orders)do assert(x.Id~=armed.Id,"Stop rested in the book")end end end
  restored:AddAccount("t:maker",1e9,10000,.99,false);restored:AddAccount("t:taker",1e9,10000,.99,false)
  for _,aid in ipairs(restored.AccountOrder)do if not restored.Accounts[aid].Player then restored:CancelAll(aid)end end
  restored:ProcessStops() -- flush any participant exits carried in the checkpoint
  local top=o.Price*restored.Books.BX.Spec.Tick
  restored.Books.BX.FairReference=o.Price -- This fixture moves fair value to the stop, not just the last trade.
  submit(restored,"t:maker",{Contract="BX",Direction=-1,Quantity=1000,Type="Limit",Price=top})
  submit(restored,"t:taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"});restored:ProcessStops()
  assert(not restored.Orders[armed.Id] and restored.Accounts[id].Positions.BX and restored.Accounts[id].Positions.BX.Quantity==2,"Restored stop did not trigger")
  restored:Audit()
 end)
 test("Waiting player limits execute against incoming quantity and re-check capacity",function()
  local e,a=fresh(Ladder.Tiers[1]);local r=submit(e,a.Id,request(1,5,20480))
  a.Balance=1000;a.Realized=-4000;quote(e,-1,5,20480)
  assert(a.Positions.BT.Quantity==5 and a.Positions.BT.Entry==20480 and not e.Orders[r.Id])
  assert(Liquidity.Perform(e,a.Id,{Action="Close",Contract="BT"}))
  a.Balance=10000;a.Realized=10000-a.Base
  local second=submit(e,a.Id,request(1,8,20470));a.Balance=5000;a.Realized=5000-a.Base
  quote(e,-1,8,20470);assert(not a.Positions.BT and not e.Orders[second.Id],"Waiting entry filled past the cap")
  a.Balance=a.Base;a.Realized=0;e:Audit()
 end)
 test("A marketable player limit consumes finite liquidity and rests its residual",function()
  local e,a=fresh(Ladder.Tiers[1]);quote(e,-1,2,20485.5)
  local r=submit(e,a.Id,request(1,5,20486))
  assert(r.Filled==2 and r.Remaining==3 and r.Average==20485.5)
  assert(#e.Books.BT.Asks==0 and e.Books.BT.Bids[1].Quantity==3 and #e.Trades==1)
  rejected(e,a,request(1,1),0);e:Audit()
 end)
 test("Invalid, fractional, infinite and oversized remote quantities are rejected",function()
  local e,a=fresh(Ladder.Tiers[1])
  for _,n in ipairs({0,-1,1.5,math.huge,0/0})do assert(not e:Submit(a.Id,request(1,n)))end
  rejected(e,a,request(1,101),5);rejected(e,a,request(-1,1000),5)
 end)
 test("Saved old margins/caps adopt current policy without changing player progress or exposure",function()
  local old=clone(Config);old.Contracts.BT.Margin=2000;old.MaxPlayerInventory=40;old.MaxPlayerQuantity=20
  local e=E.new(old,592);local population=P.new(e);local f=F.new(e,Ladder,old);f:Start("migration")
  local profile=e.Profiles.migration
  local id=f:Owner("migration")
  local a=e.Accounts[id];a.Limit=40
  e:AddAccount("maker",1e9,10000,.99,false);quote(e,-1,1);submit(e,id,request(1,1))
  submit(e,id,request(1,1,20480))
  a.Limit=40 -- model the stale value persisted by the previous build
  local snapshot=Checkpoint.Capture(e,population)
  local restored=Checkpoint.Restore(snapshot,Config);F.new(restored,Ladder,Config)
  local after=restored.Accounts[id]
  assert(after.Balance==a.Balance and after.Realized==a.Realized and #after.History==#a.History)
  assert(after.Positions.BT.Entry==a.Positions.BT.Entry and after.Positions.BT.Quantity==1)
  assert(after.Positions.BT.Stop==a.Positions.BT.Stop and next(after.OpenOrders))
  assert(after.Limit==10 and restored.Books.BT.Spec.Margin==750)
  assert(restored.Profiles.migration.ProgressCredit==profile.ProgressCredit)
  assert(snapshot.Config.Contracts.BT.Margin==2000 and a.Limit==40,"Restore mutated source checkpoint")
 end)
 test("Closed balance determines capacity at every $1K boundary, with a minimum of five",function()
  local e,a=fresh(Ladder.Tiers[1])
  for _,pair in ipairs({{1,5},{999,5},{4999.99,5},{5000,5},{5999.99,5},{6000,6},{9999.99,9},{10000,10},{10999.99,10},{11000,11},{49999.99,49},{50000,50},{100000,100},{101000,101},{250000,250},{9999.999999999998,10}})do
   a.Balance=pair[1];a.Realized=a.Balance-a.Base;a.Limit=5 -- stale saved cap must not win
   for _,key in ipairs(Config.ContractOrder)do for _,side in ipairs({1,-1})do
    assert(e:OrderCapacity(a,key,side)==pair[2],"Incorrect limit for balance "..pair[1])
   end end
   local s=e:Snapshot(a.Id,"BX","1m",false)
   assert(s.Limit==pair[2] and s.Capacity.BX.Buy==pair[2] and a.Limit==pair[2],"Snapshot and cached limit disagree")
  end
 end)
 for _,balance in ipairs({10000,50000,101000,250000})do for _,key in ipairs(Config.ContractOrder)do for _,side in ipairs({1,-1})do
  test("$"..balance.." allows "..(balance/1000).." "..key.." contracts on side "..side,function()
   local e,a=fresh({Size=balance,MaxContracts=5});local limit=balance/1000
   local last=e.Books[key].Last
   rejected(e,a,request(side,limit+1,nil,key),limit,"limit")
   local r=request(side,limit,nil,key);r.StopTicks=nil;r.TargetTicks=nil
   assert(submit(e,a.Id,r).Filled==limit and a.Positions[key].Quantity==limit)
   rejected(e,a,request(side,1,nil,key),0,"limit")
   assert(e.TotalVolume==limit and e.Books[key].Last==math.round(Config.Contracts[key].Last/Config.Contracts[key].Tick),"Player fill must print exactly its executed quantity")
   assert(submit(e,a.Id,{Contract=key,Direction=-side,Quantity=limit,Type="Market",ReduceOnly=true}).Filled==limit,"Large positions can still close in full")
   e:Audit()
  end)
 end end end
 test("Realized profit/loss changes the cap immediately; open P&L does not",function()
  local e,a=fresh({Size=10000,MaxContracts=5});local b=e.Books.BX
  submit(e,a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"})
  local entry=a.Positions.BX.Entry
  b.Last=math.round((entry+1000/b.Spec.Multiplier)/b.Spec.Tick)
  assert(e:Summary(a).Equity==11000 and e:ContractLimit(a)==10,"Open profit increased cap")
  submit(e,a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true})
  assert(a.Balance==11000 and a.Limit==11 and e:Snapshot(a.Id,"BX","1m",false).Limit==11)
  submit(e,a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market"})
  b.Last-=2000/(b.Spec.Multiplier*b.Spec.Tick)
  submit(e,a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true})
  assert(a.Balance==9000 and a.Limit==9,"Closed loss did not reduce the cap immediately")
  submit(e,a.Id,{Contract="BX",Direction=1,Quantity=9,Type="Market"})
  -- Simulate a closed loss elsewhere while an existing position is above the new cap.
  a.Balance=5000;a.Realized=5000-a.Base
  assert(e:OrderCapacity(a,"BX",1)==0,"Loss must block additional exposure")
  assert(submit(e,a.Id,{Contract="BX",Direction=-1,Quantity=9,Type="Market",ReduceOnly=true}).Filled==9,"A lower cap blocked closing an existing position")
 end)
 test("$50K reservations are shared across markets and are released on cancel",function()
  local e,a=fresh({Size=50000,MaxContracts=5})
  submit(e,a.Id,request(1,20,nil,"BX"))
  local waiting=submit(e,a.Id,request(1,15,Config.Contracts.BT.Last-10,"BT"))
  assert(e:OrderCapacity(a,"BG",1)==15)
  rejected(e,a,request(1,16,nil,"BG"),15,"limit")
  assert(e:Cancel(a.Id,waiting.Id));assert(e:OrderCapacity(a,"BG",1)==30)
 end)
 return results
end
return T
