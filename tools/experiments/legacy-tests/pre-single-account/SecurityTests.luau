-- Security regressions for the 2026-09-30 audit (F1 reset growth, checkpoint size mismatch, F2 purchase
-- replay pauses, F3 unbounded replies, S1 crossed fallback quotes). Disposable engines and injected
-- in-memory stores only: no DataStore, no live remote, no real purchase, no published server.
local Tests={}
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local P=require(script.Parent.Participants)
local CP=require(script.Parent.WorldCheckpoint)
local W=require(script.Parent.WorldService)
local Settings=require(script.Parent.WorldConfig)
local Ranking=require(script.Parent.LeaderboardRanking)
local ReplyBuffer=require(script.Parent.ReplyBuffer)
local Http=game:GetService("HttpService")

local function clone(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=clone(x) end return r end
local function equal(a,b,label) assert(a==b,(label or "value")..": "..tostring(a).." ~= "..tostring(b)) end
-- Deep comparison with a small tolerance for floating-point sums taken in a different order.
local function close(a,b,path)
 path=path or "value"
 if type(a)=="number" and type(b)=="number" then assert(math.abs(a-b)<=1e-6*math.max(1,math.abs(a)),path..": "..a.." ~= "..b) return end
 assert(type(a)==type(b),path.." type "..type(a).." ~= "..type(b))
 if type(a)~="table" then assert(a==b,path..": "..tostring(a).." ~= "..tostring(b)) return end
 for k,v in pairs(a) do close(v,b[k],path.."."..tostring(k)) end
 for k in pairs(b) do assert(a[k]~=nil,path.." missing "..tostring(k)) end
end
local function ladder(overrides)
 local l=clone(L)
 for group,values in pairs(overrides or {}) do l[group]=l[group] or {} for k,v in pairs(values) do l[group][k]=v end end
 return l
end
local UNLIMITED={ResetLimits={CooldownSeconds=0,Burst=0},PurchaseLimits={Burst=0}}
local function speed() return C.SimulationSpeed end
local function wait(e,seconds) e.Time+=seconds*speed() end -- real seconds of live exchange time
local function exchange(l,uid,options)
 local c=clone(C);c.WarmupSeconds=0
 local e=E.new(c,4821);local f=F.new(e,l or L,c,options)
 if uid then assert(f:Start(uid)) end
 return e,f
end
-- Deterministic closed result on an empty book: both fills use the last trade.
local function result(e,id,value)
 local a=e.Accounts[id];assert(not next(a.Positions),"fixture needs a flat account")
 local b=e.Books.BX;b.Bids={};b.Asks={};b.Last=24000;b.Reference=24000
 assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market"}))
 b.Last+=value/50/b.Spec.Tick
 assert(e:Submit(id,{Contract="BX",Direction=-1,Quantity=1,Type="Market",ReduceOnly=true}))
 if a.Balance<=0 then a.Locked=true;a.Depleted=true;a.DepletedAt=e.Time end
 return a
end
local function snapshotOf(e,f,uid)
 local p=f:Profile(uid)
 return {Stats=f:Stats(uid).Scopes,Earned=f:Earned(p),Row=Ranking.Row(f,uid),Wallet=p.WalletCents,Earned2=p.WalletEarnedCents,
  Spent=p.WalletSpentCents,Purchases=clone(p.Purchases),Tiers=clone(p.Tiers),Progress=f:Progress(p),Stage=f:StageProgress(p)}
end
local function roundtrip(e,l)
 local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(77),Agents={}},P)
 local encoded=Http:JSONDecode(Http:JSONEncode(CP.Encode(CP.Capture(e,pop))))
 local restored=CP.Restore(CP.Decode(encoded),e.Config)
 return restored,F.new(restored,l,restored.Config),encoded
end
local function store()
 local s={Writes=0,Reads=0}
 function s:UpdateAsync(_,fn)
  if self.FailBefore then error("injected storage outage") end
  local value=fn(clone(self.Value))
  if value~=nil then self.Writes+=1;self.Value=clone(value) end
  if self.FailAfter then error("injected lost commit response") end
  return clone(value)
 end
 function s:GetAsync() self.Reads+=1 return clone(self.Value) end
 return s
end
local function world(s,job,clock,settings)
 local c=clone(C);c.WarmupSeconds=0
 return W.new(c,{Studio=false,PlaceId=123,JobId=job,Store=s,Now=clock,CanOwn=true,Settings=settings}),c
end
local function drain() for _=1,3 do task.wait() end end
local function ledgerFootprint(e,p)
 local n=#Http:JSONEncode(p)
 for _,id in ipairs(p.Ledger) do n+=#Http:JSONEncode(e.Accounts[id]) end
 return n
end

function Tests.Run()
 local report={};local function test(name,fn) local ok,detail=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and (detail or "OK") or tostring(detail)}) end

 ------------------------------------------------------------------------------------------ F1 limits
 test("F1: healthy free resets obey the saved cooldown and budget; each rejection changes nothing",function()
  local e,f=exchange(nil,"r1");local p=f:Profile("r1")
  local accepted,rejected=0,0
  local function attempt()
   local before={Ledger=#p.Ledger,Accounts=#e.AccountOrder,Active=p.Active,Revision=p.Revision,Limits=clone(p.Limits)}
   local current=e.Accounts[f:Owner("r1")]
   local ok,message=f:Restart("r1",p.Active)
   if ok then accepted+=1 return true end
   rejected+=1
   equal(#p.Ledger,before.Ledger,"ledger after rejection");equal(#e.AccountOrder,before.Accounts,"accounts after rejection")
   equal(p.Active,before.Active,"active after rejection");equal(p.Revision,before.Revision,"revision after rejection")
   close(p.Limits,before.Limits,"limits after rejection")
   assert(not current.Retired and not current.Locked and f:Usable(current),"rejected reset retired the account")
   assert(message:find("Nothing was changed"),message)
   return false
  end
  assert(attempt(),"first reset")
  assert(not attempt(),"second reset inside the cooldown was accepted")
  wait(e,f:Limit("ResetLimits","CooldownSeconds")-1);assert(not attempt(),"reset 1s before the cooldown ended")
  wait(e,1)
  -- Burst of 5 credits, each reset spaced only by the cooldown (a fresh instance key every time).
  for _=2,f:Limit("ResetLimits","Burst") do assert(attempt(),"reset within burst") wait(e,f:Limit("ResetLimits","CooldownSeconds")) end
  assert(not attempt(),"reset beyond the saved burst")
  wait(e,f:Limit("ResetLimits","RefillSeconds"));assert(attempt(),"reset after one refill interval")
  assert(not attempt(),"second reset after a single refill")
  equal(p.Limits.Reset.Healthy,accepted,"saved healthy reset count")
  e:Audit()
  return {Accepted=accepted,Rejected=rejected,Retained=#p.Ledger}
 end)

 test("F1: reconnect, restore and successive new instance keys cannot restore a reset budget",function()
  local e,f=exchange(nil,"r2");local p=f:Profile("r2")
  local cooldown=f:Limit("ResetLimits","CooldownSeconds")
  for _=1,f:Limit("ResetLimits","Burst") do assert(f:Restart("r2",p.Active)) wait(e,cooldown) end
  assert(not f:Restart("r2",p.Active),"budget exhausted")
  -- Reconnect: a new Funded view over the same exchange joins the same saved profile.
  local g=F.new(e,L,e.Config);g:Join("r2");assert(not g:Restart("r2",g:Profile("r2").Active),"reconnect restored the budget")
  -- Server restart: checkpoint round trip restores the saved limit state.
  local r,h=roundtrip(e,L);h:Join("r2")
  local q=h:Profile("r2");close(q.Limits,p.Limits,"restored limits")
  assert(not h:Restart("r2",q.Active),"restore restored the budget")
  -- Every older instance key is either already reset or unknown.
  for key in pairs(q.Instances) do assert(not h:Restart("r2",key),"old key "..key.." reset again") end
  assert(not h:Restart("r2","F5K:999999"),"invented key accepted")
  wait(r,f:Limit("ResetLimits","RefillSeconds"));assert(h:Restart("r2",q.Active),"refill after restore")
  r:Audit()
  return {Retained=#q.Ledger}
 end)

 test("F1: a rejected reset settles nothing (positions and working orders untouched)",function()
  local e,f=exchange(nil,"r3");local p=f:Profile("r3")
  assert(f:Restart("r3",p.Active))
  local id=f:Owner("r3");local b=e.Books.BX;b.Bids={};b.Asks={};b.Last=24000;b.Reference=24000
  assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=2,Type="Market"}))
  assert(e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=5900}))
  local a=e.Accounts[id];local orders=clone(a.OpenOrders);local position=clone(a.Positions.BX)
  local ok,message=f:Restart("r3",p.Active)
  assert(not ok and message:find("cooling down"),tostring(message))
  close(a.Positions.BX,position,"position");close(a.OpenOrders,orders,"orders")
  assert(not a.Retired and not a.Locked and f:Owner("r3")==id)
  e:Audit()
 end)

 test("F1: blown-account restarts use the same saved budget and are refused before any change",function()
  local e,f=exchange(nil,"r4");local p=f:Profile("r4")
  local burst=f:Limit("ResetLimits","Burst")
  for i=1,burst do
   local a=result(e,f:Owner("r4"),-5000);assert(a.Depleted);f:TakeEvents("r4")
   assert(f:Restart("r4","F5K"),"blown restart "..i)
  end
  local a=result(e,f:Owner("r4"),-5000);f:TakeEvents("r4")
  local before=#p.Ledger
  local ok,message=f:Restart("r4","F5K")
  assert(not ok and message:find("limit reached"),tostring(message));equal(#p.Ledger,before);assert(not a.Retired)
  wait(e,f:Limit("ResetLimits","RefillSeconds"));assert(f:Restart("r4","F5K"))
  equal(p.Limits.Reset.Blown,burst+1,"saved blown restart count")
  e:Audit()
 end)

 test("F1: 600 fresh-key resets keep retained accounts, checkpoint and portfolio bounded",function()
  local l=ladder(UNLIMITED)
  local e,f=exchange(l,"r5");local p=f:Profile("r5")
  local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(5),Agents={}},P)
  -- Compaction cycles, so compare the largest state seen in an early and a late window of resets.
  local early={Retained=0,Accounts=0,Raw=0,View=0};local late=table.clone(early)
  for i=1,600 do
   assert(f:Restart("r5",p.Active),"reset "..i)
   assert(#p.Ledger<=f:Limit("AccountLimits","CompactAbove"),"retained records exceed the compaction bound")
   local window=(i>100 and i<=200) and early or i>500 and late or nil
   if window then
    window.Retained=math.max(window.Retained,#p.Ledger);window.Accounts=math.max(window.Accounts,#e.AccountOrder)
    window.Raw=math.max(window.Raw,CP.Encode(CP.Capture(e,pop)).RawBytes);window.View=math.max(window.View,#Http:JSONEncode(f:View("r5")))
   end
  end
  local samples={Early=early,Late=late}
  equal(late.Retained,early.Retained,"retained records plateau");equal(late.Accounts,early.Accounts,"engine accounts plateau")
  assert(late.Raw<=early.Raw+512,"checkpoint kept growing: "..early.Raw.." -> "..late.Raw)
  assert(late.View<=early.View+64,"portfolio kept growing: "..early.View.." -> "..late.View)
  local stats=f:Stats("r5").Scopes[1].Life;equal(stats.Attempts,601,"every attempt still counted")
  local r,g=roundtrip(e,l);equal(g:Stats("r5").Scopes[1].Life.Attempts,601);r:Audit();e:Audit()
  return samples
 end)

 test("F1: compaction preserves accounting, statistics, wallet highs, entitlements, receipts and replay protection",function()
  -- Identical deterministic play on two exchanges: one never compacts (the pre-fix representation).
  local keep=ladder({ResetLimits=UNLIMITED.ResetLimits,PurchaseLimits=UNLIMITED.PurchaseLimits,AccountLimits={CompactAbove=0,MaxRetained=0}})
  local fold=ladder(UNLIMITED)
  local uid="501"
  local function play(l)
   local e,f=exchange(l,uid);local p=f:Profile(uid);local receipt;local folded=0
   for i=1,90 do
    local id=f:Owner(uid)
    if i==3 then result(e,id,3200) -- earns $10K access and a Shop balance
     local ok,_,r=f:Purchase(uid,"F5K",1);assert(ok);receipt=r
     result(e,r.Account,-5000);f:TakeEvents(uid) -- the bought account blows
    end
    if i%7==0 then result(e,id,-5000);f:TakeEvents(uid);assert(f:Restart(uid,"F5K"),"blown restart "..i)
    else
     result(e,id,i%3==0 and 275 or -120)
     assert(f:Restart(uid,p.Active),"healthy reset "..i)
    end
    folded=math.max(folded,#p.Ledger)
   end
   f:Evaluate(uid)
   -- Production builds a fresh Funded view over the exchange on every save (leaderboard projection),
   -- which reconciles every account's stats; compare the state players actually see.
   f=F.new(e,l,e.Config)
   return e,f,p,receipt,folded
  end
  local e1,f1,p1,r1=play(keep)
  local e2,f2,p2,r2,peak=play(fold)
  e1:Audit();e2:Audit()
  assert(#p1.Ledger>80,"reference kept every attempt");assert(peak<=fold.AccountLimits.MaxRetained and #p2.Ledger<=fold.AccountLimits.CompactAbove+1,"compacted ledger bounded")
  close(snapshotOf(e2,f2,uid),snapshotOf(e1,f1,uid),"compacted vs reference")
  assert(snapshotOf(e2,f2,uid).Row.Eligible and snapshotOf(e2,f2,uid).Row.Cents==snapshotOf(e1,f1,uid).Row.Cents,"leaderboard row")
  assert(p2.Tiers.F10K and p1.Tiers.F10K,"earned entitlement kept")
  -- Receipt replay protection survives folding of the bought account.
  local before=#p2.Ledger;local ok,_,again=f2:Purchase(uid,"F5K",1)
  assert(ok and again.Key==r2.Key and again.Account==r2.Account,"receipt replay");equal(#p2.Ledger,before);equal(p2.WalletCents,p1.WalletCents)
  -- Folded (old) instance keys cannot be reset again.
  for _,row in ipairs(e2.Accounts[p2.Instances["F5K:archive"].Account].Archive.Recent) do assert(not f2:Restart(uid,row.Key),"folded key reset") end
  -- Wallet high-water marks never allow a folded profit to be re-earned.
  local highs=0 for _,id in ipairs(p2.Ledger) do highs+=p2.WalletHighs[id] or 0 end
  local reference=0 for _,id in ipairs(p1.Ledger) do reference+=p1.WalletHighs[id] or 0 end
  equal(highs,reference,"sum of wallet high-water marks")
  f2:Reconcile(p2);equal(p2.WalletCents,p1.WalletCents,"reconcile after folding mints nothing")
  -- Restores are exact and idempotent.
  local r,g=roundtrip(e2,fold);g:Join(uid);close(snapshotOf(r,g,uid),snapshotOf(e2,f2,uid),"restored")
  local again2=F.new(r,fold,r.Config);again2:Join(uid);close(snapshotOf(r,again2,uid),snapshotOf(e1,f1,uid),"repeated restore")
  r:Audit()
  return {ReferenceRecords=#p1.Ledger,CompactedRecords=#p2.Ledger,ReferenceBytes=ledgerFootprint(e1,p1),CompactedBytes=ledgerFootprint(e2,p2)}
 end)

 test("F1: a full exchange refuses new accounts before any change while existing players keep trading",function()
  local e,f=exchange(ladder(UNLIMITED),"x1")
  local p=f:Profile("x1");result(e,f:Owner("x1"),3000)
  local count=f:PlayerAccounts()
  local full=ladder({ResetLimits=UNLIMITED.ResetLimits,PurchaseLimits=UNLIMITED.PurchaseLimits,AccountLimits={MaxExchangeAccounts=count}})
  local g=F.new(e,full,e.Config)
  local wallet,ledger=p.WalletCents,#p.Ledger
  local ok,message=g:Start("x2");assert(not ok and message:find("capacity"),tostring(message));assert(not g:Profile("x2"),"profile created")
  assert(not g:Restart("x1",p.Active));assert(not g:Purchase("x1","F5K",1));assert(not g:Activate("x1","F10K"))
  equal(p.WalletCents,wallet);equal(#p.Ledger,ledger);equal(f:PlayerAccounts(),count)
  local id=g:Owner("x1");local b=e.Books.BX;b.Bids={};b.Asks={}
  assert(F.Perform(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}),"existing player cannot trade")
  assert(F.Perform(e,id,{Action="Close",Contract="BX"}),"existing player cannot close")
  -- The storage-size signal from the world pauses creation in the same way.
  local h=F.new(e,ladder(UNLIMITED),e.Config,{Capacity=function() return false end})
  assert(not h:Start("x3") and not h:Profile("x3"))
  -- Byte thresholds: discretionary accounts stop at CapacityFraction, a first Start / earned activation at
  -- NewAccountCapacityFraction of the same limits.
  local w={Settings={MaxEncodedBytes=1000,CapacityFraction=0.8,NewAccountCapacityFraction=0.9}};setmetatable(w,{__index=W})
  local raw=CP.MaxDecodedBytes
  w.LastRawBytes=raw*0.8-1;w.LastStoredBytes=10;assert(W.HasCapacity(w,"Restart"))
  w.LastRawBytes=raw*0.8;assert(not W.HasCapacity(w,"Restart") and not W.HasCapacity(w,"Purchase") and W.HasCapacity(w,"Start") and W.HasCapacity(w,"Activate"))
  w.LastRawBytes=raw*0.9;assert(not W.HasCapacity(w,"Start"))
  w.LastRawBytes=10;w.LastStoredBytes=799;assert(W.HasCapacity(w,"Purchase"));w.LastStoredBytes=800;assert(not W.HasCapacity(w,"Purchase") and W.HasCapacity(w,"Start"))
  w.LastStoredBytes=900;assert(not W.HasCapacity(w,"Start"))
  local kinds={};local k=F.new(e,ladder(UNLIMITED),e.Config,{Capacity=function(kind) table.insert(kinds,kind) return kind=="Start" end})
  assert(not k:Restart("x1",p.Active) and kinds[#kinds]=="Restart");assert(k:Start("x4") and kinds[#kinds]=="Start")
  e:Audit()
 end)

 test("F1: per-profile ceiling reserves earned activations and rejects further discretionary accounts",function()
  local l=ladder({ResetLimits=UNLIMITED.ResetLimits,PurchaseLimits=UNLIMITED.PurchaseLimits,AccountLimits={MaxRetained=6,CompactAbove=0}})
  local e,f=exchange(l,"m1");local p=f:Profile("m1")
  -- Four unclaimed tiers are reserved: 1 existing + 1 new + 4 reserve = 6.
  assert(f:Restart("m1",p.Active),"first reset fits")
  local ok,message=f:Restart("m1",p.Active);assert(not ok and message:find("Account limit"),tostring(message))
  p.Tiers.F10K={State="Unlocked",Claimed=false,Announced=true};assert(f:Activate("m1","F10K"),"earned activation blocked")
  e:Audit()
 end)

 ------------------------------------------------------------------------------------------ checkpoint size
 test("Checkpoint: writer and reader agree at both size limits",function()
  local function snap(n) return {P=string.rep("x",n)} end
  local base=#Http:JSONEncode(snap(0))
  local limit=base+2000
  local record=CP.Encode(snap(2000),limit);equal(record.RawBytes,limit,"raw at the writer limit")
  equal(CP.Decode(record,limit).P,string.rep("x",2000),"accepted checkpoint decodes at the same limit")
  assert(not pcall(CP.Encode,snap(2001),limit),"writer accepted raw limit + 1")
  assert(not pcall(CP.Decode,record,limit-1),"reader accepted a record above its limit")
  -- The whole stored value stays below Roblox's 4,194,304-character limit, and above what the previous build
  -- accepted (checkpoint JSON < 3,500,000 plus lease fields), so no existing save becomes unsavable.
  assert(Settings.MaxEncodedBytes+Settings.RecordHeadroomBytes<4194304,"stored record limit above the DataStore value limit")
  assert(Settings.MaxEncodedBytes-Settings.RecordHeadroomBytes>=3500000+2048,"stored limit below what the previous writer accepted")
  -- The audit's compressible 32,000,020-byte fixture is now refused by the writer, before compression.
  local ok,err=pcall(CP.Encode,{AuditPadding=string.rep("x",32000001)})
  assert(not ok and tostring(err):find("too large"),tostring(err))
  return {WriterLimit=CP.MaxDecodedBytes,ReaderLimit=CP.MaxDecodedBytes}
 end)

 test("Checkpoint: real-size boundary - 32,000,000 raw bytes save and restore, one byte more is refused",function()
  local base=#Http:JSONEncode({P=""});local limit=CP.MaxDecodedBytes
  local record=CP.Encode({P=string.rep("y",limit-base)})
  equal(record.RawBytes,limit);equal(#CP.Decode(record).P,limit-base)
  assert(not pcall(CP.Encode,{P=string.rep("y",limit-base+1)}))
  return {RawBytes=record.RawBytes,PayloadBytes=#record.Payload}
 end)

 test("Checkpoint: the full stored record (lease + checkpoint + headroom) is checked before commit",function()
  local s=store();local now=4000
  local settings=clone(Settings)
  local w=world(s,"size",function() return now end,settings);w:Open();assert(w:CanRun(),w.LastError)
  local stored=w.LastStoredBytes;assert(stored and stored>=#Http:JSONEncode(s.Value)-64,"stored size measured")
  settings.MaxEncodedBytes=w.LastStoredBytes+settings.RecordHeadroomBytes+4096
  assert(w:Save(false),"save within the stored limit")
  local saved=clone(s.Value)
  settings.MaxEncodedBytes=w.LastStoredBytes+settings.RecordHeadroomBytes-1
  assert(not w:Save(false),"save above the stored limit");assert(not w:CanRun() and not w.Healthy)
  close(s.Value,saved,"store after refused save")
 end)

 test("Checkpoint: legacy saves still restore; an unreadable save fails closed and is never overwritten",function()
  local e,f=exchange(nil,"7");result(e,f:Owner("7"),450)
  local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(99),Agents={}},P)
  -- Build a record with the pre-fix encoder (same format, no writer checks).
  local raw=Http:JSONEncode(CP.Capture(e,pop))
  local Encoding=game:GetService("EncodingService")
  local compressed=Encoding:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd,3)
  local hash=Encoding:ComputeStringHash(raw,Enum.HashAlgorithm.Sha256):gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
  local legacy={Version=6,Codec="zstd-base64",RawBytes=#raw,Digest=hash,Payload=buffer.tostring(Encoding:Base64Encode(compressed))}
  local restored=CP.Restore(CP.Decode(legacy),e.Config);restored:Audit()
  equal(F.new(restored,L,e.Config):Earned(restored.Profiles["7"]),450,"legacy accounting restored")
  -- A save the reader refuses (oversize/mismatched length) pauses the world and leaves the store untouched.
  local bad=clone(legacy);bad.RawBytes=CP.MaxDecodedBytes+1
  local s=store();s.Value={Version=1,WorldId="w",Generation=3,SaveSequence=9,SavedStep=e.Step,Owner="",JobId="",PlaceId=1,LeaseUntil=0,Checkpoint=bad}
  local original=clone(s.Value);local now=100
  local w=world(s,"reader",function() return now end);w:Open()
  assert(w.Mode=="Unavailable" and not w:CanRun() and not w.Engine,"unreadable save opened")
  for _=1,3 do now+=Settings.RetrySeconds;w:Maintain() end
  assert(not w:CanRun());equal(s.Value.Checkpoint.RawBytes,bad.RawBytes);equal(s.Value.Checkpoint.Payload,bad.Payload)
  equal(s.Value.SavedStep,original.SavedStep);equal(s.Value.SaveSequence,original.SaveSequence,"checkpoint overwritten")
 end)

 test("Checkpoint: a save at the previous writer's limit still reopens and saves after this update",function()
  -- Old encoder, same record format, without the new writer checks.
  local Encoding=game:GetService("EncodingService")
  local function legacyEncode(snapshot)
   local raw=Http:JSONEncode(snapshot)
   local compressed=Encoding:CompressBuffer(buffer.fromstring(raw),Enum.CompressionAlgorithm.Zstd,3)
   local hash=Encoding:ComputeStringHash(raw,Enum.HashAlgorithm.Sha256):gsub(".",function(c) return string.format("%02x",string.byte(c)) end)
   return {Version=6,Codec="zstd-base64",RawBytes=#raw,Digest=hash,Payload=buffer.tostring(Encoding:Base64Encode(compressed))}
  end
  local e,f=exchange(nil,"8");result(e,f:Owner("8"),250)
  local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(8),Agents={}},P)
  -- Incompressible synthetic padding sized so the old check (#JSON(record) < 3,500,000) just passes.
  local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local state=12345
  local function padding(n)
   local b=buffer.create(n)
   for i=0,n-1 do state=state*48271%2147483647;buffer.writeu8(b,i,string.byte(alphabet,state//7%64+1)) end
   return buffer.tostring(b)
  end
  local size,record=3400000,nil
  for _=1,6 do
   e.Profiles["8"].Padding=padding(size);record=legacyEncode(CP.Capture(e,pop))
   local length=#Http:JSONEncode(record)
   if length<3500000 and length>=3500000-3000 then break end
   size+=math.floor((3500000-1500-length)*0.98)
  end
  local length=#Http:JSONEncode(record);assert(length<3500000 and length>=3500000-3000,"fixture size "..length)
  local s=store();s.Value={Version=1,WorldId="legacy",Generation=4,SaveSequence=11,SavedStep=e.Step,Owner="",JobId="",PlaceId=123,LeaseUntil=0,Checkpoint=record}
  local now=100;local w=world(s,"reopen",function() return now end);w:Open()
  assert(w:CanRun(),"legacy-size save could not be reopened: "..tostring(w.LastError))
  equal(s.Value.SaveSequence,12,"reopen commit");assert(w:Save(false),"periodic save of a legacy-size exchange")
  equal(F.new(w.Engine,L,w.Engine.Config):Earned(w.Engine.Profiles["8"]),250,"accounting preserved")
  assert(not w:HasCapacity("Restart"),"a near-limit exchange should pause discretionary accounts")
  w.Engine:Audit()
  return {LegacyRecordJSON=length,StoredBytes=w.LastStoredBytes,Limit=Settings.MaxEncodedBytes}
 end)

 test("F1: compaction never leaves partial state (conflicting archive id is left untouched)",function()
  local e,f=exchange(ladder(UNLIMITED),"k1");local p=f:Profile("k1")
  e:AddAccount("player:k1:F5K:archive",0,0,.8,true) -- an unexpected pre-existing record with the archive id
  for _=1,40 do assert(f:Restart("k1",p.Active)) end
  local seen={} for _,id in ipairs(e.AccountOrder) do assert(e.Accounts[id],"AccountOrder references a removed account");seen[id]=true end
  for _,id in ipairs(p.Ledger) do assert(e.Accounts[id] and seen[id],"ledger references a removed account") end
  assert(not p.Instances["F5K:archive"],"conflicting archive adopted");equal(f:Stats("k1").Scopes[1].Life.Attempts,41)
  e:AdvanceClock(.25);e:Audit()
 end)

 ------------------------------------------------------------------------------------------ F2 purchases
 test("F2: completed receipt replays cause zero writes, grants, debits or pauses; others keep trading",function()
  local s=store();local now=5000
  local w,c=world(s,"shop",function() return now end);w:Open();assert(w:CanRun(),w.LastError)
  local f=F.new(w.Engine,L,c);assert(f:Start("b1"));assert(f:Start("b2"))
  result(w.Engine,f:Owner("b1"),3000);assert(w:Save(false))
  local done={};local function finish(ok,message,receipt) table.insert(done,{Ok=ok,Receipt=receipt,CanRun=w:CanRun()}) end
  assert(w:Purchase(f,"b1","F5K",1,finish));assert(w.TransactionBusy and not w:CanRun(),"new purchase pauses for its save")
  drain();equal(#done,1);assert(done[1].Ok and w:CanRun())
  local writes,p=s.Writes,f:Profile("b1");local ledger,wallet,spent=#p.Ledger,p.WalletCents,p.WalletSpentCents
  local other=f:Owner("b2");local b=w.Engine.Books.BX;b.Bids={};b.Asks={};b.Last=24000
  for i=1,25 do
   assert(w:Purchase(f,"b1","F5K",1,finish),"replay "..i)
   assert(not w.TransactionBusy and w:CanRun() and w.PendingPurchase==nil,"replay paused the exchange")
   assert(F.Perform(w.Engine,other,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}),"other player blocked")
   assert(F.Perform(w.Engine,other,{Action="Close",Contract="BX"}))
  end
  drain()
  equal(s.Writes,writes,"extra store writes");equal(#p.Ledger,ledger,"extra accounts");equal(p.WalletCents,wallet,"extra debit");equal(p.WalletSpentCents,spent)
  equal(#done,26,"one completion per request")
  for i=2,#done do assert(done[i].Ok and done[i].CanRun and done[i].Receipt.Account==done[1].Receipt.Account and done[i].Receipt.Sequence==1) end
  assert(not w:Purchase(f,"b1","F10K",1,finish),"sequence reused for another tier")
  -- After a restart the receipt is loaded from the durable record and replays the same way.
  assert(w:Close());local w2=world(s,"shop2",function() return now end);w2:Open();assert(w2:CanRun(),w2.LastError)
  local f2=F.new(w2.Engine,L,w2.Engine.Config);local after=s.Writes
  for _=1,10 do assert(w2:Purchase(f2,"b1","F5K",1,finish));assert(w2:CanRun() and not w2.TransactionBusy) end
  drain();equal(s.Writes,after,"writes after restore");equal(#f2:Profile("b1").Ledger,ledger)
  w2.Engine:Audit()
  return {Replays=35,ExtraWrites=0,Pauses=0}
 end)

 test("F2: pending and ambiguous purchases stay frozen, replay is refused, retry commits exactly once",function()
  local s=store();local now=6000
  local w,c=world(s,"ambiguous",function() return now end);w:Open()
  local f=F.new(w.Engine,L,c);assert(f:Start("a1"));result(w.Engine,f:Owner("a1"),3000);assert(w:Save(false))
  s.FailAfter=true;local done=0
  assert(w:Purchase(f,"a1","F5K",1,function(ok) assert(ok) done+=1 end))
  drain();equal(done,0);assert(w.TransactionBusy and not w:CanRun(),"ambiguous commit must stay frozen")
  assert(not w:Purchase(f,"a1","F5K",1,function() error("replay answered before durability") end))
  assert(not w:Purchase(f,"a1","F5K",2,function() error("concurrent purchase") end))
  s.FailAfter=false;now+=Settings.RetrySeconds;w:Maintain();equal(done,1);assert(w:CanRun())
  local writes=s.Writes
  assert(w:Purchase(f,"a1","F5K",1,function(ok) assert(ok) done+=1 end));equal(done,2);equal(s.Writes,writes)
  equal(f:Profile("a1").WalletCents,100000,"single debit")
  -- Failure before commit followed by loss of the lease: the store never saw the purchase, so the same
  -- confirmation is charged at most once after the exchange reloads.
  local s2=store();local t=7000
  local x,cx=world(s2,"before",function() return t end);x:Open()
  local g=F.new(x.Engine,L,cx);assert(g:Start("a2"));result(x.Engine,g:Owner("a2"),3000);assert(x:Save(false))
  s2.FailBefore=true;local outcome
  assert(x:Purchase(g,"a2","F5K",1,function(ok) outcome=ok end));drain();assert(outcome==nil and not x:CanRun())
  t=x.Lease.Record.LeaseUntil+1;s2.FailBefore=false;x:Maintain();equal(outcome,false,"pending purchase reported as not saved")
  x:Maintain();assert(x:CanRun(),x.LastError)
  local g2=F.new(x.Engine,L,x.Engine.Config);local q=g2:Profile("a2");equal(q.WalletCents,300000);equal(#q.Ledger,1)
  local final;assert(x:Purchase(g2,"a2","F5K",1,function(ok) final=ok end));drain();assert(final)
  equal(g2:Profile("a2").WalletCents,100000);equal(#g2:Profile("a2").Ledger,2)
  -- A stale writer cannot commit a purchase after another server took over.
  local s3=store();local u=8000
  local old,co=world(s3,"old",function() return u end);old:Open()
  local h=F.new(old.Engine,L,co);assert(h:Start("a3"));result(old.Engine,h:Owner("a3"),3000);assert(old:Save(false))
  u=old.Lease.Record.LeaseUntil+1;local new=world(s3,"new",function() return u end);new:Open();assert(new:CanRun())
  local stale;u-=60 -- the old server still believes its lease is valid
  old.Lease.Record.LeaseUntil=u+90
  assert(old:Purchase(h,"a3","F5K",1,function(ok) stale=ok end));drain()
  assert(stale==nil and not old:CanRun(),"stale purchase acknowledged")
  local fresh=F.new(new.Engine,L,new.Engine.Config);equal(fresh:Profile("a3").WalletCents,300000,"stale debit committed")
 end)

 test("F2: new purchases have a saved per-profile budget and an exchange-wide spacing",function()
  local e,f=exchange(nil,"p1");result(e,f:Owner("p1"),20000);local p=f:Profile("p1")
  local burst=f:Limit("PurchaseLimits","Burst")
  for i=1,burst do assert(f:Purchase("p1","F5K",i),"purchase "..i) end
  local wallet,ledger=p.WalletCents,#p.Ledger
  local ok,message=f:Purchase("p1","F5K",burst+1);assert(not ok and message:find("limit reached"),tostring(message))
  equal(p.WalletCents,wallet,"charged while limited");equal(#p.Ledger,ledger)
  assert(f:Purchase("p1","F5K",1),"replay is not limited")
  local r,g=roundtrip(e,L);assert(not g:Purchase("p1","F5K",burst+1),"restore restored the purchase budget")
  wait(r,f:Limit("PurchaseLimits","RefillSeconds"));assert(g:Purchase("p1","F5K",burst+1))
  -- Exchange-wide spacing between two players' new transactions on one server.
  local s=store();local now=9000
  local w,c=world(s,"spacing",function() return now end);w:Open()
  local h=F.new(w.Engine,L,c);for _,uid in ipairs({"s1","s2"}) do assert(h:Start(uid));result(w.Engine,h:Owner(uid),3000) end
  assert(w:Save(false))
  assert(w:Purchase(h,"s1","F5K",1,function() end));drain()
  local spent=h:Profile("s2").WalletCents
  local okSpacing,why=w:Purchase(h,"s2","F5K",1,function() error("spaced purchase ran") end)
  assert(not okSpacing and why:find("busy") and w:CanRun(),tostring(why));equal(h:Profile("s2").WalletCents,spent)
  now+=Settings.PurchaseSpacingSeconds;assert(w:Purchase(h,"s2","F5K",1,function() end));drain()
  equal(h:Profile("s2").WalletCents,spent-200000)
 end)

 test("F2: errors inside a purchase never freeze the exchange; replays are answered during a routine save",function()
  local s=store();local now=11000
  local w,c=world(s,"errors",function() return now end);w:Open()
  local f=F.new(w.Engine,L,c);assert(f:Start("e1"));result(w.Engine,f:Owner("e1"),5000);assert(w:Save(false))
  -- Error before anything is written: nothing charged, exchange keeps running.
  local before=setmetatable({Purchase=function() error("injected failure before commit") end},{__index=f})
  local ok=w:Purchase(before,"e1","F5K",1,function() error("no completion expected") end)
  assert(not ok and not w.TransactionBusy and w:CanRun(),"exchange frozen by a failed purchase");equal(f:Profile("e1").WalletCents,500000)
  -- Error after the receipt was written: the purchase is kept pending and saved exactly once.
  local after=setmetatable({Purchase=function(self,...) F.Purchase(f,...) error("injected failure after receipt") end},{__index=f})
  local done=0;local writes=s.Writes
  assert(w:Purchase(after,"e1","F5K",1,function(saved) assert(saved);done+=1 end))
  drain();equal(done,1);assert(w:CanRun() and not w.TransactionBusy);equal(s.Writes,writes+1);equal(f:Profile("e1").WalletCents,300000)
  -- A replay while a routine save is in flight is answered from the committed receipt.
  now+=Settings.PurchaseSpacingSeconds;w.Busy=true
  local answered;assert(w:Purchase(f,"e1","F5K",1,function(saved) answered=saved end));w.Busy=false
  assert(answered,"replay refused during a save");equal(s.Writes,writes+1)
  -- A transaction flag left behind by any earlier error is cleared when the lease is lost and the world reloads.
  w.TransactionBusy=true;assert(not w:CanRun())
  now=w.Lease.Record.LeaseUntil+1;w:Maintain()
  assert(w:CanRun() and not w.TransactionBusy,"stale transaction flag survived a reload")
  equal(F.new(w.Engine,L,w.Engine.Config):Profile("e1").WalletCents,300000)
 end)

 ------------------------------------------------------------------------------------------ F3 replies
 test("F3: reply queues stay bounded by count and age for clients that never subscribe",function()
  local buffer=ReplyBuffer.new(Settings.MaxQueuedReplies,Settings.ReplyMaxAgeSeconds)
  local state={Replies={},ReplyTimes={}};local now=0
  for i=1,10000 do
   now+=1/6 -- the remote limiter's sustained rate
   local kind=i%3==0 and {RequestId=i,Ok=false,Message="Exchange busy. Please retry."} or i%3==1 and {RequestId=i,Ok=true,Message="Saved.",Kind="Start"} or {RequestId=i,Ok=false,Message="Rejected"}
   buffer:Push(state,kind,now)
   assert(#state.Replies<=Settings.MaxQueuedReplies and #state.ReplyTimes==#state.Replies,"reply queue exceeded its bound")
  end
  equal(#state.Replies,Settings.MaxQueuedReplies);assert(state.Full and state.DroppedReplies==10000-Settings.MaxQueuedReplies)
  equal(state.Replies[#state.Replies].RequestId,10000,"newest reply kept");equal(state.Replies[1].RequestId,10000-Settings.MaxQueuedReplies+1)
  local queued,dropped=buffer:Take(state);equal(#queued,Settings.MaxQueuedReplies);equal(dropped,10000-Settings.MaxQueuedReplies)
  equal(#state.Replies,0);equal(state.DroppedReplies,nil)
  -- Age bound: idle connections release everything after ReplyMaxAgeSeconds.
  state.Full=false
  for i=1,5 do buffer:Push(state,{RequestId=i,Ok=true},now) end
  buffer:Prune(state,now+Settings.ReplyMaxAgeSeconds);equal(#state.Replies,5,"not yet expired")
  buffer:Prune(state,now+Settings.ReplyMaxAgeSeconds+0.01);equal(#state.Replies,0);assert(state.Full,"expiry forces a full resync")
  local _,expired=buffer:Take(state);equal(expired,5)
  -- A normally subscribed client (flushed every broadcast) never loses a reply.
  local live={Replies={},ReplyTimes={}}
  for i=1,200 do buffer:Push(live,{RequestId=i},i*0.1);if i%1==0 then local got,lost=buffer:Take(live);equal(#got,1);equal(lost,nil) end end
 end)

 ------------------------------------------------------------------------------------------ S1 pricing
 test("S1: empty-side fallback quotes never cross; long and short round trips cannot profit",function()
  local function book() local e,f=exchange(nil,"q1");e:AddAccount("maker",1000000,500,.8,false);return e,f,e.Books.BX end
  -- Long: asks empty, a participant bid one tick above the last trade.
  local e,f,b=book();local id=f:Owner("q1");local tick=b.Spec.Tick
  local last=(b.Last or b.Reference)
  assert(e:Submit("maker",{Contract="BX",Direction=1,Quantity=10,Type="Limit",Price=(last+1)*tick}))
  assert(#b.Asks==0 and b.Bids[1].Price>last)
  local start=e.Accounts[id].Balance
  for _=1,10 do
   local ok,fill=F.Perform(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=5,Type="Market"});assert(ok and fill.Filled==5)
   assert(fill.Average>=b.Bids[1].Price*tick,"buy filled below the best bid")
   assert(F.Perform(e,id,{Action="Close",Contract="BX"}))
  end
  assert(e.Accounts[id].Balance<=start+1e-9,"long round trips profited: "..(e.Accounts[id].Balance-start))
  equal(f:Profile("q1").WalletCents,0,"wallet credited")
  -- A marketable buy limit below the clamped fallback no longer fills at the lower last trade.
  local ok,rest=F.Perform(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=last*tick})
  assert(ok and rest.Filled==0 and rest.Remaining==1,"limit filled through the bid");e:Cancel(id,rest.Id)
  e:Audit()
  -- Short: bids empty, a participant ask one tick below the last trade.
  local e2,f2,b2=book();local id2=f2:Owner("q1");local last2=(b2.Last or b2.Reference)
  assert(e2:Submit("maker",{Contract="BX",Direction=-1,Quantity=10,Type="Limit",Price=(last2-1)*tick}))
  assert(#b2.Bids==0 and b2.Asks[1].Price<last2)
  local start2=e2.Accounts[id2].Balance
  for _=1,10 do
   local okShort,fill=F.Perform(e2,id2,{Action="Place",Contract="BX",Direction=-1,Quantity=5,Type="Market"});assert(okShort and fill.Filled==5)
   assert(fill.Average<=b2.Asks[1].Price*tick,"sell filled above the best ask")
   assert(F.Perform(e2,id2,{Action="Close",Contract="BX"}))
  end
  assert(e2.Accounts[id2].Balance<=start2+1e-9,"short round trips profited: "..(e2.Accounts[id2].Balance-start2))
  e2:Audit()
  -- No liquidity at all: closes and depletion liquidation still fill at the last trade.
  local e3,f3=exchange(nil,"q3");local id3=f3:Owner("q3");local b3=e3.Books.BX;b3.Bids={};b3.Asks={};b3.Last=24000
  assert(F.Perform(e3,id3,{Action="Place",Contract="BX",Direction=1,Quantity=3,Type="Market"}))
  b3.Last=24000-5000/50/b3.Spec.Tick;e3:AdvanceClock(.25)
  assert(e3.Accounts[id3].Locked and not e3.Accounts[id3].Positions.BX,"liquidation stuck without liquidity")
  e3:Audit()
  -- Two-sided book: normal fills are unchanged (buy at the ask, sell at the bid).
  local e4,f4,b4=book();local id4=f4:Owner("q1");local l4=b4.Last or b4.Reference
  assert(e4:Submit("maker",{Contract="BX",Direction=1,Quantity=5,Type="Limit",Price=(l4-2)*tick}))
  e4:AddAccount("maker2",1000000,500,.8,false)
  assert(e4:Submit("maker2",{Contract="BX",Direction=-1,Quantity=5,Type="Limit",Price=(l4+2)*tick}))
  local _,buy=F.Perform(e4,id4,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"});equal(buy.Average,(l4+2)*tick,"buy at ask")
  local _,sell=F.Perform(e4,id4,{Action="Close",Contract="BX"});equal(sell.Average,(l4-2)*tick,"sell at bid")
  e4:Audit()
 end)
 return report
end
return Tests
