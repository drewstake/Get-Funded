local Default=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Checkpoint=require(script.Parent.WorldCheckpoint)
local Lease=require(script.Parent.WorldLease)
local World=require(script.Parent.WorldService)
local Settings=require(script.Parent.WorldConfig)
local F=require(script.Parent.FundedAccounts)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local Tests={}
local function clone(v)
 if type(v)~="table"then return v end
 local r={}for k,x in pairs(v)do r[k]=clone(x)end return r
end
local function equal(a,b,path)
 path=path or "state"
 assert(type(a)==type(b),path.." type differs")
 if type(a)~="table"then assert(a==b,path.." differs: "..tostring(a).." / "..tostring(b))return end
 for k,v in pairs(a)do equal(v,b[k],path.."."..tostring(k))end
 for k in pairs(b)do assert(a[k]~=nil,path.." added key "..tostring(k))end
end
local function store()
 local s={}
 function s:UpdateAsync(_,callback)
  if self.Fail then error("Injected storage outage")end
  local value=callback(clone(self.Value))
  if value==nil then return nil end
  self.Value=clone(value)return clone(value)
 end
 function s:GetAsync()if self.Fail then error("Injected storage outage")end return clone(self.Value)end
 return s
end
function Tests.Run()
 local report={} local function test(name,fn)
  local ok,result=pcall(fn)table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})
 end
 test("Fresh markets retain makers, ordinary traders and whales alongside scalpers",function()
  local e=Engine.new(Default,4102)local p=Participants.new(e)
  assert(Default.MakersPerInstrument==10 and Default.ParticipantsPerInstrument==36 and Default.WhalesPerInstrument==3)
  for _,key in ipairs(Default.ContractOrder) do
   local makers,traders,whales,scalpers=0,0,0,0
   for _,a in ipairs(p.Agents) do if a.Key==key then
    if a.Kind=="Maker" then makers+=1 elseif a.Kind=="Whale" then whales+=1 elseif a.Kind=="Scalper" then scalpers+=1 elseif a.Kind~="Reserve"then traders+=1 end
   end end
   assert(makers==10 and traders==36 and whales==3 and scalpers==Default.ScalpersPerInstrument,key.." population differs")
  end
  e:Audit();return "10 makers, 36 ordinary traders, 3 whales and 18 scalpers per active market"
 end)
 test("Older worlds gain makers once, preserving the tape, accounts and retired markets",function()
  local old=clone(Default);old.MakersPerInstrument=5;old.MakerPopulationVersion=nil
  old.Contracts.RTY=clone(old.LegacyContracts.RTY);table.insert(old.ContractOrder,"RTY")
  local e=Engine.new(old,4103)local p=Participants.new(e)
  local f=F.new(e,L,old);f:Start("makers");local id=f:Owner("makers")
  for _=1,240 do p:Step() end
  assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=2,Type="Market",StopTicks=400,TargetTicks=500}))
  assert(e:Submit(id,{Contract="BT",Direction=-1,Quantity=1,Type="Limit",Price=(e.Books.BT.Last+100)*old.Contracts.BT.Tick}))
  local before=Checkpoint.Capture(e,p)
  local restored,agents=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(before)),Default)
  local after=Checkpoint.Capture(restored,agents)
  for key,value in pairs(before.Engine) do if key~="Accounts" then equal(value,after.Engine[key],"engine."..key) end end
  for i,a in ipairs(before.Engine.Accounts) do equal(a,after.Engine.Accounts[i],"account."..a.Id) end
  for key,value in pairs(before.Population) do
   if key~="Agents" and key~="RandomState" then equal(value,after.Population[key],"population."..key) end
  end
  for i,a in ipairs(before.Population.Agents) do equal(a,after.Population.Agents[i],"agent."..a.Id) end
  assert(#after.Engine.Accounts==#before.Engine.Accounts+15 and #agents.Agents==#p.Agents+15)
  local counts={}
  for i,a in ipairs(agents.Agents) do
   if a.Kind=="Maker" then counts[a.Key]=(counts[a.Key] or 0)+1 end
   if i>#p.Agents then assert(a.Kind=="Maker" and a.Next>restored.Time and a.Next<=restored.Time+18,"Maker acted during restore") end
  end
  for _,key in ipairs(Default.ContractOrder) do assert(counts[key]==10,key.." maker top-up missing") end
  assert(counts.RTY==5,"Retired market population changed")
  assert(after.Config.MakerPopulationVersion==Default.MakerPopulationVersion and after.Config.MakersPerInstrument==10)
  equal(before,Checkpoint.Capture(e,p),"input snapshot")
  local resumed,rp=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(after)),Default)
  equal(after,Checkpoint.Capture(resumed,rp),"second restore")
  for _=1,200 do agents:Step();rp:Step() end
  equal(Checkpoint.Capture(restored,agents),Checkpoint.Capture(resumed,rp),"resumed future")
  local quoted=false
  for _,o in pairs(restored.Orders) do
   for i=#p.Agents+1,#agents.Agents do if o.Owner==agents.Agents[i].Id then quoted=true end end
  end
  assert(quoted,"New makers never posted liquidity")
  restored:Audit();resumed:Audit()
  return "15 makers added once; history, FIFO orders, positions, funds and retired participants preserved; deterministic restart and new quotes verified"
 end)
 test("Maker migration counts renamed agents and avoids occupied account ids",function()
  local old=clone(Default);old.MakersPerInstrument=5;old.MakerPopulationVersion=nil
  old.Contracts.ES=old.Contracts.BX;old.Contracts.BX=nil;old.ContractOrder[1]="ES"
  local e=Engine.new(old,4104)local p=Participants.new(e)
  e:AddAccount("bot:BX:Maker:6",123456,200,0.8,false)
  for _=1,80 do p:Step() end
  local original=clone(e.Accounts["bot:BX:Maker:6"])
  local restored,agents=Checkpoint.Restore(Checkpoint.Capture(e,p),Default)
  equal(original,restored.Accounts[original.Id],"occupied account")
  local count,ids=0,{}
  for _,a in ipairs(agents.Agents) do
   assert(not ids[a.Id],"Duplicate maker id");ids[a.Id]=true
   if a.Key=="BX" and a.Kind=="Maker" then count+=1 end
  end
  assert(count==10 and ids["bot:ES:Maker:1"] and ids["bot:BX:Maker:7"] and not ids[original.Id])
  local state=agents.Random.State
  assert(agents:EnsureMakers(Default.ContractOrder,10)==0 and agents.Random.State==state,"Repeated top-up changed population or random state")
  restored:Audit();return "Renamed maker ids retained; occupied account untouched; repeat top-up is a no-op"
 end)
 test("Compressed checkpoint resumes the identical future with identical actions",function()
  local e=Engine.new(Default,92041)local p=Participants.new(e)
  local f=F.new(e,L,Default);f:Start("test");local id=f:Owner("test")
  for _=1,500 do p:Step()end
  assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=2,Type="Market",StopTicks=80,TargetTicks=100}))
  local before=Checkpoint.Capture(e,p)local encoded=Checkpoint.Encode(before)
  local http=game:GetService("HttpService")encoded=http:JSONDecode(http:JSONEncode(encoded))
  local restored,agents=Checkpoint.Restore(Checkpoint.Decode(encoded),Default)
  equal(before,Checkpoint.Capture(restored,agents))
  for i=1,700 do
   if i==200 or i==480 then
    local request={Contract="BT",Direction=i==200 and -1 or 1,Quantity=1,Type="Market"}
    local ok1,r1=e:Submit(id,request)local ok2,r2=restored:Submit(id,request)
    equal({ok1,r1},{ok2,r2})
   end
   p:Step()agents:Step()
  end
  equal(Checkpoint.Capture(e,p),Checkpoint.Capture(restored,agents)) e:Audit()restored:Audit()
  return {Step=e.Step,Trades=e.NextTrade,Hash=e.TradeHash,CompressedBytes=#encoded.Payload,RawBytes=encoded.RawBytes}
 end)
 test("Restored book retains FIFO, partial fills, cancellations, account funds and protection",function()
  local e=Engine.new(Default,19)
  -- Player and participant limits share the same preserved FIFO.
  for _,id in ipairs({"a","b","c"})do e:AddAccount(id,1000000,500,0.8,false)end
  local f=F.new(e,L,Default);f:Start("w");local player=e.Accounts[f:Owner("w")]
  local function order(who,side,qty,price)
   local ok,r=e:Submit(who,{Contract="BX",Direction=side,Quantity=qty,Type=price and "Limit"or"Market",Price=price,StopTicks=8,TargetTicks=12})
   assert(ok,tostring(r))return r
  end
  local first=order("a",-1,4,5825)local second=order("b",-1,3,5825)
  order("c",1,2)
  local waiting=e:Submit(player.Id,{Contract="BX",Direction=1,Quantity=2,Type="Limit",Price=5800}) assert(waiting)
  local p=setmetatable({Engine=e,Config=Default,Random=Participants.RNG.new(19),Agents={}},Participants)
  local r=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(Checkpoint.Capture(e,p))),Default)
  assert(r.Orders[first.Id].Remaining==2 and r.Orders[second.Id].Remaining==3)
  assert(r.Books.BX.Asks[1].Orders[1]==r.Orders[first.Id],"Restored order references are detached")
  local account=r.Accounts.c local originalBase=account.Balance
  assert(r:AddAccount("c",50000,40,0.8,true)==account and account.Balance==originalBase,"Rejoin reset funds")
  assert(account.Positions.BX.Stop and account.Positions.BX.Target)
  local ok,fill=r:Submit("c",{Contract="BX",Direction=1,Quantity=3,Type="Market"})
  assert(ok and fill.Filled==3 and r.Trades[1].Seller=="a"and r.Trades[2].Seller=="b")
  assert(not r.Orders[first.Id]and r.Orders[second.Id].Remaining==2)
  assert(r:Cancel("b",second.Id))assert(#r.Books.BX.Asks==0)
  local saved for id,o in pairs(r.Orders)do if o.Owner==player.Id then saved=o end end
  assert(saved and saved.Remaining==2 and #r.Books.BX.Bids==1 and r.Books.BX.Bids[1].Orders[1]==saved,"Player limit did not restore into the book")
  r:Audit()return "FIFO object identity, partial residual, cancellation, persistent account and SL/TP passed"
 end)
 test("Ownership is exclusive; takeover fences stale writes and preserves the checkpoint",function()
  local s=store()local now=100 local function clock()return now end
  local function owner(id)return Lease.new(s,Settings,{Token=id,WorldId=id,JobId=id,PlaceId=1},clock)end
  local a,b=owner("a"),owner("b")assert(a:Claim())assert(not b:Claim())
  a:Commit({Marker="saved"},18,false)now=191
  assert(not a:Valid())assert(b:Claim())assert(b.Record.Checkpoint.Marker=="saved")
  assert(not pcall(function()a:Commit({Marker="stale"},999,false)end))
  assert(s.Value.Owner=="b"and s.Value.SavedStep==18 and s.Value.Checkpoint.Marker=="saved")
  b:Commit({Marker="new"},22,true)local c=owner("c")assert(c:Claim())
  assert(c.Record.SavedStep==22 and c.Record.Checkpoint.Marker=="new")
  assert(not pcall(function()c:Commit({Marker="backwards"},21,false)end))
  return "Single writer, expired lease, stale generation, release and monotonic checkpoint verified"
 end)
 test("World service restart restores live accounts, candles and next random draw without a new auction",function()
  local c=table.clone(Default)c.WarmupSeconds=12
  local s=store()local now=1000
  local function make(job)return World.new(c,{Studio=false,PlaceId=123,JobId=job,Store=s,Now=function()return now end,CanOwn=true})end
  local a=make("first")a:Open()assert(a:CanRun(),a.LastError)
  local f=F.new(a.Engine,L,c);f:Start("7");local id=f:Owner("7")
  a.Engine:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopTicks=50,TargetTicks=100})
  for _=1,40 do a.Population:Step()end
  local expected=Checkpoint.Capture(a.Engine,a.Population)
  assert(a:Close())local b=make("second")b:Open()assert(b:CanRun(),b.LastError)
  equal(expected,Checkpoint.Capture(b.Engine,b.Population))
  local follower=make("third")follower:Open()
  assert(follower.Mode=="Following"and not follower.Engine and not follower:CanRun())
  assert(follower.Owner.JobId=="second")
  return {RestoredStep=b.Engine.Step,RestoredTrades=b.Engine.NextTrade,Mode=b.Mode,Follower=follower.Mode}
 end)
 test("Storage outage pauses orders and never creates a replacement market",function()
  local c=table.clone(Default)c.WarmupSeconds=1
  local s=store()local now=2000 local opts={Studio=false,PlaceId=123,JobId="outage",Store=s,Now=function()return now end,CanOwn=true}
  s.Fail=true local unavailable=World.new(c,opts)unavailable:Open()
  assert(unavailable.Mode=="Unavailable"and not unavailable.Engine and not unavailable:CanRun())
  s.Fail=false local w=World.new(c,opts)w:Open()assert(w:CanRun())
  local step=w.Engine.Step s.Fail=true assert(not w:Save(false))assert(not w:CanRun())
  assert(w.Engine.Step==step and s.Value.SavedStep==step)
  s.Fail=false now+=Settings.RetrySeconds w:Maintain()assert(w:CanRun())
  now=w.Lease.Record.LeaseUntil+1 assert(not w:CanRun())
  return "Initial failure fails closed; save failure pauses; retry recovers; expired owner cannot trade"
 end)
 test("Corrupt or incompatible checkpoints are rejected instead of reseeded",function()
  local e=Engine.new(Default,202)local p=Participants.new(e)
  local snapshot=Checkpoint.Capture(e,p)local encoded=Checkpoint.Encode(snapshot)
  encoded.Digest="bad"assert(not pcall(Checkpoint.Decode,encoded))
  snapshot.Config.Contracts.BX.Tick=1
  assert(not pcall(Checkpoint.Restore,snapshot,Default))
  return "Checksum and instrument-schema validation passed"
 end)
 return report
end
return Tests
