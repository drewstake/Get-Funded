-- Funded-account ladder, onboarding and copy-trading regression suite (server only).
-- Studio: StudioDiagnostics:Invoke("FundedTests"). Uses isolated engines; never touches the live exchange.
local Engine=require(script.Parent.MarketEngine)
local Funded=require(script.Parent.FundedAccounts)
local Shared=game.ReplicatedStorage.MarketReign
local Default=require(Shared.MarketConfig)
local Ladder=require(Shared.ProgressionConfig)
local Tests={}
local function deep(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=deep(x) end return r end
local function progression(unlocks)
 local c=deep(Ladder)
 for id,value in pairs(unlocks or {}) do for _,t in ipairs(c.Tiers) do if t.Id==id then t.Unlock=value end end end
 return c
end
local function exchange(unlocks)
 local c=table.clone(Default) c.MaxTradeHistory=100000 c.MaxOrderHistory=100000
 local e=Engine.new(c,55)
 e:AddAccount("maker",1e9,100000,0.99,false) e:AddAccount("taker",1e9,100000,0.99,false)
 return e,Funded.new(e,progression(unlocks),c)
end
local function quote(e,side,price,qty,key)
 local ok,r=e:Submit("maker",{Contract=key or "BX",Direction=side,Quantity=qty,Type="Limit",Price=price}) assert(ok,tostring(r)) return r
end
-- One bot-to-bot execution moves the last traded price. Player fills are off-book and never consume
-- quotes, so the fixture maker's quotes are cleared first.
local function mark(e,price,key)
 e:CancelAll("maker") quote(e,-1,price,1,key) local ok,r=e:Submit("taker",{Contract=key or "BX",Direction=1,Quantity=1,Type="Market"}) assert(ok and r.Filled==1,"mark failed")
end
local function place(e,id,side,qty,key,extra)
 local r={Action="Place",Contract=key or "BX",Direction=side,Quantity=qty,Type="Market"}
 for k,v in pairs(extra or {}) do r[k]=v end
 local ok,res=Funded.Perform(e,id,r) assert(ok,tostring(res)) return res,r
end
local function playerAccounts(e,uid)
 local n=0 for id in pairs(e.Accounts) do if id:sub(1,#("player:"..uid..":"))=="player:"..uid..":" then n+=1 end end return n
end
local function tier(view,id)
 for _,row in ipairs(view.Accounts) do if row.Tier==id then return row end end
 for _,row in ipairs(view.Tiers) do if row.Key==id then return row end end
end
local function near(a,b) return math.abs(a-b)<1e-6 end

function Tests.Run()
 local report={} local function test(name,fn)
  local ok,result=pcall(fn) table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})
 end
 test("First join creates nothing; Start creates exactly one $5K starter",function()
  local e,f=exchange()
  assert(f:Join("101")==nil and f:Owner("101")==nil and f:View("101").New,"New player received an implicit account")
  local ok,_,created=f:Start("101") assert(ok and created)
  local again,_,createdAgain=f:Start("101") assert(again and not createdAgain,"Second Start created an account")
  f:Start("101") assert(playerAccounts(e,"101")==1,"Duplicate starter account")
  local a=e.Accounts[f:Owner("101")]
  assert(a.Base==5000 and a.Balance==5000 and a.LossLimit==5000 and a.Limit==5 and a.Group=="player:101")
  local v=f:View("101")
  assert(v.Started and v.Active=="F5K:1" and v.Capital==5000 and v.Earned==0 and v.Tutorial=="Pending" and v.Next.Key=="F10K")
  assert(not v.Copy.Enabled and not v.CopyAvailable,"Copy trading must start off")
  assert(f:Flag("101","TutorialSkipped") and f:View("101").Tutorial=="Skipped")
  return "One starter account; repeated Start is idempotent; tutorial state saved"
 end)
 test("Only net realized profit unlocks; starting balance and open P&L never count",function()
  local e,f=exchange() f:Start("7") local id=f:Owner("7")
  quote(e,-1,5825,2) place(e,id,1,2)
  mark(e,5900)
  assert(e:Summary(e.Accounts[id]).Unrealized>700,"Expected a large open gain")
  f:Evaluate("7") assert(f:View("7").Earned==0 and tier(f:View("7"),"F10K").State=="Locked","Unrealized gain unlocked an account")
  assert(f:TakeEvents("7")==nil)
  quote(e,1,5855,2) assert(Funded.Perform(e,id,{Action="Close",Contract="BX"}))
  assert(near(e.Accounts[id].Realized,3000) and near(e.Accounts[id].Balance,8000))
  f:Evaluate("7") local v=f:View("7")
  assert(near(v.Earned,3000),"Earned must exclude the $5,000 starting balance")
  assert(tier(v,"F10K").State=="Unlocked" and tier(v,"F25K").State=="Locked" and v.Next.Key=="F25K")
  local events=f:TakeEvents("7")
  assert(events and #events==2 and events[1].Kind=="FirstProfit" and events[2].Kind=="Unlocked" and events[2].Tier=="F10K")
  f:Evaluate("7") assert(f:TakeEvents("7")==nil,"Unlock announced twice")
  local saved=f:Profile("7").Tiers.F10K.UnlockedAt f:Evaluate("7") assert(f:Profile("7").Tiers.F10K.UnlockedAt==saved)
  return "Open +$7,500 did not unlock; realized +$3,000 unlocked $10K once"
 end)
 test("Activation needs an unlock, never duplicates, and switching changes the trading account",function()
  local e,f=exchange({F10K=1}) f:Start("8") local id=f:Owner("8")
  assert(not f:Activate("8","F10K"),"Activated a locked tier")
  quote(e,-1,5825,1) place(e,id,1,1) quote(e,1,5826,1) Funded.Perform(e,id,{Action="Close",Contract="BX"}) f:Evaluate("8")
  assert(not f:Activate("8","F25K"))
  assert(f:Activate("8","F10K")) local n=playerAccounts(e,"8")
  assert(f:Activate("8","F10K") and playerAccounts(e,"8")==n,"Second activation created another account")
  assert(f:Owner("8")==id,"Activation must not silently switch the traded account")
  assert(f:Select("8","F10K:1")) local ten=f:Owner("8") assert(ten~=id and e.Accounts[ten].Base==10000 and e.Accounts[ten].LossLimit==10000)
  assert(not f:Select("8","F25K:1") and not f:Select("8","L50000") and f:Owner("8")==ten)
  assert(f:Select("8","F5K:1") and f:Owner("8")==id)
  local v=f:View("8") assert(v.ActiveCount==2 and v.Capital==15000 and near(v.Earned,50) and v.CopyAvailable)
  return "Locked/duplicate activation rejected; switching F5K <-> F10K works"
 end)
 test("Copy trading: off by default, explicit lead/followers, per-account limits, clear reports",function()
  local e,f=exchange({F10K=1,F25K=2}) f:Start("9") local five=f:Owner("9")
  assert(not f:SetCopy("9",{Enabled=1,Leader="F5K:1",Followers="F10K:1"}),"Copy enabled with one account")
  quote(e,-1,5825,1) place(e,five,1,1) quote(e,1,5827,1) Funded.Perform(e,five,{Action="Close",Contract="BX"}) f:Evaluate("9")
  assert(f:Activate("9","F10K") and f:Activate("9","F25K"))
  local lead,twentyFive=f:Resolve("9","F10K:1"),f:Resolve("9","F25K:1")
  assert(f:Plan("9",lead)==nil,"Copy active before being enabled")
  assert(not f:SetCopy("9",{Enabled=1,Leader="F10K:1",Followers="F50K:1"}))
  assert(not f:SetCopy("9",{Enabled=1,Leader="F10K:1",Followers="F10K:1"}),"Leader cannot follow itself")
  assert(f:SetCopy("9",{Enabled=1,Leader="F10K:1",Followers="F25K:1,F5K:1",Sizing="Same"}))
  local v=f:View("9") assert(v.Copy.Enabled and table.find(v.Copy.Followers,"F5K:1") and tier(v,"F10K").Role=="Lead" and tier(v,"F25K").Role=="Follow")
  quote(e,-1,20485.5,20,"BT")
  local plan=f:Plan("9",lead)
  -- A reduced balance never reduces a follower's contract limit (5 on the $5K).
  e.Accounts[five].Balance=2500
  local res,req=place(e,lead,1,3,"BT",{StopTicks=40,TargetTicks=80})
  local copies=f:Mirror(plan,req,true,res,f:Context(lead,req))
  assert(copies.Total==2 and copies.Copied==2 and copies.Rejected==0,"Expected both copies (no margin sizing)")
  local fp=e.Accounts[twentyFive].Positions.BT assert(fp and fp.Quantity==3 and fp.Stop and fp.Target,"Follower copy missing")
  assert(e.Accounts[five].Positions.BT and e.Accounts[five].Positions.BT.Quantity==3,"Low-balance follower was not copied")
  -- The only limit is the contract count: a further 3 would exceed the $5K's 5.
  local only for _,item in ipairs(plan.Followers) do if item.Key=="F5K:1" then only=item end end
  local over=f:Mirror({Leader=plan.Leader,Followers={only},Sizing="Same"},{Action="Place",Contract="BT",Direction=1,Quantity=3,Type="Market"},true,res,{})
  assert(over.Rejected==1 and over.Items[1].Message:find("Maximum currently available: 2 BT",1,true),"Rejected copy must carry the engine reason")
  -- Linked limit orders are cancelled together.
  local limit,limitReq=place(e,lead,1,1,"BX",{Type="Limit",Price=5800})
  local placed=f:Mirror(plan,limitReq,true,limit,f:Context(lead,limitReq)) assert(placed.Copied==2)
  local linked=0 for _,o in pairs(e.Orders) do if o.Link==limit.Id then linked+=1 end end assert(linked==2)
  local cancelReq={Action="Cancel",OrderId=limit.Id} local context=f:Context(lead,cancelReq)
  local cancelOk,cancelResult=Funded.Perform(e,lead,cancelReq) local cancelled=f:Mirror(plan,cancelReq,cancelOk,cancelResult,context)
  assert(cancelled.Copied==2 and next(e.Accounts[twentyFive].OpenOrders)==nil and next(e.Accounts[five].OpenOrders)==nil)
  -- Protection moves follow the lead price; followers without that position are skipped.
  local stop=e.Accounts[lead].Positions.BT.Stop-5
  local amend={Action="AmendProtection",Contract="BT",OrderId=e.Accounts[lead].Positions.BT.Id,Protection="Stop",Price=stop,ExpectedPrice=e.Accounts[lead].Positions.BT.Stop}
  context=f:Context(lead,amend) local amendOk,amendResult=Funded.Perform(e,lead,amend) assert(amendOk,amendResult)
  local amended=f:Mirror(plan,amend,true,amendResult,context)
  assert(amended.Copied==2 and amended.Skipped==0 and e.Accounts[twentyFive].Positions.BT.Stop==stop and e.Accounts[five].Positions.BT.Stop==stop)
  -- Closing the lead closes matching copies only.
  quote(e,1,20480,10,"BT")
  local closeReq={Action="Close",Contract="BT"} context=f:Context(lead,closeReq)
  local closeOk,closeResult=Funded.Perform(e,lead,closeReq)
  local closed=f:Mirror(plan,closeReq,closeOk,closeResult,context)
  assert(closed.Copied==2 and closed.Skipped==0 and not e.Accounts[twentyFive].Positions.BT and not e.Accounts[five].Positions.BT and not e.Accounts[lead].Positions.BT)
  -- A rejected lead copies nothing.
  local badReq={Action="Place",Contract="BX",Direction=1,Quantity=50,Type="Market"}
  local badOk,badResult=Funded.Perform(e,lead,badReq) assert(not badOk)
  local none=f:Mirror(plan,badReq,badOk,badResult,{}) assert(none.Copied==0 and none.Skipped==2)
  return "Both copied (low balance does not limit size); over-limit copy rejected with the engine reason; linked cancel, SL move and close mirrored"
 end)
 test("Disabling copy keeps every position; accounts then trade independently",function()
  local e,f=exchange({F10K=1}) f:Start("11") local five=f:Owner("11")
  quote(e,-1,5825,1) place(e,five,1,1) quote(e,1,5827,1) Funded.Perform(e,five,{Action="Close",Contract="BX"}) f:Evaluate("11")
  f:Activate("11","F10K") local ten=f:Resolve("11","F10K:1")
  assert(f:SetCopy("11",{Enabled=1,Leader="F5K:1",Followers="F10K:1"}))
  quote(e,-1,5830,4) local plan=f:Plan("11",five)
  local res,req=place(e,five,1,1,"BX",{StopTicks=40}) f:Mirror(plan,req,true,res,f:Context(five,req))
  local before=table.clone(e.Accounts[ten].Positions.BX)
  local ok,message=f:SetCopy("11",{Enabled=0}) assert(ok and message:find("positions"))
  local after=e.Accounts[ten].Positions.BX
  assert(after and after.Quantity==before.Quantity and after.Entry==before.Entry and after.Stop==before.Stop,"Disabling copy changed a follower position")
  assert(f:Plan("11",five)==nil)
  quote(e,1,5829,2) Funded.Perform(e,five,{Action="Close",Contract="BX"})
  assert(not e.Accounts[five].Positions.BX and e.Accounts[ten].Positions.BX,"Independent close affected the other account")
  place(e,ten,1,1) assert(e.Accounts[ten].Positions.BX.Quantity==2 and f:Plan("11",ten)==nil)
  return "Follower kept its position and SL; later trades stayed independent"
 end)
 test("One player's accounts never trade against each other: player fills are off-book",function()
  local e,f=exchange({F10K=1}) f:Start("12") local five=f:Owner("12")
  quote(e,-1,5825,1) place(e,five,1,1) quote(e,1,5827,1) Funded.Perform(e,five,{Action="Close",Contract="BX"}) f:Evaluate("12")
  f:Activate("12","F10K") local ten=f:Resolve("12","F10K:1")
  local trades=#e.Trades
  local own=place(e,five,-1,1,"BX",{Type="Limit",Price=5830}) e:CancelAll("maker") quote(e,-1,5831,1)
  local fill=place(e,ten,1,1)
  assert(fill.Filled==1 and fill.Average==5831 and e.Orders[own.Id],"The other account's sell limit was touched")
  assert(#e.Trades==trades and #e.Books.BX.Bids==0,"Player orders reached the book or printed a trade")
  mark(e,5830) assert(not e.Orders[own.Id] and e.Accounts[five].Positions.BX.Direction==-1,"Sell limit did not fill when the market reached it")
  e:Audit()
  return "Buy filled at the 5,831 market ask; the same player's 5,830 sell limit filled only when the market traded 5,830"
 end)
 test("Legacy accounts retire without funded access or accounting loss",function()
  local e,f=exchange();local id="player:42:50000";local a=e:AddAccount(id,50000,40,.8,true)
  quote(e,-1,5825,1);place(e,id,1,1);quote(e,1,5826,1)
  f=Funded.new(e,progression(),e.Config)
  assert(a.LegacyRetired and a.Retired and not next(a.Positions) and not f:Resolve("42","L50000"))
  assert(f:Start("42"));assert(f:View("42").Earned==0 and #f:View("42").Accounts==1)
  e:Audit();return "Obsolete exposure closed, archive retained, funded capital and profit excluded"
 end)
 test("Depleted accounts restart with fresh capital; losses stay in history but not in unlock progress",function()
  local e,f=exchange() f:Start("5") local id=f:Owner("5")
  quote(e,-1,5825,3) place(e,id,1,3) mark(e,5790)
  assert(not f:Restart("5","F5K"),"Restarted before liquidation finished")
  quote(e,1,5790,3) e:AdvanceClock(0.25)
  local a=e.Accounts[id] assert(a.Locked and not a.Positions.BX and near(a.Realized,-5250),"Loss limit did not liquidate")
  assert(not select(1,e:Submit(id,{Contract="BX",Direction=1,Quantity=1,Type="Market"})),"Depleted account accepted an entry")
  assert(f:Restart("5","F5K")) local fresh=f:Owner("5")
  assert(fresh~=id and e.Accounts[fresh].Balance==5000 and not e.Accounts[fresh].Locked and playerAccounts(e,"5")==2)
  local v=f:View("5") assert(near(v.Earned,-5250),"Restart erased the lifetime realized record")
  assert(near(v.Next.Progress,0) and near(v.Next.Remaining,3000),"Blown losses carried into unlock progress")
  assert(not f:Restart("5","F5K"))
  return "Loss -$5,250 kept in lifetime net profit; attempt 2 active at $0 / $3,000"
 end)
 test("Copy sizing: exact same/proportional quantity, validated by follower engine",function()
  assert(Funded.Size(3,10000,25000,"Same",20)==3)
  assert(Funded.Size(3,10000,25000,"Proportional",20)==7 and Funded.Size(3,10000,5000,"Proportional",20)==1)
  assert(Funded.Size(1,10000,5000,"Proportional",20)==0 and Funded.Size(15,5000,100000,"Proportional",20)==300)
  return "3→7 at 2.5x, 1→0 skipped; excess sizing reaches server validation"
 end)
 test("Ladder configuration is validated",function()
  local bad=progression() bad.Tiers[2].Unlock=0 assert(not pcall(Funded.Validate,bad))
  bad=progression() bad.Tiers[3].Size=1000 assert(not pcall(Funded.Validate,bad))
  Funded.Validate(progression())
  return "Non-ascending sizes and a second free tier are rejected"
 end)
 if typeof(game)=="Instance" then
  test("Checkpoint v6 keeps profiles; v1 checkpoints restore and migrate",function()
   local Checkpoint=require(script.Parent.WorldCheckpoint) local Participants=require(script.Parent.Participants)
   local http=game:GetService("HttpService")
   local e=Engine.new(Default,4242) local population=Participants.new(e) for _=1,300 do population:Step() end
   e:AddAccount("player:88:50000",50000,40,0.8,true)
   local legacyOnly=Checkpoint.Capture(e,population)
   local f=Funded.new(e,progression(),Default) f:Join("88") f:Start("88")
   f:Profile("88").Tiers.F10K={State="Unlocked",UnlockedAt=e.Time,Earned=300,Announced=true}
   f:Activate("88","F10K") f:SetCopy("88",{Enabled=1,Leader="F10K:1",Followers="F5K:1",Sizing="Proportional"}) f:Flag("88","TutorialDone")
   local encoded=http:JSONDecode(http:JSONEncode(Checkpoint.Encode(Checkpoint.Capture(e,population))))
   assert(encoded.Version==Checkpoint.Version and Checkpoint.Version==7)
   local restored=Checkpoint.Restore(Checkpoint.Decode(encoded),Default)
   local g=Funded.new(restored,progression(),Default)
   local a,b=f:View("88"),g:View("88")
   assert(b.Copy.Enabled and b.Copy.Leader=="F10K:1" and b.Copy.Sizing=="Proportional" and b.Tutorial=="Done" and b.ActiveCount==2)
   assert(a.Revision==b.Revision and g:Owner("88")==f:Owner("88") and tier(b,"F10K").State=="Active")
   g:Evaluate("88") assert(g:TakeEvents("88")==nil,"Restored unlock announced again")
   legacyOnly.Version=1 legacyOnly.Engine.Profiles=nil
   local old=Checkpoint.Restore(Checkpoint.Decode(Checkpoint.Encode(legacyOnly)),Default)
   local h=Funded.new(old,progression(),Default)
   local p=h:Join("88") assert(p and p.Migrated and h:Owner("88")==nil and old.Accounts["player:88:50000"].LegacyRetired and old.Accounts["player:88:50000"].Balance==50000)
   old:Audit() restored:Audit()
   return {V3Bytes=#encoded.Payload,Profiles=1,V1Migrated=true}
  end)
 end
 return report
end
return Tests
