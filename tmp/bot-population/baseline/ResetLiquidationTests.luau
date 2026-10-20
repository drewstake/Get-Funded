-- Isolated exchanges only. Resets must close through real counterparties before any new grant.
local E=require("./MarketEngine")
local F=require("./FundedAccounts")
local C=require("./MarketConfig")
local L=require("./ProgressionConfig")
local CP=require("./WorldCheckpoint")
local P=require("./Participants")
local Policy=require("./PlayerExecution")
local T=require("./TestLiquidity")
local Tests={}
local uid="reset-test"
local function fresh()
 local e=E.new(C,892);local config=table.clone(L);config.StartingBalance=145000
 local f=F.new(e,config,C);f:Join(uid)
 return e,f,e.Accounts[f:Owner(uid)]
end
local function open(e,a,key,side,qty,price)
 T.Offer(e,key,-side,qty,price)
 local ok,r=e:Submit(a.Id,{Contract=key,Direction=side,Quantity=qty,Type="Market",StopTicks=8,TargetTicks=16})
 assert(ok and r.Filled==qty,tostring(r));return a.Positions[key]
end
local function step(e,f)
 e:AdvanceClock(.25);e:ProcessPlayerOrders();f:ProcessResets();e:Audit()
end
local function restore(e,f)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(892),Agents={}},P)
 local saved=CP.Capture(e,pop);assert(saved.Version==14)
 local r=CP.Restore(CP.Decode(CP.Encode(saved)),C)
 return r,F.new(r,f.Config,C)
end
function Tests.Run()
 local rows={};local function test(name,fn)local ok,err=pcall(fn);table.insert(rows,{Name=name,Passed=ok,Detail=ok and "Passed"or tostring(err)})end
 for _,side in ipairs({1,-1})do
  test(side..": 145-contract reset sweeps real depth and records market impact and loss",function()
   local e,f,a=fresh();open(e,a,"BX",side,145,5825)
   T.Offer(e,"BX",side,45,5825-side*.25);T.Offer(e,"BX",side,100,5825-side*.5)
   e.Books.BX.FairReference=5825/.25
   local state=Policy.State(e);state.Owners[uid..":"..(-side)]=C.PlayerExecution.OwnerContracts
   state.Markets["BX:"..(-side)]={Limit=0,Used=0}
   local volume,run=e.TotalVolume,f:Profile(uid).Run
   assert(f:ResetAccount(uid,a.Id));local p=f:Profile(uid);local nextA=e.Accounts[p.Account]
   assert(p.Run==run+1 and not p.PendingReset and nextA.Balance==145000)
   assert(not e.Accounts[a.Id]and not e.Accounts["house:reset-exposure"])
   assert(e.TotalVolume==volume+145 and e.Books.BX.Last*.25==5825-side*.5)
   local history=e.Accounts["player:"..uid..":single-history"]
   assert(history.Realized==-(45*.25+100*.5)*50 and history.History[1].Reason=="Account reset")
   assert(history.CompletedTrades==2 and not next(history.Positions))
   assert(state.Markets["BX:"..(-side)].Used==0 and state.Owners[uid..":"..(-side)]==C.PlayerExecution.OwnerContracts)
   assert(not f:ResetAccount(uid,a.Id),"Stale reset targeted new account");e:Audit()
  end)
  test(side..": empty then partial liquidity retains old account and survives reload/disconnect",function()
   local e,f,a=fresh();open(e,a,"BX",side,5,5825);local id=a.Id;local p=f:Profile(uid)
   assert(e:Submit(id,{Contract="BT",Direction=1,Quantity=1,Type="Limit",Price=C.Contracts.BT.Last-100}))
   assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Stop",Price=5835}))
   local run,volume=p.Run,e.TotalVolume;assert(f:ResetAccount(uid,id))
   assert(p.Run==run and p.PendingReset and a.Resetting and a.Positions.BX.Quantity==5)
   assert(e.TotalVolume==volume and not a.Positions.BX.Target and not a.Positions.BX.Stop)
   local count=0;for orderId in pairs(a.OpenOrders)do local o=e.Orders[orderId];count+=1;assert(o.Protection=="Account reset"and o.ReduceOnly and o.Queued)end
   assert(count==1 and p.Limits.Reset.Tokens==L.ResetLimits.Burst-1)
   local view=f:View(uid);assert(view.Resetting and view.Accounts[1].Closing and not view.Accounts[1].Usable and not view.CanRestart)
   for _=1,4 do assert(f:ResetAccount(uid,id));step(e,f)end
   assert(p.Run==run and p.Limits.Reset.Tokens==L.ResetLimits.Burst-1)
   local snapshot=e:Snapshot(id,"BX","1m",true)
   assert(snapshot.Capacity.BX.Buy==0 and snapshot.Orders[1].Kind:find("Reset liquidation",1,true))
   assert(snapshot.Orders[1].Status:find("5 remaining",1,true))
   for _,req in ipairs({{Action="Place",Contract="BX",Direction=side,Quantity=1,Type="Market"},
    {Action="Close",Contract="BX"},{Action="Cancel",OrderId=a.Positions.BX.ExitOrder},
    {Action="AmendProtection",Contract="BX",OrderId=a.Positions.BX.Id,Protection="Target",Price=5829}})do
    assert(not F.Perform(e,id,req),"Client changed a resetting account")
   end
   assert(not e:Submit(id,{Contract="BX",Direction=-side,Quantity=5,Type="Market",ReduceOnly=true,Protection="Account reset"}))
   T.Offer(e,"BX",side,2,5825-side*.25);step(e,f)
   assert(a.Positions.BX.Quantity==3 and e.TotalVolume==volume+2 and p.Run==run)
   e,f=restore(e,f);p=f:Profile(uid);a=e.Accounts[id]
   assert(a.Resetting and p.PendingReset.Account==id and a.Positions.BX.Quantity==3)
   e:SetConnectedOwners({[id]=true});f:Depart(uid,100);e:SetConnected(id,false)
   step(e,f);assert(p.Run==run and a.Positions.BX.Quantity==3)
   T.Offer(e,"BX",side,3,5825-side*.5);step(e,f)
   assert(p.Run==run+1 and not e.Accounts[id]and not p.PendingReset and not p.Absence and not p.AwaySummary)
   assert(e.TotalVolume==volume+5 and e.Accounts[p.Account].Balance==145000)
   local after=p.Account;for _=1,3 do step(e,f)end;assert(p.Account==after)
   e,f=restore(e,f);assert(f:Owner(uid)==after and not f:Profile(uid).PendingReset);e:Audit()
  end)
 end
 test("Multiple markets must all finish before reset completes",function()
  local e,f,a=fresh();open(e,a,"BX",1,2,5825);open(e,a,"BT",-1,3,C.Contracts.BT.Last)
  T.Offer(e,"BX",1,2,5825);local run=f:Profile(uid).Run
  assert(f:ResetAccount(uid,a.Id));assert(not a.Positions.BX and a.Positions.BT and f:Profile(uid).Run==run)
  T.Offer(e,"BT",-1,3,C.Contracts.BT.Last);step(e,f)
  assert(f:Profile(uid).Run==run+1 and not e.Accounts[a.Id])
 end)
 test("Reset resumes after a snapshot taken flat but before the account grant",function()
  local e,f,a=fresh();open(e,a,"BX",1,1,5825);assert(f:ResetAccount(uid,a.Id))
  T.Offer(e,"BX",1,1,5825);e:ProcessPlayerOrders()
  assert(not next(a.Positions)and f:Owner(uid)==a.Id)
  local run=f:Profile(uid).Run;e,f=restore(e,f);assert(f:Owner(uid)==a.Id)
  f:ProcessResets();assert(f:Profile(uid).Run==run+1);f:ProcessResets();assert(f:Profile(uid).Run==run+1);e:Audit()
 end)
 test("Reset preserves price safeguards and waits instead of inventing liquidity",function()
  local e,f,a=fresh();open(e,a,"BX",1,2,5825)
  local far=5825-(C.PlayerExecution.GuardTicks+10)*.25;e.Books.BX.FairReference=5825/.25
  T.Offer(e,"BX",1,2,far);local volume=e.TotalVolume
  assert(f:ResetAccount(uid,a.Id));assert(a.Positions.BX.Quantity==2 and e.TotalVolume==volume)
  assert(e.Orders[a.Positions.BX.ExitOrder].BlockedReason:find("price safeguard",1,true))
  e.Books.BX.FairReference=far/.25;step(e,f);assert(not e.Accounts[a.Id]and e.TotalVolume==volume+2)
 end)
 test("Equity depletion during reset keeps the reset queued and records the loss",function()
  local e,f,a=fresh();open(e,a,"BX",1,145,5825)
  T.Offer(e,"BX",1,145,5800);assert(f:ResetAccount(uid,a.Id))
  assert(not e.Accounts[a.Id]and e.Accounts[f:Owner(uid)].Balance==145000)
  local history=e.Accounts["player:"..uid..":single-history"]
  assert(history.Realized==-181250 and history.Archive.Blown==1 and history.History[1].Reason=="Account reset")
  e:Audit()
 end)
 test("Flat reset completes immediately; rejected resets do not cancel orders or spend credits",function()
  local e,f,a=fresh();open(e,a,"BX",1,1,5825);local target=a.Positions.BX.TargetOrder
  local p=f:Profile(uid);p.Limits.Reset={Tokens=0,At=e.Time}
  assert(not f:ResetAccount(uid,a.Id)and e.Orders[target]and not p.PendingReset and not a.Resetting)
  p.Limits.Reset=nil;f.Capacity=function()return false end
  assert(not f:ResetAccount(uid,a.Id)and e.Orders[target]and not p.Limits.Reset)
  f.Capacity=nil;T.Offer(e,"BX",1,1,5825);assert(f:ResetAccount(uid,a.Id))
  local nextId=p.Account;assert(f:ResetAccount(uid,nextId));assert(p.Account~=nextId and not p.PendingReset)
  assert(p.Limits.Reset.Tokens==L.ResetLimits.Burst-2);e:Audit()
 end)
 test("Partial TP is replaced by a reset liquidation without orphan exits or double counting",function()
  local e,f,a=fresh();local held=open(e,a,"BX",1,3,5825);local target=held.TargetOrder
  T.Offer(e,"BX",1,1,held.Target);assert(held.Quantity==2)
  assert(f:ResetAccount(uid,a.Id));assert(not e.Orders[target])
  T.Offer(e,"BX",1,2,5824);step(e,f)
  local archive=e.Accounts["player:"..uid..":single-history"]
  assert(archive.CompletedTrades==2 and archive.Realized==100 and not e.Accounts[a.Id])
  e:Audit()
 end)
 return rows
end
return Tests
