local Liquidity=require(script.Parent.TestLiquidity)
-- Isolated regression checks: no live accounts, DataStores or remotes.
local E=require(script.Parent.MarketEngine)
local F=require(script.Parent.FundedAccounts)
local Config=require(game.ReplicatedStorage.MarketReign.MarketConfig)
local Protection=require(game.ReplicatedStorage.MarketReign.TradeProtection)
return function()
 local n=0
 local function check(ok,msg)n+=1;assert(ok,msg)end
 for _,key in ipairs(Config.ContractOrder)do
  local spec=Config.Contracts[key]
  for _,qty in ipairs({1,3,5})do
   local amount=127.39
   for _,side in ipairs({1,-1})do
    for _,field in ipairs({"Stop","Target"})do
     local p=Protection.Resolve(spec,qty,amount,spec.Last,side,field)
     check(p and math.abs(p.Price/spec.Tick-math.round(p.Price/spec.Tick))<1e-6,"tick-aligned "..key)
     check(math.abs(p.Dollars-amount)<=spec.Tick*spec.Multiplier*qty/2+.001 or p.Ticks==1,"nearest valid total")
     check((p.Price-spec.Last)*side*(field=="Stop"and -1 or 1)>0,"correct protection side")
    end
   end
  end
 end
 for _,bad in ipairs({0,-1,math.huge,0/0})do check(not Protection.Resolve(Config.Contracts.BX,1,bad),"invalid dollars")end
 local e=E.new(Config,41)
 local a=e:AddAccount("test",100000,100,.8,true)
 e:AddAccount("other",100000,100,.8,true)
 local spec=Config.Contracts.BX local price=spec.Last-20
 local ok,r=Liquidity.Perform(e,a.Id,{Action="Place",Contract="BX",Direction=1,Quantity=3,Type="Limit",Price=price,StopDollars=100,TargetDollars=200})
 check(ok,"place dollar-protected limit")
 local id=r.Id local o=e.Orders[id]
 check(o.StopTicks==3 and o.TargetTicks==5,"server converts totals using quantity")
 local function req(p,expected,qty)return {Action="AmendOrder",Contract="BX",OrderId=id,Price=p,ExpectedPrice=expected or price,ExpectedQuantity=qty or 3}end
 local function reject(owner,r)
  local old=o.Price local accepted=F.Perform(e,owner,r)
  check(not accepted and o.Price==old and e.Orders[id]==o,"rejection is atomic")
 end
 reject("other",req(price+1))
 reject(a.Id,req(price+.1))
 reject(a.Id,req(price+1,price+2))
 reject(a.Id,req(price+1,nil,2))
 reject(a.Id,req(spec.Last*2))
 a.Locked=true;reject(a.Id,req(price+1));a.Locked=false
 check(F.Perform(e,a.Id,req(price+1)),"accepted amendment")
 check(o.Price*spec.Tick==price+1 and o.Id==id and o.Remaining==3 and o.StopTicks==3,"preserves identity, quantity, protection")
 price+=1
 Liquidity.Offer(e,"BX",-1,3,spec.Last)
 check(F.Perform(e,a.Id,req(spec.Last+10)),"marketable amendment accepted")
 check(not e.Orders[id] and a.Positions.BX.Quantity==3,"marketable amendment fills normally")
 local p=a.Positions.BX
 check(math.abs((p.Entry-p.Stop)*spec.Multiplier*3-112.5)<.001,"chart stop reflects effective total")
 check(math.abs((p.Target-p.Entry)*spec.Multiplier*3-187.5)<.001,"chart target reflects effective total")
 check(not F.Perform(e,a.Id,req(price)),"filled order cannot be amended")
 local accepted,v=e:Submit(a.Id,{Contract="BX",Direction=-1,Quantity=1,Type="Limit",Price=spec.Last+30})
 check(accepted and e:Cancel(a.Id,v.Id) and not e.Orders[v.Id],"cancel exact pending order")
 check(a.Positions.BX.Quantity==3,"cancel leaves position intact")
 check(not e:Submit(a.Id,{Contract="BX",Direction=1,Quantity=1,Type="Market",StopDollars=100,StopTicks=10}),"reject ambiguous units")
 -- A hand-moved SL/TP keeps its exact price when the position grows; it still protects the whole position.
 local held,book=a.Positions.BX,e.Books.BX
 book.Last=book.Reference+8 -- the add fills 2 points higher, so the average entry moves
 local movedStop,movedTarget=held.Stop-1.25,held.Target+2.5
 check(F.Perform(e,a.Id,{Action="AmendProtection",Contract="BX",OrderId=held.Id,Protection="Stop",Price=movedStop,ExpectedPrice=held.Stop}),"move SL")
 check(F.Perform(e,a.Id,{Action="AmendProtection",Contract="BX",OrderId=held.Id,Protection="Target",Price=movedTarget,ExpectedPrice=held.Target}),"move TP")
 local entry=held.Entry
 check(Liquidity.Perform(e,a.Id,{Action="Place",Contract="BX",Direction=1,Quantity=2,Type="Market",StopDollars=100,TargetDollars=200}),"add to the position")
 check(a.Positions.BX==held and held.Quantity==5 and held.Entry>entry,"add fills into the same position at a new average")
 check(held.Stop==movedStop and held.Target==movedTarget,"moved SL/TP keep their exact prices after adding")
 local covered=0
 for _,o in ipairs(e:Snapshot(a.Id,"BX","1m",false).Orders)do if o.Protection and o.Id==held.Id and o.Quantity==5 then covered+=1 end end
 check(covered==2,"SL and TP cover the updated quantity")
 check(e:CancelProtection(a.Id,held.Id,"Stop") and not held.Stop and not held.ManualStop,"cancelling a moved SL clears its manual flag")
 -- Ticket-created protection also keeps its original price when the average entry changes.
 check(Liquidity.Perform(e,"other",{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market",StopDollars=100}),"other opens")
 local q=e.Accounts.other.Positions.BX local first=q.Stop
 book.Last=book.Reference+16
 check(Liquidity.Perform(e,"other",{Action="Place",Contract="BX",Direction=1,Quantity=1,Type="Market",StopDollars=100}),"other adds")
 check(q.Stop==first,"ticket-created SL preserves its exact price after adding")
 e:Audit()
 return {Passed=true,Cases=n}
end
