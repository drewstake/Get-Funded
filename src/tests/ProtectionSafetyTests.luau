-- Disposable exchanges and fake storage only; never access a live player or DataStore.
local E=require(script.Parent.MarketEngine)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local F=require(script.Parent.FundedAccounts)
local Protect=require(script.Parent.ProtectiveOrders)
local C=require(script.Parent.TestMarkets).ThreeMarkets()
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Prices=require(game.ReplicatedStorage.MarketReign.TradeProtection)
local World=require(script.Parent.WorldService)
local Lease=require(script.Parent.WorldLease)
local Settings=require(script.Parent.WorldConfig)
local Fake=require(script.Parent.TestDataStore)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function same(a,b)
 assert(type(a)==type(b),"Different types")
 if type(a)~="table"then assert(a==b,"Different values: "..tostring(a).." / "..tostring(b));return end
 for k,v in pairs(a)do same(v,b[k])end;for k in pairs(b)do assert(a[k]~=nil,"Extra key: "..tostring(k))end
end
local function fresh(key,price)
 local c=clone(C);c.BotPopulation=nil;c.WarmupSeconds=0
 if price then c.Contracts[key].Last=price end
 local e=E.new(c,19381);local f=F.new(e,L,c);f:Start("101");f:Start("102")
 e:AddAccount("maker",1e9,10000,.9,false);e:AddAccount("taker",1e9,10000,.9,false)
 return e,f,e.Accounts[f:Owner("101")],e.Accounts[f:Owner("102")]
end
local function offer(e,key,side,qty,price,owner)
 local ok,r=e:Submit(owner or "maker",{Contract=key,Direction=side,Quantity=qty,Type="Limit",Price=price})
 assert(ok,tostring(r));return r
end
local function capture(e)
 return CP.Capture(e,setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(19381),Agents={}},P))
end
local function roundtrip(e)
 local restored,p=CP.Restore(CP.Decode(CP.Encode(capture(e))),e.Config)
 restored:Audit();return restored,p
end
local function unchanged(before,e)
 local after=capture(e)
 for _,key in ipairs({"Accounts","Profiles","Books","Orders","PendingStops","NextOrder","NextTrade","TotalVolume","TradeHash"})do
  same(before.Engine[key],after.Engine[key])
 end
end
local function open(e,a,key,side,target)
 local spec=e.Books[key].Spec;local price=(e.Books[key].Last or e.Books[key].Reference)*spec.Tick
 offer(e,key,-side,100,price)
 local ok,r=e:Submit(a.Id,{Contract=key,Direction=side,Quantity=1,Type="Market",StopTicks=8,TargetDollars=target or 1500})
 assert(ok and r.Filled==1,tostring(r));return a.Positions[key]
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,r=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and(r or "Passed")or tostring(r)})end
 for _,key in ipairs(C.ContractOrder)do for _,kind in ipairs({"Market","Limit","Stop"})do
  test(key.." "..kind..": invalid dollar targets reject before orders, fills or ledger changes",function()
   local e,_,a=fresh(key);local spec=e.Books[key].Spec
   local price=spec.Last-(kind=="Stop"and spec.Tick or 0)
   offer(e,key,1,100,spec.Last)
   for _,amount in ipairs({0,-1,.001,math.huge,0/0,1e9+1,"1000",false,{},price*spec.Multiplier,(price+spec.Tick)*spec.Multiplier,1000000})do
    local before=capture(e)
    local ok,message=e:Submit(a.Id,{Contract=key,Direction=-1,Quantity=1,Type=kind,Price=kind~="Market"and price or nil,TargetDollars=amount})
    assert(not ok and type(message)=="string","Invalid target accepted: "..tostring(amount));unchanged(before,e)
   end
   e:Audit()
  end)
  test(key.." "..kind..": tick-based zero/negative targets cannot bypass validation",function()
   local e,_,a=fresh(key);local spec=e.Books[key].Spec
   local price=spec.Last-(kind=="Stop"and spec.Tick or 0);offer(e,key,1,100,spec.Last)
   for _,ticks in ipairs({math.round(price/spec.Tick),math.round(price/spec.Tick)+1})do
    local before=capture(e)
    assert(not e:Submit(a.Id,{Contract=key,Direction=-1,Quantity=1,Type=kind,Price=kind~="Market"and price or nil,TargetTicks=ticks}))
    unchanged(before,e)
   end
  end)
 end end
 test("Ticket preview rejects impossible target prices but preserves large stop intentions",function()
  local spec=C.Contracts.BX
  assert(not Prices.Resolve(spec,1,1000000,spec.Last,-1,"Target"))
  assert(Prices.Resolve(spec,1,1000000,spec.Last,1,"Target").Price>spec.Last)
  assert(Prices.Resolve(spec,1,1000000,spec.Last,1,"Stop").Price<0)
 end)
 test("A rejected short target leaves another player's target working and future targets executable",function()
  local e,_,a,b=fresh("BX");local p=open(e,b,"BX",1,50);local target=p.TargetOrder
  local before=capture(e)
  assert(not F.Perform(e,a.Id,{Action="Place",Contract="BX",Direction=-1,Quantity=1,Type="Market",TargetDollars=1000000}))
  unchanged(before,e);assert(not e.SyncingProtection and e.Orders[target])
  offer(e,"BX",1,100,p.Target,"taker");e:ProcessStops();assert(not b.Positions.BX and b.History[1].Reason=="Take profit")
  local nextP=open(e,a,"BT",-1,100);assert(e.Orders[nextP.TargetOrder]);roundtrip(e)
 end)
 test("The smallest positive short target and normal long/short targets still save and restore",function()
  for _,key in ipairs(C.ContractOrder)do
   local e,_,a,b=fresh(key);local spec=e.Books[key].Spec
   local p=open(e,a,key,-1,(spec.Last-spec.Tick)*spec.Multiplier)
   assert(math.abs(p.Target-spec.Tick)<1e-6 and e.Orders[p.TargetOrder])
   local q=open(e,b,key,1,1500);assert(e.Orders[q.TargetOrder])
   local r=roundtrip(e);assert(r.Accounts[a.Id].Positions[key].Target==p.Target and r.Accounts[b.Id].Positions[key].Target==q.Target)
  end
 end)
 test("Delayed sliced entries recheck the actual fill price before creating a negative target",function()
  local e,_,a=fresh("BX",10)
  local ok,r=e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",Execution="Sliced",TargetDollars=487.5})
  assert(ok and r.Queued and r.Filled==0)
  offer(e,"BX",1,100,9.75)
  local volume=e.TotalVolume;e:ProcessPlayerOrders()
  assert(not a.Positions.BX and e.TotalVolume==volume and not e.Orders[r.Id],"Invalid delayed target filled")
  assert(not e.SyncingProtection);roundtrip(e)
 end)
 for _,execution in ipairs({"Immediate","Sliced"})do
  test(execution.." stop entry rejects a now-impossible target when triggered",function()
   local e,_,a=fresh("BX",10)
   local ok,r=e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Stop",Price=9.75,Execution=execution,TargetDollars=475})
   assert(ok and r.Filled==0)
   offer(e,"BX",1,100,9.5)
   assert(e:Submit("taker",{Contract="BX",Direction=-1,Quantity=1,Type="Market"}))
   assert(e.Orders[r.Id].Triggered~=nil);local volume=e.TotalVolume;local balance=a.Balance
   e:ProcessStops()
   assert(not a.Positions.BX and not e.Orders[r.Id]and e.TotalVolume==volume and a.Balance==balance)
   roundtrip(e)
  end)
 end
 test("An invalid limit amendment preserves its original price, quantity and FIFO",function()
  local e,_,a=fresh("BX",10)
  local ok,r=e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=10.25,TargetDollars=500})
  assert(ok and r.Remaining==1);local before=capture(e)
  assert(not e:AmendOrder(a.Id,{Contract="BX",OrderId=r.Id,ExpectedPrice=10.25,ExpectedQuantity=1,Price=10}))
  unchanged(before,e);roundtrip(e)
 end)
 test("A reversing order with an impossible target cannot close or debit either counterparty",function()
  local e,_,a=fresh("BX");open(e,a,"BX",1,50)
  offer(e,"BX",1,100,C.Contracts.BX.Last)
  local before=capture(e)
  assert(not e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=2,Type="Market",TargetDollars=1000000}))
  unchanged(before,e);roundtrip(e)
 end)
 test("Resting entries recheck targets after their original position closes",function()
  local e,_,a=fresh("BX",10);local p=open(e,a,"BX",-1,12.5)
  -- Scale-ins keep the existing target. The same order must not open a new invalid position later.
  local ok,r=e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=10.25,TargetDollars=1000000})
  assert(ok and r.Remaining==1);e:CancelAll("maker")
  offer(e,"BX",-1,100,p.Target,"taker");e:ProcessStops();assert(not a.Positions.BX)
  e:CancelAll("taker");local volume=e.TotalVolume
  offer(e,"BX",1,1,10.25,"taker")
  assert(not a.Positions.BX and e.TotalVolume==volume and not e.Orders[r.Id],"Stale invalid entry filled")
  roundtrip(e)
 end)
 test("One synchronization failure keeps retry work, clears its guard, and does not starve another player",function()
  local e,_,a,b=fresh("BX");local p=open(e,a,"BX",1,1500);local q=open(e,b,"BT",-1,1500)
  e:Cancel(a.Id,p.TargetOrder);e:Cancel(b.Id,q.TargetOrder)
  local submit=e.Submit
  e.Submit=function(self,id,req,internal)
   if id==a.Id and internal and internal.Protection=="Take profit"then error("Injected target failure")end
   return submit(self,id,req,internal)
  end
  local ok=Protect.Sync(e,true)
  assert(ok==false and not e.SyncingProtection and e.ProtectionDirty[a.Id].BX)
  assert(e.Orders[q.TargetOrder],"Another player's target was starved")
  e.Submit=submit;assert(Protect.Sync(e,true));assert(e.Orders[p.TargetOrder]and not e.SyncingProtection)
  roundtrip(e)
 end)
 for _,bad in ipairs({0,-14175.25})do
  test("V23 invalid target "..bad.." restores without resetting balances, positions, or another player's target",function()
   local e,f,a,b=fresh("BX");local p=open(e,a,"BX",-1,1500);local q=open(e,b,"BT",1,1500)
   e:Cancel(a.Id,p.TargetOrder);p.TargetOrder=nil;p.Target=bad
   local saved=capture(e);saved.Version=23;local original=clone(saved)
   local r,rp=CP.Restore(CP.Decode(CP.Encode(saved)),e.Config);local recovered=r.Accounts[a.Id].Positions.BX
   same(saved,original)
   assert(recovered and recovered.Id==p.Id and recovered.Quantity==p.Quantity and recovered.Entry==p.Entry and recovered.Stop==p.Stop)
   assert(recovered.Target==nil and recovered.TargetOrder==nil and recovered.TargetRepair.PreviousTarget==bad)
   assert(r.Accounts[a.Id].Balance==a.Balance and r.Accounts[a.Id].Realized==a.Realized and r.Accounts[a.Id].CashFlow==a.CashFlow)
   same(r.Accounts[b.Id],b);same(r.Orders[q.TargetOrder],e.Orders[q.TargetOrder])
   assert(r.TotalVolume==e.TotalVolume and r.NextTrade==e.NextTrade and not r.SyncingProtection)
   local events=r.Profiles["101"].Events;local notices=0
   for _,ev in ipairs(events)do if ev.Kind=="ProtectionRepaired"then notices+=1 end end;assert(notices==1)
   local again=CP.Restore(CP.Decode(CP.EncodeWorld(r,rp,CP.MaxDecodedBytes)),e.Config)
   same(capture(r).Engine,capture(again).Engine)
   assert(again:AmendProtection(a.Id,{Contract="BX",OrderId=p.Id,Protection="Target",Price=p.Entry-1,Create=true,ExpectedQuantity=1}))
   local target=again.Accounts[a.Id].Positions.BX.TargetOrder;assert(again.Orders[target]);again:Audit()
  end)
 end
 test("Recovery retains an executable stop loss and another player's executable target",function()
  local e,_,a,b=fresh("BX");local p=open(e,a,"BX",-1,1500);local q=open(e,b,"BT",1,50)
  e:Cancel(a.Id,p.TargetOrder);p.TargetOrder=nil;p.Target=-14175.25
  local r=roundtrip(e)
  r:CancelAll("maker")
  offer(r,"BX",-1,100,p.Stop)
  assert(r:Submit("taker",{Contract="BX",Direction=1,Quantity=1,Type="Market"}));r:ProcessStops()
  assert(not r.Accounts[a.Id].Positions.BX and r.Accounts[a.Id].History[1].Reason=="Stop loss")
  offer(r,"BT",1,100,q.Target,"taker");r:ProcessStops()
  assert(not r.Accounts[b.Id].Positions.BT and r.Accounts[b.Id].History[1].Reason=="Take profit")
  roundtrip(r)
 end)
 test("Unexpected protection errors abort restore and leave the saved checkpoint recoverable",function()
  local e,_,a=fresh("BX");local p=open(e,a,"BX",-1,1500)
  e:Cancel(a.Id,p.TargetOrder);p.TargetOrder=nil
  local saved=capture(e);local original=clone(saved);local submit=E.Submit
  E.Submit=function(self,owner,request,internal)
   if internal and internal.Protection=="Take profit"then error("Injected restore failure")end
   return submit(self,owner,request,internal)
  end
  local ok,message=pcall(CP.Restore,saved,e.Config)
  E.Submit=submit
  assert(not ok and tostring(message):find("Cannot restore protective orders",1,true));same(saved,original)
  local restored=CP.Restore(saved,e.Config)
  assert(restored.Orders[restored.Accounts[a.Id].Positions.BX.TargetOrder]);restored:Audit()
 end)
 for _,version in ipairs({23,24,28})do
 test("World save/restart recovers V"..version.." targets, fails closed on storage outage, and saves the repair once",function()
  local e,_,a,b=fresh("BX");local p=open(e,a,"BX",-1,1500);local q=open(e,b,"BT",1,1500)
  e:Cancel(a.Id,p.TargetOrder);p.TargetOrder=nil;p.Target=-14175.25
  local snapshot=capture(e);snapshot.Version=version
  local s=Fake.new()
  local function make(job)return World.new(e.Config,{Studio=false,PlaceId=123,JobId=job,Store=s,Now=function()return 1000 end,CanOwn=true})end
  local seed=make("seed");local lease=Lease.new(s,Settings,seed.Identity,seed.Now)
  local encoded=CP.Encode(snapshot);encoded.Version=version
  assert(lease:Claim());lease:Commit(encoded,e.Step,true)
  local w=make("recovery");w:Open();assert(w:CanRun(),w.LastError)
  assert(w.Engine.Accounts[a.Id].Positions.BX.Target==nil and w.Engine.Accounts[a.Id].Positions.BX.Stop==p.Stop)
  assert(w.Engine.Accounts[a.Id].Balance==a.Balance and w.Engine.Accounts[a.Id].CashFlow==a.CashFlow)
  same(w.Engine.Accounts[b.Id],b);same(w.Engine.Orders[q.TargetOrder],e.Orders[q.TargetOrder])
  assert(w.Lease:ReadCheckpoint().Version==CP.Version)
  local durable=clone(s.Value);s.Fail=true
  assert(not w:Save(false)and not w:CanRun());same(s.Value,durable)
  s.Fail=false;assert(w:Save(false));assert(w:CanRun());assert(w:Close())
  local resumed=make("restart");resumed:Open();assert(resumed:CanRun(),resumed.LastError)
  same(capture(w.Engine).Engine,capture(resumed.Engine).Engine)
  local events=resumed.Engine.Profiles["101"].Events;local notices=0
  for _,ev in ipairs(events)do if ev.Kind=="ProtectionRepaired"then notices+=1 end end
  assert(notices==1);resumed.Engine:Audit();assert(resumed:Close())
 end)
 end
 return rows
end
return Tests
