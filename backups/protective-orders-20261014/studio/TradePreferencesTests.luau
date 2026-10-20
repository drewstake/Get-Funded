local Liquidity=require(script.Parent.TestLiquidity)
-- Isolated exchange/profile tests, including real fills and encoded checkpoint restart.
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Protection=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local Tests={}
local function fresh()
 local e=E.new(C,8912);local f=F.new(e,L,C);f:Join("preferences-test")
 local id=f:Owner("preferences-test");local b=e.Books.BX;b.Last=math.round(C.Contracts.BX.Last/b.Spec.Tick)
 return e,f,id
end
local function trade(e,price)
 e:AddAccount("test-maker",1e9,10000,.99,false);e:AddAccount("test-taker",1e9,10000,.99,false)
 assert(Liquidity.Submit(e,"test-maker",{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=price}))
 assert(Liquidity.Submit(e,"test-taker",{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=price}))
end
local function restore(e)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(8912),Agents={}},P)
 local r=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),C)
 return r,F.new(r,L,C)
end
function Tests.Run()
 local rows={}
 local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 test("Unsaved profiles keep the existing $500/$1500 enabled defaults",function()
  local _,f=fresh();local v=f:View("preferences-test").ProtectionPreferences
  assert(v.StopOn and v.TargetOn and v.StopDollars==500 and v.TargetDollars==1500)
  assert(f:Profile("preferences-test").ProtectionPreferences==nil)
 end)
 test("Both false switches and disabled amounts survive encoded save, new engine and rejoin",function()
  local e,f=fresh();local prefs={StopOn=false,TargetOn=false,StopDollars=123.45,TargetDollars=678.9}
  assert(f:SetProtectionPreferences("preferences-test",prefs));e,f=restore(e);f:Join("preferences-test")
  assert(Protection.SamePreferences(prefs,f:View("preferences-test").ProtectionPreferences))
  prefs.StopDollars=1;assert(f:Profile("preferences-test").ProtectionPreferences.StopDollars==123.45)
 end)
 test("Invalid or incomplete preferences fail atomically; another profile is unchanged",function()
  local _,f=fresh();f:Join("other")
  local value={StopOn=false,TargetOn=true,StopDollars=123.45,TargetDollars=678.9}
  assert(f:SetProtectionPreferences("preferences-test",value))
  for _,bad in ipairs({0,-1,math.huge,0/0,"12",{}})do
   local r=table.clone(value);r.StopDollars=bad;assert(not f:SetProtectionPreferences("preferences-test",r))
  end
  local r=table.clone(value);r.TargetOn=nil;assert(not f:SetProtectionPreferences("preferences-test",r))
  r=table.clone(value);r.StopOn=0;assert(not f:SetProtectionPreferences("preferences-test",r))
  assert(Protection.SamePreferences(value,f:View("preferences-test").ProtectionPreferences))
  assert(f:View("other").ProtectionPreferences.StopDollars==500)
 end)
 test("Updating defaults never amends an open position or an existing working order",function()
  local e,f,id=fresh()
  assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopDollars=500,TargetDollars=1500}))
  local p=e.Accounts[id].Positions.BX;local stop,target=p.Stop,p.Target
  local ok,r=Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=p.Entry-50,StopDollars=500,TargetDollars=1500});assert(ok)
  local order=e.Orders[r.Id];local stopTicks,targetTicks=order.StopTicks,order.TargetTicks
  assert(f:SetProtectionPreferences("preferences-test",{StopOn=false,TargetOn=true,StopDollars=111,TargetDollars=222}))
  assert(p.Stop==stop and p.Target==target and order.StopTicks==stopTicks and order.TargetTicks==targetTicks)
  assert(Liquidity.Perform(e,id,{Action="Close",Contract="BX"}))
  assert(f:View("preferences-test").ProtectionPreferences.StopDollars==111);e:Audit()
 end)
 for _,side in ipairs({1,-1})do for _,reason in ipairs({"Take profit","Stop loss"})do
  test(reason.." on "..(side==1 and "long"or "short").." announces once only after execution",function()
   local e,f,id=fresh()
   assert(Liquidity.Submit(e,id,{Contract="BX",Direction=side,Quantity=1,Type="Market",StopDollars=100,TargetDollars=200}))
   local p=e.Accounts[id].Positions.BX;local price=reason=="Take profit"and p.Target or p.Stop
   assert(not f:TakeEvents("preferences-test"));trade(e,price)
   assert(p.Triggered==reason and not f:TakeEvents("preferences-test"),"A price trigger is not a fill")
   Liquidity.Offer(e,"BX",side,1,price)
   e:ProcessStops();assert(not e.Accounts[id].Positions.BX)
   local events=f:TakeEvents("preferences-test");assert(#events==1,"Close should not add progression toasts")
   local ev=events[1];assert(ev.Kind=="TradeClosed"and ev.Reason==reason and ev.Account==id and ev.TradeId==e.Accounts[id].History[1].TradeId)
   e:ProcessStops();assert(not f:TakeEvents("preferences-test"));e:Audit()
  end)
 end end
 test("Manual close has an execution identity; rejected close emits nothing",function()
  local e,f,id=fresh()
  assert(not Liquidity.Perform(e,id,{Action="Close",Contract="BX"}));assert(not f:TakeEvents("preferences-test"))
  for _=1,25 do
   assert(Liquidity.Submit(e,id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
   assert(Liquidity.Perform(e,id,{Action="Close",Contract="BX"}))
   local events=f:TakeEvents("preferences-test");assert(#events==1 and events[1].Reason=="Player close"and events[1].TradeId)
  end
  assert(f:Profile("preferences-test").Awards.FirstTrade,"Titles still earned without expanding the toast")
 end)
 return rows
end
return Tests
