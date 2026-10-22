local D={}
local function scenario(root,direction,fraction)
 local E=require(root.MarketEngine);local P=require(root.Participants);local C=require(root.Shared.MarketConfig)
 local e=E.new(C,7251)
 local p=setmetatable({Engine=e,Config=C,Random=P.RNG.new(7251),Agents={},Markets={},Regime={Volatility=1,Liquidity=1,Activity=1},NewsUntil=0},P)
 for _,key in ipairs(C.ContractOrder)do p.Markets[key]={}end
 local a=p:_agent('BX','Maker',1);local b=e.Books.BX
 e:AddAccount('warehouse-counterparty',1000000,1000,1,false)
 e:AddAccount('balanced-taker',1000000,1000,1,false)
 local qty=math.max(1,math.floor(a.Limit*fraction))
 assert(e:Submit('warehouse-counterparty',{Contract='BX',Direction=-direction,Quantity=qty,Type='Limit',Price=b.Reference*b.Spec.Tick}))
 local ok,fill=e:Submit(a.Id,{Contract='BX',Direction=direction,Quantity=qty,Type='Market'});assert(ok and fill.Filled==qty)
 local initial=b.Last;local rows={}
 -- These deterministic external orders are a controlled fixture, not a proposed trader.
 -- Equal buys/sells return Maker inventory to the same funded value every cycle.
 -- Alternate the final side, avoiding an always-last-at-bid sampling bias.
 for i=1,40 do
  e:AdvanceClock(C.MakerMinRestSeconds*6+1);p:_maker(a)
  e:AdvanceClock(C.MakerReplenishSeconds*1.4+1);p:_maker(a)
  local bid,ask=e:PublicPrices('BX');assert(bid and ask,'No funded quote')
  local first=i%2==0 and 1 or -1
  for _,side in ipairs({first,-first})do
   local good,result=e:Submit('balanced-taker',{Contract='BX',Direction=side,Quantity=1,Type='Market'})
   assert(good and result.Filled==1,'Balanced order unfilled')
  end
  local pos=e.Accounts[a.Id].Positions.BX;assert(pos and pos.Direction==direction and pos.Quantity==qty)
  assert(not e.Accounts['balanced-taker'].Positions.BX)
  table.insert(rows,{Cycle=i,Last=b.Last,Midpoint=(bid+ask)/2/b.Spec.Tick,Inventory=qty})
 end
 return {Initial=initial,Final=b.Last,DriftTicks=b.Last-initial,Inventory=qty*direction,Fraction=fraction,Rows=rows,Audit=e:Audit(),Volume=e.TotalVolume}
end
function D.Run(root)
 local out={}
 for _,direction in ipairs({1,-1})do for _,fraction in ipairs({.05,.15,1/3})do table.insert(out,scenario(root,direction,fraction));task.wait()end end
 return {Cases=out}
end
return D
