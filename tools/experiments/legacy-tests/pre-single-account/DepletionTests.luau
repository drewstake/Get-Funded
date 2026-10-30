-- Account-blown (depletion) notice, status and restart regression suite (server only).
-- Studio: StudioDiagnostics:Invoke("DepletionTests"). Uses isolated engines; never touches the live exchange.
local Engine=require(script.Parent.MarketEngine)
local Funded=require(script.Parent.FundedAccounts)
local Shared=game.ReplicatedStorage.MarketReign
local Default=require(Shared.MarketConfig)
local Ladder=require(Shared.ProgressionConfig)
local Tests={}
local function deep(v) if type(v)~="table" then return v end local r={} for k,x in pairs(v) do r[k]=deep(x) end return r end
local function exchange()
 local c=table.clone(Default) c.MaxTradeHistory=100000 c.MaxOrderHistory=100000
 local e=Engine.new(c,91)
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
local function place(e,id,side,qty,key,extra)
 local r={Action="Place",Contract=key or "BX",Direction=side,Quantity=qty,Type="Market"}
 for k,v in pairs(extra or {}) do r[k]=v end
 local ok,res=Funded.Perform(e,id,r) assert(ok,tostring(res)) return res,r
end
local function tier(view,id) local found;for _,row in ipairs(view.Accounts) do if row.Tier==id then found=row end end return found end
local function near(a,b,msg) assert(math.abs(a-b)<1e-6,(msg or "value").." expected "..b.." got "..a) end
local function depletions(events)
 local list={} for _,ev in ipairs(events or {}) do if ev.Kind=="Depleted" then table.insert(list,ev) end end return list
end
local function playerAccounts(e,uid)
 local n=0 for id in pairs(e.Accounts) do if id:sub(1,#("player:"..uid..":"))=="player:"..uid..":" then n+=1 end end return n
end

function Tests.Run()
 local report={} local function test(name,fn)
  local ok,result=pcall(fn) table.insert(report,{Name=name,Passed=ok,Detail=ok and result or tostring(result)})
 end
 test("Exactly $0 equity blows the account and announces it once",function()
  local e,f=exchange() f:Start("1") local id=f:Owner("1")
  quote(e,-1,5825,1) place(e,id,1,1) mark(e,5725)
  local a=e.Accounts[id] near(e:Summary(a).Equity,0,"equity") assert(a.Locked,"Zero equity did not deplete")
  local list=depletions(f:TakeEvents("1")) assert(#list==1,"Expected one depletion notice")
  local ev=list[1] assert(ev.Tier=="F5K:1" and ev.Name=="$5K FUNDED ACCOUNT" and ev.Event=="F5K:1" and ev.Attempt==1 and ev.Size==5000)
  near(ev.Equity,0,"event equity") assert(ev.Closing and not ev.CanRestart,"No liquidity yet: notice must report closing")
  quote(e,1,5725,1) e:AdvanceClock(.25)
  assert(not a.Positions.BX) near(a.Realized,-5000,"realized")
  local row=tier(f:View("1"),"F5K") assert(row.Depleted and row.Breached and not row.Closing and row.CanRestart and row.DepletionEvent=="F5K:1")
  assert(#depletions(f:TakeEvents("1"))==0,"Depletion announced twice")
  e:Audit()
  return "Equity $0.00 → notice F5K:1 (closing), then liquidated −$5,000, restart available, no repeat"
 end)
 test("Negative equity blows the account",function()
  local e,f=exchange() f:Start("2") local id=f:Owner("2")
  quote(e,-1,5825,1) place(e,id,1,1) mark(e,5700)
  local a=e.Accounts[id] near(e:Summary(a).Equity,-1250,"equity") assert(a.Locked)
  local ev=depletions(f:TakeEvents("2"))[1] assert(ev) near(ev.Equity,-1250,"event equity")
  quote(e,1,5700,1) e:AdvanceClock(.25) near(a.Realized,-6250,"realized") near(a.Balance,-1250,"balance")
  return "Equity −$1,250 → blown; liquidated at −$6,250 realized"
 end)
 test("Negative open P&L with positive equity is not blown",function()
  local e,f=exchange() f:Start("3") local id=f:Owner("3")
  quote(e,-1,5825,1) place(e,id,1,1) mark(e,5760) e:AdvanceClock(.25)
  local a=e.Accounts[id] near(e:Summary(a).Unrealized,-3250,"open P&L") near(e:Summary(a).Equity,1750,"equity")
  assert(not a.Locked and a.Positions.BX,"Positive equity liquidated")
  local row=tier(f:View("3"),"F5K") assert(not row.Depleted and not row.Breached and not row.CanRestart and row.Closing==nil)
  assert(#depletions(f:TakeEvents("3"))==0,"Notice raised for open loss")
  assert(not f:Restart("3","F5K"),"Restarted an account in good standing")
  return "Open P&L −$3,250 / equity $1,750: no notice, no restart"
 end)
 test("Liquidation reports closing status until it closes at the market price, then allows restart",function()
  local e,f=exchange() f:Start("4") local id=f:Owner("4") local a=e.Accounts[id]
  quote(e,-1,5825,3) place(e,id,1,3) mark(e,5790)
  -- Depletion latches on the reaching trade; the close runs on the next scheduler step.
  assert(a.Locked and a.Positions.BX.Quantity==3,"Position should be closing after the depleting trade")
  local row=tier(f:View("4"),"F5K") assert(row.Depleted and row.Closing and not row.CanRestart and row.Positions==1 and row.OpenContracts==3)
  local ok,msg=f:Restart("4","F5K") assert(not ok,"Restart allowed while closing")
  assert(#depletions(f:TakeEvents("4"))==1)
  local lastTick=e.Books.BX.Last
  e:AdvanceClock(.25) -- an empty bid side still closes, at the last market trade, without printing one
  row=tier(f:View("4"),"F5K") assert(not a.Positions.BX and not row.Closing and row.CanRestart and row.OpenContracts==0)
  assert(e.Books.BX.Last==lastTick,"Liquidation moved the market")
  assert(#depletions(f:TakeEvents("4"))==0,"Status changes re-announced the depletion")
  near(a.Realized,-5250,"realized")
  return "3 open (closing) → flat at the 5,790 market price in one step; restart only when flat; one notice"
 end)
 test("Restart succeeds once, restores capital and keeps losses/history",function()
  local e,f=exchange() f:Start("5") local id=f:Owner("5") local a=e.Accounts[id]
  quote(e,-1,5825,3) place(e,id,1,3) mark(e,5790) quote(e,1,5790,3) e:AdvanceClock(.25)
  assert(a.Locked and not a.Positions.BX) f:TakeEvents("5")
  local history=#a.History
  local ok1=f:Restart("5","F5K") local ok2,duplicate=f:Restart("5","F5K")
  assert(ok1 and not ok2 and playerAccounts(e,"5")==2,"Duplicate restart created another attempt")
  e:AdvanceClock(.25) assert(not f:Restart("5","F5K"),"Fresh attempt restarted again")
  local fresh=e.Accounts[f:Owner("5")] assert(fresh.Id~=id and fresh.Balance==5000 and fresh.Base==5000 and not fresh.Locked)
  assert(a.Retired and #a.History==history and a.Locked,"Earlier attempt was altered")
  local view=f:View("5") local row=tier(view,"F5K")
  assert(row.Attempt==2 and row.Balance==5000 and not row.Depleted and not row.CanRestart)
  near(view.Earned-row.Realized,-5250,"prior realized") near(view.Earned,-5250,"net realized")
  near(view.Next.Progress,0,"unlock progress") near(view.Next.Remaining,3000,"unlock remaining")
  quote(e,-1,5790,1) place(e,fresh.Id,1,1) mark(e,5690)
  local ev=depletions(f:TakeEvents("5"))[1] assert(ev and ev.Event=="F5K:2" and ev.Attempt==2,"New attempt's depletion not announced")
  return "Attempt 2 at $5,000; duplicate restart rejected; −$5,250 and history kept; attempt 2 has its own notice"
 end)
 test("A blown copy follower is removed; surviving instances keep trading and prevent free restarts",function()
  local e,f=exchange();f:Start("6");local p=f:Profile("6")
  p.Tiers.F10K={State="Unlocked",Claimed=false,Announced=true};assert(f:Activate("6","F10K"))
  local follower=f:Owner("6");local lead=p.Tiers.F10K.Account
  assert(f:SetCopy("6",{Enabled=1,Leader="F10K:1",Followers="F5K:1",Sizing="Same"}))
  quote(e,-1,5825,1);place(e,follower,1,1);mark(e,5725);e:AdvanceClock(.25);f:Evaluate("6")
  assert(e.Accounts[follower].Locked and not e.Accounts[lead].Locked)
  assert(not p.Copy.Enabled and #p.Copy.Followers==0 and not f:Restart("6","F5K:1"))
  assert(p.Tiers.F5K and p.Tiers.F10K and f:Select("6","F10K:1"))
  local before=e.Accounts[follower].Realized
  quote(e,-1,5725,1);place(e,lead,1,1);assert(not e.Accounts[follower].Positions.BX)
  near(e.Accounts[follower].Realized,before);e:Audit();return "Permanent access retained; copy membership follows usable instance identity"
 end)
 test("Depletion notice and free-restart state survive checkpoint/rejoin without duplicate events",function()
  local CP=require(script.Parent.WorldCheckpoint);local P=require(script.Parent.Participants)
  local e,f=exchange();f:Start("7");local id=f:Owner("7")
  quote(e,-1,5825,1);place(e,id,1,1);mark(e,5725);e:AdvanceClock(.25)
  assert(#depletions(f:TakeEvents("7"))==1)
  local pop=setmetatable({Engine=e,Config=e.Config,Random=P.RNG.new(81),Agents={}},P)
  local restored=CP.Restore(CP.Decode(CP.Encode(CP.Capture(e,pop))),Default);local g=Funded.new(restored,deep(Ladder),Default)
  g:Join("7");g:Evaluate("7");assert(#depletions(g:TakeEvents("7"))==0)
  assert(g:View("7").CanRestart and g:Restart("7","F5K:1"));assert(not g:Restart("7","F5K:1"))
  near(g:View("7").Next.Progress,0);near(g:View("7").Earned,-5000);restored:Audit()
  return "One notice per account instance; restart and retained losses persist"
 end)
 return report
end
return Tests
