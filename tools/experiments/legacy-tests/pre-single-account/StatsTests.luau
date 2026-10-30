-- Lifetime Stats regression suite (server only). Studio: StudioDiagnostics:Invoke("StatsTests").
-- Every case uses an isolated in-memory engine; the live exchange and saved data are never touched.
local Engine=require(script.Parent.MarketEngine)
local Funded=require(script.Parent.FundedAccounts)
local TradeStats=require(script.Parent.TradeStats)
local Shared=game.ReplicatedStorage.MarketReign
local Default=require(Shared.MarketConfig)
local Ladder=require(Shared.ProgressionConfig)
local StatsView=require(Shared.StatsView)
local Http=game:GetService("HttpService")
local Tests={}
local function deep(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=deep(x) end return r end
local function exchange(seed)
 local c=table.clone(Default) c.MaxTradeHistory=100000 c.MaxOrderHistory=100000
 local e=Engine.new(c,seed or 77)
 e:AddAccount("maker",1e9,100000,0.99,false) e:AddAccount("taker",1e9,100000,0.99,false)
 return e,Funded.new(e,deep(Ladder),c)
end
local function quote(e,side,price,qty,key)
 local ok,r=e:Submit("maker",{Contract=key or "BX",Direction=side,Quantity=qty,Type="Limit",Price=price}) assert(ok,tostring(r)) return r
end
-- Player fills are off-book and never consume quotes, so clear the fixture maker's quotes first: this
-- participant-to-participant print is what moves the market price.
local function mark(e,price,key)
 e:CancelAll("maker") quote(e,-1,price,1,key) local ok,r=e:Submit("taker",{Contract=key or "BX",Direction=1,Quantity=1,Type="Market"}) assert(ok and r.Filled==1,"mark failed")
end
local function place(e,id,side,qty,key)
 local ok,res=Funded.Perform(e,id,{Action="Place",Contract=key or "BX",Direction=side,Quantity=qty,Type="Market"}) assert(ok,tostring(res))
 assert(res.Filled==qty,"expected a full fill, got "..tostring(res.Filled)) return res
end
-- One round trip: open at entry, close at exit (both fully filled by the maker).
local function round(e,id,side,entry,exit,qty)
 quote(e,-side,entry,qty or 1) place(e,id,side,qty or 1) quote(e,side,exit,qty or 1) place(e,id,-side,qty or 1)
end
local function near(a,b,msg) assert(a~=nil and math.abs(a-b)<1e-6,(msg or "value").." expected "..tostring(b).." got "..tostring(a)) end
local function scope(stats,key) for _,x in ipairs(stats.Scopes) do if x.Key==key then return x end end for _,x in ipairs(stats.Legacy) do if x.Key==key then return x end end end
local function json(v) return Http:JSONEncode(v) end
-- Ledger reconciliation used by every case: stats agree with balances, realized totals, trade history and the
-- completed-trade counter, and the engine audit (which now also checks stats) passes.
local function reconcile(e,f,uid)
 local p=f:Profile(uid) local stats=f:Stats(uid) local all=scope(stats,"ALL").Life
 near(all.Net,f:Earned(p),"All funded net vs ledger")
 near(all.Net,all.Gains-all.Loss+all.UntrackedNet,"gains - losses + untracked")
 assert(all.Trades==all.Wins+all.Losses+all.Even,"classification")
 for _,id in ipairs(p.Ledger) do
  local a=e.Accounts[id] local s=a.Stats
  near(a.Realized,s.Gains-s.Loss+s.UntrackedNet,id.." stats vs realized")
  if s.Origin~="Partial" then
   assert((a.CompletedTrades or 0)==s.Trades,id.." counter "..tostring(a.CompletedTrades).." vs stats "..s.Trades)
   if #a.History<e.Config.MaxAccountHistory then
    local sum=0 for _,h in ipairs(a.History) do sum+=h.Pnl end
    near(sum,a.Realized,id.." history sum") assert(#a.History==s.Trades,id.." history rows vs trades")
   end
  end
 end
 e:Audit()
 return stats
end

function Tests.Run()
 local report={} local function test(name,fn)
  local ok,result=pcall(fn) table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})
 end
 test("Wins, losses and break-even trades",function()
  local e,f=exchange() f:Start("1") local id=f:Owner("1")
  round(e,id,1,5825,5827) -- +$100
  round(e,id,1,5830,5828.5) -- −$75
  round(e,id,1,5830,5830) -- $0.00
  round(e,id,-1,5830,5829) -- short +$50
  local all=scope(reconcile(e,f,"1"),"ALL").Life
  assert(all.Trades==4 and all.Wins==2 and all.Losses==1 and all.Even==1,"counts "..json(all))
  near(all.Gains,150,"gains") near(all.Loss,75,"losses") near(all.Net,75,"net") near(all.WinRate,.5,"win rate")
  near(all.Best,100,"best") near(all.Worst,-75,"worst") near(all.Average,18.75,"average") near(all.Open,0,"open") near(all.Total,75,"total")
  assert(all.Blown==0 and all.Attempts==1 and not all.Partial)
  -- Break-even is judged to the cent; exact P&L is still summed.
  local s=TradeStats.New() TradeStats.Add(s,{Pnl=0.004}) TradeStats.Add(s,{Pnl=-0.004}) TradeStats.Add(s,{Pnl=0.006})
  assert(s.Even==2 and s.Wins==1 and s.Losses==0) near(s.Gains-s.Loss,0.006,"sub-cent sum")
  return "+$100, −$75, $0.00, +$50 short → 4 trades, 2W/1L/1BE, gains $150, losses $75, net +$75, 50.0%, best +$100, worst −$75, avg +$18.75"
 end)
 test("Partial closes, multi-level closes and reversals follow the trade history",function()
  local e,f=exchange() f:Start("2") local id=f:Owner("2") local a=e.Accounts[id]
  quote(e,-1,5825,3) place(e,id,1,3)
  quote(e,1,5826,1) place(e,id,-1,1) -- partial close: 1 of 3
  assert(a.Stats.Trades==1 and a.Positions.BX.Quantity==2,"partial close")
  quote(e,1,5827,1) quote(e,1,5826.5,1) place(e,id,-1,2) -- off-book: one closing fill of 2 at the 5,827 bid
  assert(a.Stats.Trades==2 and #a.History==2 and a.History[1].Quantity==2 and not a.Positions.BX,"one-fill close")
  quote(e,-1,5830,1) place(e,id,1,1) quote(e,1,5829,3) place(e,id,-1,3) -- reversal: closes 1, opens short 2
  assert(a.Stats.Trades==3 and a.Positions.BX.Direction==-1 and a.Positions.BX.Quantity==2,"reversal")
  quote(e,-1,5828,2) place(e,id,1,2)
  local all=scope(reconcile(e,f,"2"),"ALL").Life
  assert(all.Trades==4 and all.Wins==3 and all.Losses==1,"counts "..json(all))
  near(all.Net,50+200-50+100,"net")
  return "Buy 3 · sell 1 (1 trade) · sell 2 at the bid (1 trade) · reversal (1) · cover (1) = 4 trades = 4 history rows, net +$300"
 end)
 test("Open P&L moves with the market without changing realized stats",function()
  local e,f=exchange() f:Start("3") local id=f:Owner("3")
  quote(e,-1,5825,1) place(e,id,1,1)
  local key=f:StatsKey("3")
  mark(e,5835) local all=scope(f:Stats("3"),"ALL").Life near(all.Open,500,"open up") near(all.Total,500,"total") assert(all.Trades==0)
  mark(e,5815) all=scope(f:Stats("3"),"ALL").Life near(all.Open,-500,"open down") near(all.Net,0,"net") near(all.Total,-500,"total down")
  near(scope(f:Stats("3"),"F5K").Current.Open,-500,"tier current open")
  assert(f:StatsKey("3")==key,"price moves must not trigger stats packets")
  quote(e,1,5815,1) place(e,id,-1,1)
  assert(f:StatsKey("3")~=key,"a close must trigger a stats packet")
  all=scope(reconcile(e,f,"3"),"ALL").Life near(all.Open,0,"flat") near(all.Net,-500,"realized") assert(all.Trades==1 and all.Losses==1)
  return "Open +$500 → −$500 (total follows, realized unchanged, no resend) → closed −$500, 1 losing trade"
 end)
 test("Copied trades count once per participating account",function()
  local e,f=exchange() f:Start("4")
  local p=f:Profile("4") p.Tiers.F10K={State="Unlocked",UnlockedAt=e.Time,Earned=0,Announced=true}
  local gainsBefore=scope(f:Stats("4"),"ALL").Life.Gains
  assert(f:Activate("4","F10K")) assert(f:SetCopy("4",{Enabled=1,Leader="F10K:1",Followers="F5K:1",Sizing="Same"}))
  near(scope(f:Stats("4"),"ALL").Life.Gains,gainsBefore,"activation capital is not a gain")
  local lead=p.Tiers.F10K.Account local follower=p.Tiers.F5K.Account
  local function leadAction(req)
   local plan=f:Plan("4",lead) local context=f:Context(lead,req) -- captured before the lead acts, as MarketServer does
   local ok,res=Funded.Perform(e,lead,req) local report=f:Mirror(plan,req,ok,res,context) assert(ok,tostring(res)) return report
  end
  quote(e,-1,5825,2) local r1=leadAction({Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market"}) assert(r1.Copied==1)
  quote(e,1,5830,2) local r2=leadAction({Action="Close",Contract="BX"}) assert(r2.Copied==1)
  for _=1,3 do f:Stats("4") Funded.new(e,deep(Ladder),e.Config) end -- repeated reads and rebuilds
  local stats=reconcile(e,f,"4")
  assert(scope(stats,"ALL").Life.Trades==2,"one trade per participating account")
  assert(scope(stats,"F10K").Life.Trades==1 and scope(stats,"F5K").Life.Trades==1)
  assert(e.Accounts[lead].Stats.Trades==1 and e.Accounts[follower].Stats.Trades==1)
  near(scope(stats,"ALL").Life.Net,500,"two accounts × +$250")
  return "Lead $10K + follower $5K: 1 trade each, All funded 2 trades / +$500; activation capital not a gain"
 end)
 test("Repeated depletion updates count each blown attempt once",function()
  local e,f=exchange() f:Start("5") local id=f:Owner("5") local a=e.Accounts[id]
  quote(e,-1,5825,1) place(e,id,1,1) mark(e,5725)
  assert(a.Locked and a.Depleted,"depletion latched")
  for _=1,3 do f:TakeEvents("5") e:AdvanceClock(.25) TradeStats.Reconcile(e,a,os.time()) end
  f=Funded.new(e,deep(Ladder),e.Config) -- rebuild (restore / reconnect path)
  quote(e,1,5725,1) for _=1,3 do e:AdvanceClock(.25) f:TakeEvents("5") end
  assert(not a.Positions.BX,"liquidated")
  local all=scope(reconcile(e,f,"5"),"ALL").Life
  assert(all.Blown==1 and all.Attempts==1,"blown "..all.Blown)
  near(all.Net,-5000,"net") assert(all.Trades==1 and all.Losses==1)
  return "Equity $0 → 3× notices/steps/reconciles + rebuild + liquidation: 1 blown attempt, −$5,000, 1 trade"
 end)
 test("Restarts keep lifetime losses and blown attempts; current attempt starts fresh",function()
  local e,f=exchange() f:Start("6") local first=f:Owner("6")
  quote(e,-1,5825,1) place(e,first,1,1) mark(e,5725) quote(e,1,5725,1) e:AdvanceClock(.25) f:TakeEvents("6")
  assert(f:Restart("6","F5K")) assert(not f:Restart("6","F5K"),"duplicate restart")
  local second=f:Owner("6")
  local stats=reconcile(e,f,"6") local tier=scope(stats,"F5K")
  assert(tier.Life.Attempts==2 and tier.Life.Blown==1,"lifetime attempts")
  assert(tier.Current.Attempts==1 and tier.Current.Blown==0 and tier.Current.Trades==0,"current attempt")
  near(tier.Life.Net,-5000,"lifetime keeps the loss") near(tier.Current.Net,0,"fresh attempt") near(tier.Life.Gains,0,"restart capital is not a gain")
  round(e,second,1,5725,5726)
  stats=reconcile(e,f,"6") tier=scope(stats,"F5K")
  assert(tier.Life.Trades==2 and tier.Current.Trades==1) near(tier.Life.Net,-4950,"lifetime net") near(tier.Current.Net,50,"current net")
  quote(e,-1,5726,1) place(e,second,1,1) mark(e,5625) quote(e,1,5625,1) e:AdvanceClock(.25)
  stats=reconcile(e,f,"6")
  assert(scope(stats,"ALL").Life.Blown==2 and scope(stats,"ALL").Current.Blown==0,"second depletion")
  return "Attempt 1 blown −$5,000; restart → lifetime 2 attempts/1 blown/−$5,000, current 0 trades; +$50; attempt 2 blown → lifetime 2 blown"
 end)
 test("Display-history trimming never erases lifetime totals",function()
  local e,f=exchange() f:Start("7") local id=f:Owner("7") local a=e.Accounts[id]
  for i=1,75 do round(e,id,1,5825,i%3==0 and 5824 or 5826) end -- 50 wins of +$50, 25 losses of −$50
  assert(#a.History==e.Config.MaxAccountHistory,"history is bounded")
  local all=scope(reconcile(e,f,"7"),"ALL").Life
  assert(all.Trades==75 and all.Wins==50 and all.Losses==25 and not all.Partial,"counts "..json(all))
  near(all.Net,1250,"net") near(a.Realized,1250,"ledger")
  return "75 closes with 60 retained rows: 75 trades, 50W/25L, net +$1,250 = ledger"
 end)
 test("Migration rebuilds complete history exactly and labels incomplete history",function()
  local e,f=exchange() f:Start("8") local id=f:Owner("8") local a=e.Accounts[id]
  for i=1,12 do round(e,id,1,5825,i%4==0 and 5825 or i%2==0 and 5824 or 5827) end
  local live=json(a.Stats)
  a.Stats=nil a.CompletedTrades=nil -- an account saved before stats (and before the completed-trade counter)
  f=Funded.new(e,deep(Ladder),e.Config)
  local rebuilt=a.Stats assert(rebuilt.Origin=="Recovered","origin "..tostring(rebuilt.Origin))
  local want=Http:JSONDecode(live)
  for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","Best","Worst","LastTradeId"}) do assert(math.abs((want[k] or 0)-(rebuilt[k] or 0))<1e-6,k.." differs after rebuild") end
  local stats=reconcile(e,f,"8") assert(scope(stats,"ALL").Life.Recovered and not scope(stats,"ALL").Life.Partial)
  -- Trimmed history with a trustworthy counter: 75 closes, 60 retained rows.
  local e2,f2=exchange(78) f2:Start("9") local id2=f2:Owner("9") local b=e2.Accounts[id2]
  for i=1,75 do round(e2,id2,1,5825,i<=10 and 5820 or 5826) end -- first 10 lose −$250 each (trimmed away)
  b.Stats=nil
  f2=Funded.new(e2,deep(Ladder),e2.Config)
  local s2=b.Stats assert(s2.Origin=="Partial" and s2.Trades==60 and s2.UntrackedTrades==15 and s2.CountUnknown,"partial "..json(s2))
  local sum=0 for _,h in ipairs(b.History) do sum+=h.Pnl end near(s2.UntrackedNet,b.Realized-sum,"untracked net")
  local all2=scope(reconcile(e2,f2,"9"),"ALL").Life
  near(all2.Net,b.Realized,"net stays the ledger value") assert(all2.Partial and all2.AverageScope=="Tracked")
  local note=StatsView.Coverage(all2,function(v) return string.format("%+.2f",v) end)
  assert(note and note:find("at least 15 earlier trades") and note:find("remain in Total P&L"),"coverage label: "..tostring(note))
  -- Trimmed history without any counter: the count is unknown and said so.
  b.Stats=nil b.CompletedTrades=nil TradeStats.Reconcile(e2,b,os.time())
  assert(b.Stats.Origin=="Partial" and b.Stats.UntrackedTrades==0 and b.Stats.CountUnknown)
  assert(StatsView.Coverage(TradeStats.Finish(TradeStats.Include(TradeStats.Empty(),e2,b)),tostring):find("unknown number"))
  -- Idempotent: repeated restores/rebuilds never change migrated stats.
  local snapshot=json(b.Stats)
  for _=1,3 do TradeStats.Reconcile(e2,b,os.time()+100) Funded.new(e2,deep(Ladder),e2.Config) end
  assert(json(b.Stats)==snapshot,"migration is not idempotent")
  return {Complete="12 trades rebuilt exactly (Recovered)",Trimmed="60 tracked + 15 earlier (≥, net "..string.format("%.2f",s2.UntrackedNet)..") labelled",NoCounter="unknown count labelled",Idempotent=true}
 end)
 test("Saved blown attempts migrate once; old loss-limit breaches are not blown",function()
  local e,f=exchange() f:Start("10") local p=f:Profile("10")
  local id=f:Owner("10") local a=e.Accounts[id]
  quote(e,-1,5825,1) place(e,id,1,1) mark(e,5724) quote(e,1,5724,1) e:AdvanceClock(.25) assert(f:Restart("10","F5K"))
  local b=e.Accounts[f:Owner("10")]
  round(e,b.Id,1,5724,5720) -- a breach under the old rules left most capital; simulate the old lock + restart
  b.Locked=true assert(f:Restart("10","F5K"),"restart old-rule breach")
  for _,acct in ipairs({a,b}) do acct.Depleted=nil acct.DepletedAt=nil acct.Breached=nil acct.Stats=nil end
  for _=1,2 do f=Funded.new(e,deep(Ladder),e.Config) end
  assert(a.Depleted and not a.Breached and b.Breached and not b.Depleted,"classification")
  local life=scope(reconcile(e,f,"10"),"F5K").Life
  assert(life.Attempts==3 and life.Blown==1 and life.Breached==1,"blown "..life.Blown.." breached "..life.Breached)
  assert(StatsView.Describe(scope(f:Stats("10"),"F5K"),life,"Life"):find("old loss%-limit rules"))
  return "Retired attempt at −$50 → blown; retired attempt at $4,800 (old loss-limit rule) → reported separately; 3 attempts, 1 blown"
 end)
 test("Drift from an older server build is repaired without double counting",function()
  local e,f=exchange() f:Start("11") local id=f:Owner("11") local a=e.Accounts[id]
  round(e,id,1,5825,5826)
  local saved=deep(a.Stats)
  round(e,id,1,5826,5828) round(e,id,1,5828,5827)
  a.Stats=saved -- as if an older build had traded (history, realized, counter) without updating stats
  assert(a.Stats.Trades==1 and a.CompletedTrades==3)
  f=Funded.new(e,deep(Ladder),e.Config) f=Funded.new(e,deep(Ladder),e.Config)
  assert(a.Stats.Trades==3 and a.Stats.Origin=="Live","retained rows picked up once: "..json(a.Stats))
  -- A realized change with no retained row (trimmed) moves into the labelled remainder.
  a.Realized+=25 a.Balance+=25 a.CompletedTrades+=1
  e.Accounts.maker.Realized-=25 e.Accounts.maker.Balance-=25 -- keep the exchange's P&L conserved
  f=Funded.new(e,deep(Ladder),e.Config)
  assert(a.Stats.Origin=="Partial" and a.Stats.UntrackedTrades==1) near(a.Stats.UntrackedNet,25,"remainder")
  reconcile(e,f,"11")
  return "2 trades written by an older build recovered from history once; an untraceable +$25 kept as a labelled remainder"
 end)
 test("Legacy archives are inaccessible and excluded from funded statistics",function()
  local e,f=exchange();local id="player:12:50000";local a=e:AddAccount(id,50000,100,Ladder.MarginUse,true)
  round(e,id,1,5825,5830)
  f=Funded.new(e,deep(Ladder),e.Config);assert(not f:Select("12","L50000") and a.LegacyRetired)
  f:Start("12");round(e,f:Owner("12"),1,5825,5824)
  local stats=reconcile(e,f,"12");local all=scope(stats,"ALL").Life
  assert(all.Trades==1 and not stats.Legacy);near(all.Net,-50,"funded net excludes retired legacy profit")
  return "Retained legacy +$250 excluded; funded -$50 and one trade retained"
 end)
 if typeof(game)=="Instance" then
  test("Checkpoint round trips, reconnects and repeated restores keep stats identical",function()
   local Checkpoint=require(script.Parent.WorldCheckpoint) local Participants=require(script.Parent.Participants)
   local e=Engine.new(Default,4545) local population=Participants.new(e) for _=1,300 do population:Step() end
   e:AddAccount("t:maker",1e9,100000,0.99,false)
   local f=Funded.new(e,deep(Ladder),Default) f:Start("13") local id=f:Owner("13")
   for i=1,4 do
    local last=e.Books.BX.Last*e.Books.BX.Spec.Tick
    assert(e:Submit("t:maker",{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=last+1}))
    assert(select(1,e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market"})))
    for _=1,20 do population:Step() end
    assert(select(1,Funded.Perform(e,id,{Action="Close",Contract="BX"}))) for _=1,20 do population:Step() end
   end
   local before=json(f:Stats("13"))
   local function roundTrip(engine,pop)
    return Checkpoint.Restore(Checkpoint.Decode(Http:JSONDecode(Http:JSONEncode(Checkpoint.Encode(Checkpoint.Capture(engine,pop))))),Default)
   end
   local r1,p1=roundTrip(e,population) local r2=roundTrip(r1,p1)
   local g=Funded.new(r2,deep(Ladder),Default)
   local afterStats=g:Stats("13")
   -- Open P&L is recomputed from the restored book; every counted value must be identical.
   local a,b=Http:JSONDecode(before),Http:JSONDecode(json(afterStats))
   for _,k in ipairs({"Trades","Wins","Losses","Even","Gains","Loss","Net","Blown","Attempts","Best","Worst"}) do
    assert(math.abs((a.Scopes[1].Life[k] or 0)-(b.Scopes[1].Life[k] or 0))<1e-6,k.." changed across restore")
   end
   assert(g:StatsKey("13")==f:StatsKey("13"),"signature changed across restore (would resend/double count)")
   reconcile(r2,g,"13")
   return {Trades=b.Scopes[1].Life.Trades,Net=b.Scopes[1].Life.Net,RoundTrips=2}
  end)
 end
 return report
end
return Tests
