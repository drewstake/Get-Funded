-- Reply queue and empty-book pricing regressions. Disposable engines only.
local Tests={}
local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local L=require(game.ReplicatedStorage.MarketReign.ProgressionConfig)
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local Settings=require(script.Parent.WorldConfig)
local ReplyBuffer=require(script.Parent.ReplyBuffer)
local function clone(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=clone(x) end return r end
local function equal(a,b,label) assert(a==b,(label or "value")..": "..tostring(a).." ~= "..tostring(b)) end
local function exchange(l,uid,options)
 local c=clone(C);c.WarmupSeconds=0
 local e=E.new(c,4821);local f=F.new(e,l or L,c,options)
 if uid then assert(f:Start(uid)) end
 return e,f
end

function Tests.Run()
 local report={}
 local function test(name,fn)local ok,value=pcall(fn);table.insert(report,{Name=name,Passed=ok,Detail=ok and (value or "Passed") or tostring(value)})end
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
 test("S1: missing liquidity never fabricates fills, balances, or round-trip profit",function()
  for _,side in ipairs({1,-1})do
   local e,f=exchange(nil,"q1");e:AddAccount("maker",1000000,500,.8,false)
   local id=f:Owner("q1");local b=e.Books.BX;local tick=b.Spec.Tick;local last=b.Last or b.Reference
   assert(e:Submit("maker",{Contract="BX",Direction=side,Quantity=10,Type="Limit",Price=(last+side)*tick}))
   local start=e.Accounts[id].Balance
   for _=1,10 do
    local ok,fill=F.Perform(e,id,{Action="Place",Contract="BX",Direction=side,Quantity=5,Type="Market"})
    assert(ok and fill.Filled==0 and fill.Cancelled==5 and not e.Accounts[id].Positions.BX)
    assert(not F.Perform(e,id,{Action="Close",Contract="BX"}))
   end
   assert(e.Accounts[id].Balance==start and e.TotalVolume==0 and not e.Accounts[E.HouseId])
   local ok,rest=F.Perform(e,id,{Action="Place",Contract="BX",Direction=side,Quantity=1,Type="Limit",Price=last*tick})
   assert(ok and rest.Filled==0 and rest.Remaining==1);e:Cancel(id,rest.Id);e:Audit()
  end
  local e,f=exchange(nil,"depletion");local id=f:Owner("depletion");local b=e.Books.BX
  e:AddAccount("maker",1e9,10000,.99,false)
  assert(e:Submit("maker",{Contract="BX",Direction=-1,Quantity=2,Type="Limit",Price=6000}))
  assert(F.Perform(e,id,{Action="Place",Contract="BX",Direction=1,Quantity=2,Type="Market"}))
  b.Last=math.round(5900/b.Spec.Tick);e:AdvanceClock(.25)
  assert(e.Accounts[id].Locked and e.Accounts[id].Positions.BX.Triggered=="Account depleted")
  assert(e.Accounts[id].Positions.BX.Quantity==2,"Empty book fabricated a liquidation")
  assert(e:Submit("maker",{Contract="BX",Direction=1,Quantity=2,Type="Limit",Price=5900}))
  e:AdvanceClock(.25);assert(not e.Accounts[id].Positions.BX);e:Audit()
  local e2,f2=exchange(nil,"spread");local id2=f2:Owner("spread");local b2=e2.Books.BX;local ref=b2.Reference
  for i,side in ipairs({1,-1})do
   e2:AddAccount("maker"..i,1e9,10000,.99,false)
   assert(e2:Submit("maker"..i,{Contract="BX",Direction=side,Quantity=5,Type="Limit",Price=(ref-side*2)*b2.Spec.Tick}))
  end
  local _,buy=F.Perform(e2,id2,{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"})
  local _,sell=F.Perform(e2,id2,{Action="Close",Contract="BX"})
  equal(buy.Average,(ref+2)*b2.Spec.Tick);equal(sell.Average,(ref-2)*b2.Spec.Tick)
  assert(e2.Accounts[id2].Balance<e2.Accounts[id2].Base);e2:Audit()
 end)

 return report
end
return Tests
