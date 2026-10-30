-- Isolated regression scenarios for market migrations, progression and equity.
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local C=require(script.Parent.WorldCheckpoint)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Ladder=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local T={}
local function clone(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=clone(x) end return r end
local function near(a,b) assert(math.abs(a-b)<1e-5,tostring(a).." ~= "..tostring(b)) end
local function submit(e,who,key,side,qty,price,extra)
 local r={Contract=key,Direction=side,Quantity=qty,Type=price and "Limit" or "Market",Price=price}
 for k,v in pairs(extra or {}) do r[k]=v end
 local ok,result=e:Submit(who,r) assert(ok,tostring(result)) return result
end
local function fresh()
 local e=E.new(Config,987) local f=F.new(e,Ladder,Config)
 e:AddAccount("maker",1e9,10000,.99,false) e:AddAccount("taker",1e9,10000,.99,false)
 f:Start("test") return e,f,e.Accounts[f:Owner("test")]
end
function T.LegacyWorld()
 local config=clone(Config) config.Contracts={} config.ContractOrder={"MES","MNQ","M2K","MYM"} config.DailyLossLimit=1000
 for _,key in ipairs(config.ContractOrder) do config.Contracts[key]=clone(Config.LegacyContracts[key]);config.Contracts[key].CloseOnly=nil end
 local e=E.new(config,7239) local p=P.new(e)
 for _=1,200 do p:Step() end
 local f=F.new(e,Ladder,config) f:Start("old") local a=e.Accounts[f:Owner("old")]
 e:AddAccount("fixture-maker",1e9,10000,.99,false)
 for _,id in ipairs(e.AccountOrder) do e:CancelAll(id) end
 submit(e,"fixture-maker","MES",-1,2,5825)
 submit(e,a.Id,"MES",1,2,nil,{StopTicks=400,TargetTicks=800})
 submit(e,a.Id,"M2K",1,1,2200)
 a.LossLimit=500 a.Locked=true -- old positive-equity loss lock must be lifted
 a.History={{Contract="MES",Pnl=12.5,Quantity=1,Entry=5822.5,Exit=5825,Time="00:01:00"}}
 local profile=f:Profile("old") profile.V=1 profile.ProgressCredit=nil
 profile.Tiers.F10K={State="Unlocked",Announced=true}
 local snapshot=C.Capture(e,p);snapshot.Version=2
 return snapshot,a.Id
end
-- A V6 save from the build that listed ES, NQ, RTY and YM (the same economics under the old symbols).
function T.ClassicWorld()
 local config=clone(Config) config.Renamed=nil config.ContractOrder={"ES","NQ","RTY","YM"}
 config.Contracts={ES=clone(Config.Contracts.BX),NQ=clone(Config.Contracts.BT),RTY=clone(Config.LegacyContracts.RTY),YM=clone(Config.LegacyContracts.YM)}
 for _,key in ipairs(config.ContractOrder) do config.Contracts[key].CloseOnly=nil end
 local e=E.new(config,6106) local p=P.new(e)
 for _=1,200 do p:Step() end
 local f=F.new(e,Ladder,config) f:Start("classic") local a=e.Accounts[f:Owner("classic")]
 e:AddAccount("fixture-maker",1e9,10000,.99,false)
 for _,id in ipairs(e.AccountOrder) do e:CancelAll(id) end
 submit(e,"fixture-maker","NQ",-1,1,20500);submit(e,a.Id,"NQ",1,1)
 assert(F.Perform(e,a.Id,{Action="Close",Contract="NQ"}))
 submit(e,"fixture-maker","ES",-1,2,5825)
 submit(e,a.Id,"ES",1,2,nil,{StopTicks=40,TargetTicks=80})
 local held=a.Positions.ES
 assert(e:AmendProtection(a.Id,{Contract="ES",OrderId=held.Id,Protection="Stop",Price=held.Stop-1,ExpectedPrice=held.Stop}))
 submit(e,a.Id,"ES",1,1,5700) -- working entry limit: moves with its market
 submit(e,"fixture-maker","RTY",-1,1,2200)
 submit(e,a.Id,"RTY",1,1,nil,{StopTicks=50})
 submit(e,a.Id,"RTY",1,1,2150) -- entry limit in a market that retires: cancelled on restore
 submit(e,a.Id,"RTY",-1,1,2260,{ReduceOnly=true}) -- closing limit: kept
 local snapshot=C.Capture(e,p);snapshot.Version=6
 return snapshot,a.Id
end
function T.Run()
 local results={}
 local function test(name,fn) local ok,detail=pcall(fn);table.insert(results,{Name=name,Passed=ok,Detail=ok and detail or tostring(detail)}) end
 test("Every progression boundary, current-stage reset and top-tier completion",function()
  local e,f,a=fresh()
  local thresholds={3000,8000,18000,38000,78000}
  local goals={3000,5000,10000,20000,40000}
  for i,value in ipairs(thresholds) do
   a.Realized=value-.01;a.Balance=a.Base+a.Realized;f:Evaluate("test")
   local v=f:View("test");assert(v.Next and v.Next.Goal==goals[i]);near(v.Next.Remaining,.01)
   a.Realized=value;a.Balance=a.Base+value;f:Evaluate("test")
   v=f:View("test")
   if i<5 then assert(v.Next.Goal==goals[i+1]);near(v.Next.Progress,0)
   else assert(v.Completed and not v.Next) end
  end
  local events=f:TakeEvents("test");assert(events[#events].Kind=="Completed")
  f:Evaluate("test");assert(not f:TakeEvents("test"))
  a.Realized=70000;a.Balance=75000;f:Evaluate("test");assert(f:View("test").Completed)
 end)
 test("Closed losses reduce progress; activation, capital and switching never add profit",function()
  local e,f,a=fresh();a.Realized=3500;a.Balance=8500;f:Evaluate("test");f:Activate("test","F10K")
  local v=f:View("test");near(v.Next.Progress,500);near(v.Earned,3500)
  f:Select("test","F10K:1");local ten=e.Accounts[f:Owner("test")]
  ten.Realized=-250;ten.Balance=9750;f:Evaluate("test");near(f:View("test").Next.Progress,250)
  for _=1,5 do f:Select("test","F5K:1");f:Select("test","F10K:1");f:Evaluate("test") end
  near(f:View("test").Earned,3250)
  ten.Realized=-600;ten.Balance=9400;f:Evaluate("test")
  assert(f:Profile("test").Tiers.F10K);near(f:View("test").Next.Progress,0)
 end)
 test("Grandfathered stages retain surplus/losses and migrate exactly once",function()
  for index=2,5 do
   local e,f,a=fresh();local profile=f:Profile("test")
   for i=2,index do profile.Tiers[Ladder.Tiers[i].Id]={State="Unlocked",Announced=true} end
   local id=Ladder.Tiers[index].Id local old=Ladder.LegacyUnlocks[id]
   a.Realized=old+100;a.Balance=5000+a.Realized;profile.V=1;profile.ProgressCredit=nil
   f=F.new(e,Ladder,Config);local v=f:View("test")
   near(v.Earned,old+100);near(v.Next.Progress,100);near(v.ProgressCredit,Ladder.Tiers[index].Unlock-old)
   local credit=v.ProgressCredit;f=F.new(e,Ladder,Config);near(f:View("test").ProgressCredit,credit)
   a.Realized-=250;a.Balance-=250;f:Evaluate("test");near(f:View("test").Next.Progress,0)
  end
 end)
 test("Market tick economics, both directions, partial closing and stop estimates",function()
  local expected={BX={50,.25,12.5},BT={20,.25,5},BG={100,.1,10}}
  for key,spec in pairs(expected) do
   near(Config.Contracts[key].Multiplier,spec[1]);near(Config.Contracts[key].Tick,spec[2])
   for _,side in ipairs({1,-1}) do
    local e,f,a=fresh();local price=Config.Contracts[key].Last
    submit(e,"maker",key,-side,2,price);submit(e,a.Id,key,side,2,nil,{StopTicks=4,TargetTicks=12})
    local p=a.Positions[key];near((p.Entry-p.Stop)*p.Direction*p.Quantity*spec[1],8*spec[3])
    submit(e,"maker",key,side,1,price+side*spec[2]);submit(e,a.Id,key,-side,1,nil,{ReduceOnly=true})
    submit(e,"taker",key,-side,1) -- the player's fill is off-book; this participant trade marks the market there
    near(a.Realized,spec[3]);near(e:Summary(a).Unrealized,spec[3]);assert(p.Quantity==1)
    e:Audit()
   end
  end
 end)
 test("A fresh $5K can trade BX, BT or BG; wide stops are allowed within buying power",function()
  for _,key in ipairs({"BX","BT","BG"}) do
   local e,f,a=fresh();local price=Config.Contracts[key].Last
   submit(e,"maker",key,-1,1,price);assert(submit(e,a.Id,key,1,1).Filled==1)
   assert(not e:Submit(a.Id,{Contract=key,Direction=1,Quantity=5,Type="Market"}))
   submit(e,"maker",key,-1,1,price)
   assert(submit(e,a.Id,key,1,1,nil,{StopTicks=10000}).Filled==1)
  end
 end)
 test("Positive equity keeps funded positions open below maintenance margin, with no free restart",function()
  local e,f,a=fresh();submit(e,"maker","BX",-1,3,5825);submit(e,a.Id,"BX",1,3)
  submit(e,"maker","BX",1,4,5813);submit(e,"taker","BX",-1,1)
  e:AdvanceClock(.25)
  assert(a.Positions.BX and not a.Locked and not a.Liquidating);near(a.Balance,5000);near(e:Summary(a).Equity,3200)
  assert(not f:Restart("test","F5K"))
  -- Reduced equity never reduces the contract limit: 3 held of 5.
  assert(e:OrderCapacity(a,"BX",1)==2 and e:OrderCapacity(a,"BT",-1)==2,"Reduced equity must not restrict entries")
  assert(F.Perform(e,a.Id,{Action="Close",Contract="BX"}));assert(not a.Positions.BX);near(a.Balance,3200)
  submit(e,"maker","BX",-1,1,5813);e:AdvanceClock(.25);assert(submit(e,a.Id,"BX",1,1).Filled==1)
  e:Audit()
 end)
 test("Only depletion fails; intrastep depletion latches and restart retains closed losses/history",function()
  local e,f,a=fresh();submit(e,"maker","BX",-1,1,5825);submit(e,a.Id,"BX",1,1)
  submit(e,"maker","BX",1,2,5725);submit(e,"taker","BX",-1,1)
  assert(a.Locked,"Depletion must latch immediately at execution")
  e:ProcessStops();assert(not a.Positions.BX);near(a.Balance,0);near(a.Realized,-5000)
  local history=#a.History;assert(f:Restart("test","F5K"));assert(a.Retired and #a.History==history)
  near(f:View("test").Earned,-5000);near(f:View("test").Next.Progress,0);near(f:View("test").Next.Remaining,3000)
  e:Audit()
 end)
 test("Positive equity survives losses larger than the former daily/trailing allowance",function()
  local e,f,a=fresh();submit(e,"maker","BX",-1,1,5825);submit(e,a.Id,"BX",1,1)
  submit(e,"maker","BX",1,2,5800);submit(e,"taker","BX",-1,1);e:AdvanceClock(.25)
  assert(not a.Locked and a.Positions.BX);near(e:Summary(a).Equity,3750);near(e:Summary(a).Allowance,3750)
 end)
 test("Micro checkpoint migration preserves exposure, history, prices, candles and pending protection",function()
  local saved,id=T.LegacyWorld();local before=clone(saved)
  local e,p=C.Restore(C.Decode(C.Encode(saved)),Config);local a=e.Accounts[id]
  assert(a.Balance==5000 and a.Realized==0 and a.LossLimit==5000 and not a.Locked)
  assert(a.Positions.MES.Quantity==2 and a.Positions.MES.Entry==5825 and a.Positions.MES.Stop==5725)
  assert(a.History[1].Contract=="MES" and a.History[1].Pnl==12.5 and not next(a.OpenOrders))
  assert(e.Books.MES.Last==before.Engine.Books.MES.Last and #e.Books.MES.Candles["1m"]==#before.Engine.Books.MES.Candles["1m"])
  assert(e.Config.SimulationSpeed==18 and e.Books.BX.Spec.Multiplier==50 and e.Books.MES.Spec.Multiplier==5)
  assert(not e:Submit(id,{Contract="MES",Direction=1,Quantity=1,Type="Market"}))
  for _,owner in ipairs(e.AccountOrder) do e:CancelAll(owner) end
  submit(e,"fixture-maker","MES",1,2,5826);assert(F.Perform(e,id,{Action="Close",Contract="MES"}))
  near(a.Realized,10);near(a.Balance,5010);assert(a.History[1].Pnl==10 and a.History[2].Pnl==12.5)
  local f=F.new(e,Ladder,Config);local credit=f:View("old").ProgressCredit
  local nextSnapshot=C.Capture(e,p);local r,q=C.Restore(C.Decode(C.Encode(nextSnapshot)),Config)
  local g=F.new(r,Ladder,Config);near(g:View("old").ProgressCredit,credit);near(r.Accounts[id].Balance,5010)
  assert(#q.Agents==#p.Agents and #r.Config.ContractOrder==7,"Restore duplicated markets")
  e:Audit();r:Audit()
  return {LegacyRealized=10,HistoryPreserved=true,CancelledPending=true,Participants=#p.Agents}
 end)
 test("E-mini era save renames ES/NQ to BX/BT, keeps RTY/YM close-only and opens a tradable BG",function()
  local saved,id=T.ClassicWorld();local before=clone(saved)
  local old;for _,x in ipairs(before.Engine.Accounts) do if x.Id==id then old=x end end
  local e,p=C.Restore(C.Decode(C.Encode(saved)),Config);local a=e.Accounts[id]
  local order=table.concat(e.Config.ContractOrder,",")
  assert(order=="BX,BT,BG,RTY,YM","Restored markets: "..order)
  assert(not e.Books.ES and not e.Books.NQ and not a.Positions.ES and e.Books.BX.Spec.Name=="Blox 500")
  local bx,es=a.Positions.BX,old.Positions.ES
  assert(bx.Contract=="BX" and bx.Quantity==2 and bx.Entry==es.Entry and bx.Stop==es.Stop and bx.ManualStop and bx.Target==es.Target,"Position moves with its market")
  assert(e.Books.BX.Last==before.Engine.Books.ES.Last and #e.Books.BX.Candles["1m"]==#before.Engine.Books.ES.Candles["1m"],"Book and candles move")
  assert(a.History[1].Contract=="BT" and e:Summary(a).Equity>0)
  local working={}
  for orderId in pairs(a.OpenOrders) do local o=e.Orders[orderId];table.insert(working,o.Contract..(o.ReduceOnly and":close"or":entry")) end
  table.sort(working);assert(table.concat(working,",")=="BX:entry,RTY:close","Working orders: "..table.concat(working,","))
  assert(a.Positions.RTY.Quantity==1 and a.Positions.RTY.Stop==old.Positions.RTY.Stop and e.Books.RTY.Spec.CloseOnly,"Retired position keeps protection")
  assert(not e:Submit(id,{Contract="RTY",Direction=1,Quantity=1,Type="Market"}),"Retired market opened new exposure")
  local kinds={}
  for _,agent in ipairs(p.Agents) do kinds[agent.Key]=(kinds[agent.Key] or 0)+1 end
  local per=Config.MakersPerInstrument+Config.ParticipantsPerInstrument+Config.WhalesPerInstrument
  assert(not kinds.ES and kinds.BX==per and kinds.BG==per and kinds.RTY==per,"Participants per market")
  local nextSnapshot=C.Capture(e,p);local r,q=C.Restore(C.Decode(C.Encode(nextSnapshot)),Config)
  assert(#q.Agents==#p.Agents and table.concat(r.Config.ContractOrder,",")==order,"Restore duplicated markets")
  for _=1,400 do p:Step() end
  assert(e.Books.BG.Last and e.Books.BG.Volume>0,"BG has no market activity")
  local ok,fill=F.Perform(e,id,{Action="Place",Contract="BG",Direction=1,Quantity=1,Type="Market",StopDollars=200,TargetDollars=400})
  assert(ok and fill.Filled==1 and a.Positions.BG.Stop and a.Positions.BG.Target,"BG trade with protection")
  assert(F.Perform(e,id,{Action="Close",Contract="BG"}) and not a.Positions.BG and a.History[1].Contract=="BG")
  if a.Positions.RTY then assert(F.Perform(e,id,{Action="Close",Contract="RTY"}));assert(not a.Positions.RTY and a.History[1].Contract=="RTY") end
  e:Audit();r:Audit()
  return {Markets=order,Participants=#p.Agents}
 end)
 test("Speed 18 executes all 72 scheduler steps/sec and intrastep OCO crossings latch",function()
  local e,f,a=fresh();submit(e,"maker","BX",-1,1,5825);submit(e,a.Id,"BX",1,1,nil,{StopTicks=4,TargetTicks=8})
  submit(e,"maker","BX",1,1,5824);submit(e,"taker","BX",-1,1)
  submit(e,"maker","BX",-1,1,5827);submit(e,"taker","BX",1,1)
  assert(a.Positions.BX.Triggered=="Stop loss" and not a.Positions.BX.Target)
  submit(e,"maker","BX",1,1,5826);e:ProcessStops();assert(not a.Positions.BX)
  local accumulator=0 local steps=0
  for _=1,200 do accumulator+=(1/60)*Config.SimulationSpeed
   local frameSteps=0 while accumulator+1e-9>=Config.StepSeconds and frameSteps<Config.MaxCatchupSteps do
    accumulator-=Config.StepSeconds;steps+=1;frameSteps+=1;e:AdvanceClock(Config.StepSeconds)
   end
  end
  assert(steps==240);near(e.Time,60);assert(Config.BroadcastSeconds==.1 and Config.Volatility==1)
 end)
 return results
end
return T

