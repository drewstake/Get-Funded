-- All fixtures are isolated engines/in-memory stores; this suite never reads or writes player data.
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local R=require(script.Parent.LeaderboardRanking)
local S=require(script.Parent.LeaderboardService)
local CP=require(script.Parent.WorldCheckpoint)
local P=require(script.Parent.Participants)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Ladder=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Tests={}
local function clone(v)if type(v)~="table"then return v end local r={}for k,x in pairs(v)do r[k]=clone(x)end return r end
local function fresh()
 local e=E.new(Config,981);local f=F.new(e,clone(Ladder),Config)
 e:AddAccount("maker",1e9,100000,.99,false)
 return e,f
end
local function order(e,id,side,price,qty)
 local ok,result=e:Submit(id,{Contract="BX",Direction=side,Quantity=qty or 1,Type=price and"Limit"or"Market",Price=price})
 assert(ok,tostring(result));assert(result.Filled>0 or price,"No execution");return result
end
local function roundtrip(e,f,uid,entry,exit,qty)
 f:Start(uid);local id=f:Owner(uid)
 order(e,"maker",-1,entry,qty);order(e,id,1,nil,qty)
 order(e,"maker",1,exit,qty);order(e,id,-1,nil,qty);f:Evaluate(uid)
 return e.Accounts[id]
end
local function memory()
 local store={Reads=0,Writes=0}
 function store:GetAsync()self.Reads+=1;if self.Fail then error("isolated outage")end;return clone(self.Value)end
 function store:UpdateAsync(_,fn)self.Writes+=1;if self.Fail then error("isolated outage")end;local r=fn(clone(self.Value));if r then self.Value=clone(r)end;return clone(r)end
 return store
end
local function projection(rows,seq,time)return {Rows=rows,WorldId="isolated-world",Sequence=seq,SavedAt=time}end
function Tests.Run()
 local report={}
 local function test(name,fn)local ok,result=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and (result or "Passed")or tostring(result)})end
 test("New / open-only accounts excluded; break-even close qualifies",function()
  local e,f=fresh();f:Start("1");local id=f:Owner("1")
  assert(not R.Row(f,"1").Eligible);order(e,"maker",-1,5825);order(e,id,1)
  e.Books.BX.Last=24000;assert(e:Summary(e.Accounts[id]).Unrealized>0)
  assert(R.Row(f,"1").Cents==0 and not R.Row(f,"1").Eligible)
  order(e,"maker",1,5825);order(e,id,-1)
  assert(R.Row(f,"1").Eligible and R.Row(f,"1").Cents==0)
 end)
 test("Negative profit, unlock money and legacy practice excluded",function()
  local e,f=fresh();local a=roundtrip(e,f,"2",5825,5815)
  local p=f:Profile("2");p.ProgressCredit=50000;p.Tiers.F100K={State="Unlocked",Claimed=false,Announced=true}
  local practice=e:AddAccount("player:2:50000",50000,40,.8,true);practice.Realized=999999;practice.History={{Pnl=999999}}
  table.insert(p.Ledger,practice.Id) -- defensive even for an accidentally contaminated old ledger
  f:Evaluate("2");assert(f:Activate("2","F100K"))
  local row=R.Row(f,"2");assert(row.Cents==-50000 and row.Tier=="$100K" and a.Balance==4500)
 end)
 test("Copied lead and followers each count once; duplicate ledger ids ignored",function()
  local e,f=fresh();roundtrip(e,f,"3",5825,5885)
  assert(f:Activate("3","F10K"));assert(f:SetCopy("3",{Enabled=1,Leader="F10K:1",Followers="F5K:1",Sizing="Same"}))
  local id=f:Resolve("3","F10K:1");local plan=f:Plan("3",id)
  local req={Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}
  order(e,"maker",-1,5825,2);local ok,result=F.Perform(e,id,req);assert(ok);assert(f:Mirror(plan,req,ok,result,{}).Copied==1)
  local close={Action="Close",Contract="BX"};local context=f:Context(id,close)
  order(e,"maker",1,5820,2);ok,result=F.Perform(e,id,close);assert(ok);assert(f:Mirror(plan,close,ok,result,context).Copied==1)
  table.insert(f:Profile("3").Ledger,id)
  assert(R.Row(f,"3").Cents==250000,"Expected +3000 minus two $250 losses")
 end)
 test("Restart retains losses; old records and checkpoint roundtrip survive reconnect",function()
  local e,f=fresh();local a=roundtrip(e,f,"4",5825,5700)
  a.Locked=true;assert(f:Restart("4","F5K"));assert(R.Row(f,"4").Cents==-625000)
  roundtrip(e,f,"4",5825,5830);local expected=R.Row(f,"4").Cents;assert(expected==-600000)
  a.CompletedTrades=nil -- old save eligibility comes from retained history / realized result
  local pop=setmetatable({Engine=e,Config=Config,Random=P.RNG.new(98),Agents={}},P)
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),Config)
  local rf=F.new(restored,Ladder,Config);rf:Join("4");rf:Join("4")
  assert(R.Row(rf,"4").Cents==expected and R.Row(rf,"4").Eligible)
  assert(#rf:Profile("4").Ledger==2)
 end)
 test("Eligibility persists when history is trimmed and net profit returns to zero",function()
  local e,f=fresh();local a=roundtrip(e,f,"5",5825,5825)
  a.History={};assert(a.CompletedTrades==1 and R.Row(f,"5").Eligible)
 end)
 test("Top 100, tie cutoff, descending negatives and duplicate users",function()
  local rows={};for id=105,1,-1 do table.insert(rows,{UserId=id,Cents=-100,Eligible=true,Name="Fixture"..id})end
  table.insert(rows,clone(rows[1]));local sorted=R.Sort(rows,100)
  assert(#sorted==100 and sorted[1].UserId==1 and sorted[100].UserId==100)
  assert(sorted[100].Rank==100)
  assert(R.Standing(rows[1],sorted,true).Status=="Outside top 100")
  assert(R.Standing(sorted[2],sorted,false).Rank==nil)
  local changed=clone(sorted[2]);changed.Cents=-200;assert(R.Standing(changed,sorted,true).Rank==nil)
 end)
 test("Atomic projection accepts a loss; stale writers cannot resurrect earnings",function()
  local store=memory();local now=100;local service=S.new({Store=store,Now=function()return now end,Studio=true})
  local rows={{UserId=1,Cents=10000,Eligible=true,Rank=1,Name="Fixture"}}
  service:Queue(projection(rows,2,now));assert(service:Flush());now+=45
  rows=clone(rows);rows[1].Cents=-50000;service:Queue(projection(rows,4,now));assert(service:Flush())
  local stale=S.new({Store=store,Now=function()return now end,Studio=true});stale:Queue(projection({},3,now));assert(stale:Flush())
  assert(store.Value.Sequence==4 and store.Value.Rows[1].Cents==-50000)
  local reconnect=S.new({Store=store,Now=function()return now end,Studio=true})
  local packet=reconnect:Global(rows[1]);assert(packet.Your.Rank==1 and packet.Rows[1].Cents==-50000)
 end)
 test("Batched latest score, cached reads, retry recovery and stale rank suppression",function()
  local store=memory();local now=100;local svc=S.new({Store=store,Studio=true,Now=function()return now end})
  local row={UserId=1,Cents=0,Eligible=true,Name="Fixture",Rank=1}
  for seq=1,10 do svc:Queue(projection({row},seq,now))end
  store.Fail=true;assert(not svc:Flush() and svc.Pending.Sequence==10)
  assert(svc:Global(row).State=="Error")
  now+=10;store.Fail=false;assert(svc:Flush());assert(store.Value.Sequence==10)
  local reads=store.Reads;for _=1,20 do assert(svc:Global(row).Your.Rank==1)end;assert(store.Reads==reads)
  now+=46;store.Fail=true;local stale=svc:Global(row);assert(stale.State=="Stale" and stale.Your.Rank==nil and stale.Rows[1].Rank==nil)
  now+=11;store.Fail=false;assert(svc:Global(row).State=="Ready")
  now+=130;assert(svc:Global(row).State=="Stale")
 end)
 test("A delayed write response cannot regress a newer cached read",function()
  local store=memory();local svc=S.new({Store=store,Studio=true,Now=function()return 100 end})
  function store:UpdateAsync(_,fn)
   local result=fn(nil)
   -- Models a read completing after this write commits, but before its response returns.
   svc.Cache={Version=1,WorldId="isolated-world",Sequence=9,SavedAt=100,Rows={}}
   return result
  end
  svc:Queue(projection({},2,100));assert(svc:Flush());assert(svc.Cache.Sequence==9)
 end)
 test("Only connected players in server standings; names come from server identities",function()
  local e,f=fresh();roundtrip(e,f,"11",5825,5820);roundtrip(e,f,"12",5825,5830)
  local player={UserId=11,Name="ActualUsername",DisplayName="Actual display"}
  local svc=S.new({Store=memory(),Studio=true});local packet=svc:Server(f,{player},player)
  assert(#packet.Rows==1 and packet.Rows[1].UserId==11 and packet.Your.Rank==1 and packet.Rows[1].Name==player.Name)
  assert(#svc:Server(f,{},player).Rows==0)
 end)
 test("Studio and production namespaces are distinct",function()assert(S.Scope(true)=="Studio" and S.Scope(false)=="Live")end)
 test("Leaderboard failure leaves engine orders functional",function()
  local e,f=fresh();local store=memory();store.Fail=true
  local svc=S.new({Store=store,Studio=true});svc:Queue(projection({},1,100));assert(not svc:Flush())
  roundtrip(e,f,"21",5825,5826);assert(R.Row(f,"21").Cents==5000);e:Audit()
 end)
 test("Only committed exchange saves publish; failed saves retain the prior projection",function()
  local World=require(script.Parent.WorldService)
  local config=clone(Config);config.WarmupSeconds=1
  local store=memory();local now=100
  local world=World.new(config,{Studio=true,PlaceId=1,JobId="isolated-test",Store=store,Now=function()return now end})
  world.CaptureProjection=function(e)return R.Capture(F.new(e,Ladder,config))end
  world:Open();assert(world:CanRun());local before=world.DurableProjection
  local f=F.new(world.Engine,Ladder,config);f:Start("500");assert(world:Save(false))
  assert(world.DurableProjection.Sequence>before.Sequence)
  local saved=world.DurableProjection;store.Fail=true;assert(not world:Save(false));assert(world.DurableProjection==saved)
  store.Fail=false;assert(world:Save(false));world.CaptureProjection=function()error("isolated projection failure")end
  assert(world:Save(false) and world:CanRun(),"Leaderboard projection paused trading")
  world:Close()
 end)
 return report
end
return Tests
