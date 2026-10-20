local Engine=require(script.Parent.MarketEngine)
local Participants=require(script.Parent.Participants)
local Default=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Tests={}
local function config()
 local c=table.clone(Default) c.MaxTradeHistory=100000 c.MaxOrderHistory=100000 c.MaxCandles=10000 return c
end
local function fresh()
 local e=Engine.new(config(),123)
 for _,id in ipairs({"A","B","C","D"}) do e:AddAccount(id,1000000,500,0.9,false) end
 return e
end
local function place(e,id,side,qty,price,extra)
 local r={Contract="BX",Direction=side,Quantity=qty,Type=price and "Limit" or "Market",Price=price}
 for k,v in pairs(extra or {}) do r[k]=v end
 local ok,result=e:Submit(id,r) assert(ok,tostring(result)) return result
end
function Tests.Run()
 local report={} local function test(name,fn) local ok,result=pcall(fn) table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)}) end
 test("Price/time priority, partial fills, cancellation and no quote-driven price",function()
  local e=fresh() local a=place(e,"A",-1,3,5825) local b=place(e,"B",-1,4,5825) place(e,"C",-1,2,5824.75)
  assert(e.Books.BX.Last==nil) local fill=place(e,"D",1,4)
  assert(fill.Filled==4 and fill.Average==5824.875) assert(e.Orders[a.Id].Remaining==1 and e.Orders[b.Id].Remaining==4)
  assert(e.Trades[1].Seller=="C" and e.Trades[2].Seller=="A")
  local last=e.Books.BX.Last assert(e:Cancel("B",b.Id)) assert(e.Books.BX.Last==last)
  assert(not e:Cancel("C",a.Id)) e:Audit() return "Better price first, then FIFO; partial residual 1; ownership checked"
 end)
 test("Marketable limits honor their price cap and rest the residual",function()
  local e=fresh() place(e,"A",-1,2,5825) place(e,"B",-1,3,5825.5)
  local order=place(e,"C",1,5,5825.25)
  assert(order.Filled==2 and order.Remaining==3 and e.Orders[order.Id].Price==23301)
  assert(e.Books.BX.Asks[1].Price==23302)
  local follow=place(e,"D",-1,1)
  assert(follow.Filled==1 and e.Orders[order.Id].Remaining==2)
  assert(e:Cancel("C",order.Id)) e:Audit() return "Limit cap, later partial fill and residual cancellation passed"
 end)
 test("Thin liquidity increases impact; multi-level sweeps",function()
  local function sweep(depth)
   local e=fresh() for i=1,6 do place(e,"A",-1,depth,5825+(i-1)*0.25) end
   local r=place(e,"B",1,6) e:Audit() return r
  end
  local thin,deep=sweep(1),sweep(8)
  assert(thin.Average>deep.Average and thin.Slippage>deep.Slippage)
  return {ThinAverage=thin.Average,DeepAverage=deep.Average,ThinSlippage=thin.Slippage,DeepSlippage=deep.Slippage}
 end)
 test("Unfilled market remainder cancelled, self trades prevented",function()
  local e=fresh() place(e,"A",-1,2,5825) local r=place(e,"B",1,7)
  assert(r.Filled==2 and r.Cancelled==5 and r.Remaining==0)
  place(e,"B",-1,2,5825.25) local vol=e.TotalVolume place(e,"B",1,2)
  assert(e.TotalVolume==vol) e:Audit() return "IOC accounting and self-trade prevention passed"
 end)
 test("Stop cascade, partial protection, retry and OCO",function()
  local e=fresh() place(e,"A",-1,4,5825) place(e,"B",1,4,nil,{StopTicks=4,TargetTicks=8})
  place(e,"C",1,2,5824) place(e,"A",-1,1) e:ProcessStops()
  assert(e.Accounts.B.Positions.BX.Quantity==3 and e.Accounts.B.Positions.BX.Triggered=="Stop loss")
  assert(e.Accounts.B.Positions.BX.Target==nil,"OCO target must disappear while stop exit is partial")
  place(e,"D",1,3,5823.75) e:AdvanceClock(0.25)
  assert(not e.Accounts.B.Positions.BX) assert(e.Accounts.B.Realized<0)
  assert(#e:Snapshot("B","BX","1m",true).Orders==0) e:Audit() return "Stop remains latched through insufficient liquidity, never reverses"
 end)
 test("Take-profit long and short, entry averaging and realized P&L",function()
  local e=fresh() place(e,"A",-1,2,5825) place(e,"B",1,2,nil,{TargetTicks=4})
  place(e,"C",1,3,5826) place(e,"A",-1,1) e:ProcessStops()
  assert(not e.Accounts.B.Positions.BX and e.Accounts.B.Realized==100)
  place(e,"C",1,2,5825) place(e,"B",-1,2,nil,{TargetTicks=4})
  place(e,"A",-1,3,5824) place(e,"D",1,1) e:ProcessStops()
  assert(not e.Accounts.B.Positions.BX and e.Accounts.B.Realized==200) e:Audit()
  return "Both take-profit directions settle from real fills"
 end)
 test("Dragged SL and TP amend atomically and trigger from subsequent executions",function()
  for _,side in ipairs({1,-1})do
   for _,field in ipairs({"Stop","Target"})do
    local e=fresh() place(e,"A",-side,2,5825) place(e,"B",side,2,nil,{StopTicks=40,TargetTicks=120})
    local p=e.Accounts.B.Positions.BX local opposite=field=="Stop"and"Target"or"Stop" local other=p[opposite]
    -- Move the market into profit so a stop beyond the entry is legal.
    place(e,"C",-side,1,5825+side*2) place(e,"D",side,1)
    local price=5825+side*(field=="Stop"and 1 or 3)
    local before=e:Audit() local revision=e.Accounts.B.Revision
    assert(e:AmendProtection("B",{Contract="BX",OrderId=p.Id,Protection=field,Price=price,ExpectedPrice=p[field]}))
    assert(p[field]==price and p[opposite]==other and e.Accounts.B.Revision==revision+1)
    assert(e:Audit().Hash==before.Hash and e.TotalVolume==3 and e.Books.BX.Last*0.25==5825+side*2)
    local snapshot=e:Snapshot("B","BX","1m",true) local found=false
    for _,order in ipairs(snapshot.Orders)do if order.Protection==field then assert(order.Price==price and order.Quantity==2);found=true end end assert(found)
    -- A new trade reaches the edited level; closing liquidity fills the protection.
    place(e,"C",side,3,price) place(e,"A",-side,1) e:ProcessStops()
    assert(not e.Accounts.B.Positions.BX and e.Accounts.B.Realized==side*(price-5825)*100)
    e:Audit()
   end
  end
  return "Long/short SL and TP, profitable stops, snapshots, OCO and fill-based exits passed"
 end)
 test("Wide ticket protections remain draggable outside the entry-order price band",function()
  for _,key in ipairs(Default.ContractOrder)do
   local spec=Default.Contracts[key]
   -- Reproduce a BX target 2,000 points away; cover the other markets beyond their 10% bands too.
   local ticks=key=="BX"and 8000 or math.ceil(spec.Last*Default.PriceBandFraction*1.2/spec.Tick)
   assert(ticks<=10000 and ticks*spec.Tick>spec.Last*Default.PriceBandFraction)
   for _,side in ipairs({1,-1})do for _,field in ipairs({"Stop","Target"})do
    local e=fresh() local a=e:AddAccount("P",1000000,500,.9,true)
    assert(e:Submit("A",{Contract=key,Direction=-side,Quantity=2,Type="Limit",Price=spec.Last}))
    assert(e:Submit("P",{Contract=key,Direction=side,Quantity=2,Type="Market",StopTicks=ticks,TargetTicks=ticks}))
    local p=a.Positions[key] local original=p[field] local opposite=field=="Stop"and"Target"or"Stop" local other=p[opposite]
    local sign=side*(field=="Stop"and -1 or 1) local before=e:Audit() local volume=e.TotalVolume
    for _,offset in ipairs({1,-1})do
     local price=math.round((original+sign*offset*spec.Tick)/spec.Tick)*spec.Tick
     local expected=p[field] local revision=a.Revision
     local request={Contract=key,OrderId=p.Id,Protection=field,Price=price,ExpectedPrice=expected}
     local ok,reason=e:AmendProtection("P",request);assert(ok,key.." "..side.." "..field..": "..tostring(reason))
     assert(p[field]==price and p[opposite]==other and a.Revision==revision+1)
     assert(p["Manual"..field] and p.Quantity==2 and not p.Triggered)
     assert(not e:AmendProtection("P",request),"Repeated stale drag accepted")
     local found=false
     for _,order in ipairs(e:Snapshot("P",key,"1m",true).Orders)do
      if order.Protection==field then assert(order.Price==price and order.Quantity==2);found=true end
     end
     assert(found and e.TotalVolume==volume and e:Audit().Hash==before.Hash)
    end
    -- Adding a missing SL/TP uses the same protection rules as dragging an existing one.
    assert(e:CancelProtection("P",p.Id,field))
    assert(e:AmendProtection("P",{Contract=key,OrderId=p.Id,Protection=field,Price=original,Create=true,ExpectedQuantity=2}))
    assert(p[field]==original and p[opposite]==other and p.Quantity==2)
    -- The entry-order band still applies to both limit and stop entries.
    for _,kind in ipairs({"Limit","Stop"})do
     local ok,reason=e:Submit("P",{Contract=key,Direction=1,Quantity=1,Type=kind,Price=spec.Last+ticks*spec.Tick})
     assert(not ok and reason==kind.." is outside the price band.")
    end
    e:Audit()
   end end
  end
  return "Wide long/short SL and TP can move both ways or be added on every market; entry bands and stale checks remain enforced"
 end)
 test("Protection edits reject invalid, stale and foreign requests",function()
  local e=fresh() e:AddAccount("P",50000,40,0.8,true)
  place(e,"A",-1,2,5825) place(e,"P",1,2,nil,{StopTicks=40,TargetTicks=120})
  local p=e.Accounts.P.Positions.BX local original=p.Stop local revision=e.Accounts.P.Revision
  local function request(changes)
   local r={Contract="BX",OrderId=p.Id,Protection="Stop",Price=5820,ExpectedPrice=original}
   for key,value in pairs(changes or{})do r[key]=value end return r
  end
  for _,change in ipairs({{Price=0/0},{Price=math.huge},{Price=-1},{Price=5820.13},{Price=5825},{Price=5826},
   {Price=1e12},{ExpectedPrice=5814.75},{OrderId=p.Id+1},{Contract="BT"},{Protection="Entry"},
   {Protection="Target",ExpectedPrice=p.Target,Price=5824}})do
   assert(not e:AmendProtection("P",request(change)))
  end
  assert(not e:AmendProtection("B",request())) assert(not e:AmendProtection("Missing",request()))
  assert(p.Stop==original and e.Accounts.P.Revision==revision)
  assert(e:AmendProtection("P",request())) assert(not e:AmendProtection("P",request({Price=5821})))
  assert(e:CancelProtection("P",p.Id,"Target"))
  assert(not e:AmendProtection("P",request({Protection="Target",ExpectedPrice=5855,Price=5856})))
  place(e,"C",1,1,5820) place(e,"A",-1,1)
  assert(p.Triggered=="Stop loss")
  assert(not e:AmendProtection("P",request({ExpectedPrice=5820,Price=5819})))
  e:Audit() return "Invalid ticks, direction, ownership, stale versions, non-finite/extreme prices, cancelled/triggered orders rejected"
 end)
 test("Validation, reserved margin, finite inventory and off-tick prices",function()
  local e=fresh() e:AddAccount("P",50000,40,0.8,true)
  assert(not e:Submit("P",{Contract="BX",Direction=1,Quantity=1.5,Type="Market"}))
  assert(not e:Submit("P",{Contract="BX",Direction=1,Quantity=1,Type="Limit",Price=5824.13}))
  assert(not e:Submit("P",{Contract="BX",Direction=1,Quantity=0/0,Type="Market"}))
  assert(not e:Submit("P",{Contract="FAKE",Direction=1,Quantity=1,Type="Market"}))
  place(e,"P",1,20,5810)
  -- 20 working + 31 more would exceed the $50K account's 50-contract limit.
  assert(not e:Submit("P",{Contract="BX",Direction=1,Quantity=31,Type="Limit",Price=5810}))
  e:Audit() return "Working orders reserve capacity; invalid inputs rejected"
 end)
 test("Every candle timeframe agrees with the execution tape",function()
  local e=fresh()
  for i=1,80 do e:AdvanceClock(17) place(e,"A",-1,1,5824+(i%5)*0.25) place(e,"B",1,1) end
  for _,tf in ipairs(e.Config.Timeframes) do
   local groups={}
   for _,t in ipairs(e.Trades) do
    local bucket=math.floor(t.Time/tf[2])*tf[2] local c=groups[bucket]
    if not c then c={Open=t.Price,High=t.Price,Low=t.Price,Close=t.Price,Volume=0} groups[bucket]=c end
    c.High=math.max(c.High,t.Price) c.Low=math.min(c.Low,t.Price) c.Close=t.Price c.Volume+=t.Quantity
   end
   for _,c in ipairs(e.Books.BX.Candles[tf[1]]) do for _,field in ipairs({"Open","High","Low","Close","Volume"}) do assert(c[field]==groups[c.Time][field],tf[1].." "..field) end end
  end
  e:Audit() return "OHLCV independently reconstructed for 1m, 5m, 15m, 1h and 1D"
 end)
 test("Daily quote baseline follows simulated days, timeframes and saved restores",function()
  local e=fresh()
  local function trade(price) place(e,"A",-1,1,price);place(e,"B",1,1) end
  local function quote(tf)return e:Snapshot("B","BX",tf or "1m",true).Quotes.BX end
  assert(quote().DayOpen==nil,"An untraded market has no daily opening price")
  trade(6000);e:AdvanceClock(86390);trade(5940)
  assert(quote().DayOpen==6000 and quote().DayStart==0)
  e:AdvanceClock(10)
  assert(quote().DayOpen==5940 and quote().DayStart==86400,"Day rollover must clear yesterday's change")
  trade(5500);trade(5400)
  for _,tf in ipairs(e.Config.Timeframes)do
   local q=quote(tf[1])
   assert(q.Open==6000 and q.DayOpen==5500 and q.Last==5400 and q.DayStart==86400,"Timeframe changed daily reference")
   assert(math.abs((q.Last-q.DayOpen)/q.DayOpen*100-(-100/5500*100))<1e-9)
  end
  assert(e:Snapshot("B","BX","1m",true).Quotes.BT.DayOpen==nil,"Instruments shared a daily reference")
  local checkpoint=require(script.Parent.WorldCheckpoint)
  local population={Engine=e,Config=e.Config,Random=Participants.RNG.new(e.Seed),Agents={}}
  local saved=checkpoint.Encode(checkpoint.Capture(e,population))
  e=checkpoint.Restore(checkpoint.Decode(saved),e.Config)
  assert(quote().DayOpen==5500 and quote().DayStart==86400,"Restore changed the current day's opening price")
  e:AdvanceClock(86400)
  assert(quote().DayOpen==5400 and quote().DayStart==172800)
  trade(5400);trade(5454)
  assert(quote().DayOpen==5400 and quote().Last==5454,"New day did not establish its own open")
  e:Audit();return "Negative/positive days, midnight, no trades, all timeframes and checkpoint restore passed"
 end)
 test("Seeded participants and identical step-indexed player actions reproduce",function()
  local function run(seed)
   local c=config() c.ParticipantsPerInstrument=12 c.MakersPerInstrument=3 c.WhalesPerInstrument=2
   local e=Engine.new(c,seed) local bots=Participants.new(e) e:AddAccount("P",50000,40,0.8,true)
   for i=1,1000 do
    if i==80 or i==220 or i==500 then e:Submit("P",{Contract="BX",Direction=i==220 and -1 or 1,Quantity=2,Type="Market",StopTicks=12,TargetTicks=20}) end
    if i==600 then e:Submit("P",{Contract="BT",Direction=-1,Quantity=1,Type="Limit",Price=(e.Books.BT.Last+10)*0.25}) end
    if i==680 then e:CancelAll("P") end
    bots:Step()
   end
   return e,e:Audit()
  end
  local a,aa=run(73521) local b,bb=run(73521) local c,cc=run(73522)
  assert(aa.Hash==bb.Hash and a.NextTrade==b.NextTrade and a.TotalVolume==b.TotalVolume)
  for i,t in ipairs(a.Trades) do local other=b.Trades[i] for _,field in ipairs({"Step","Price","Quantity","Buyer","Seller","Contract"}) do assert(t[field]==other[field],"Replay differs: "..field) end end
  assert(aa.Hash~=cc.Hash)
  for _,key in ipairs(a.Config.ContractOrder) do assert(a.Books[key].Up>0 and a.Books[key].Down>0,"Missing two-way market") end
  return {Seed=73521,Hash=aa.Hash,DifferentSeedHash=cc.Hash,Trades=a.NextTrade,Volume=a.TotalVolume,CashError=aa.CashError,EquityError=aa.EquityError}
 end)
 -- Regression for the price-spike exploit: a player's order used to rest in the participant book, so a
 -- thin moment let a participant sweep into a far limit, printing a candle at the player's price before
 -- makers re-centred (instant profit). Player orders are now off-book: the market must be identical with
 -- or without them, and a far limit fills only if the independent market actually trades there.
 test("Player executions consume shared liquidity and join the execution tape",function()
  local e=fresh();e:AddAccount("P",100000,100,.9,true)
  place(e,"A",-1,2,5825);local first=place(e,"P",1,3,5825)
  assert(first.Filled==2 and first.Remaining==1 and e.Books.BX.Bids[1].Quantity==1)
  place(e,"B",-1,1);assert(not e.Orders[first.Id]and e.Accounts.P.Positions.BX.Quantity==3)
  assert(e.TotalVolume==3 and #e.Trades==2 and e.Trades[1].Buyer=="P")
  assert(not e.Accounts[Engine.HouseId],"Player fill used a synthetic house counterparty")
  return e:Audit()
 end)
 local passed=0 for _,result in ipairs(report) do if result.Passed then passed+=1 end end
 return {Passed=passed,Total=#report,Results=report}
end
return Tests

