local T={}
function T.Run(root,snapshot)
 local CP=require(root.WorldCheckpoint);local e,p=CP.Restore(snapshot,require(root.Shared.MarketConfig))
 local start=math.ceil((e.Time+1200)/60)*60;local finish=start+3600;local rows={}
 while e.Time<finish do
  p:Step()
  if e.Time>=start and e.Step%4==0 then
   for _,key in ipairs(p.Config.ContractOrder)do
    local b=e.Books[key];local x=rows[key]or{Samples=0,RequestedHalfSpread={},BookSpread={},BothTouchQuantity=0};rows[key]=x
    local stress=p.Regime.Volatility*p.Config.Volatility+math.min(6,b.Volatility)*.2
    local half=math.max(1,math.floor(stress*.8+b.Volatility*.2));local bid,ask=e:PublicPrices(key)
    x.Samples+=1;x.RequestedHalfSpread[tostring(half)]=(x.RequestedHalfSpread[tostring(half)]or 0)+1
    if bid and ask then local spread=tostring(math.round((ask-bid)/b.Spec.Tick));x.BookSpread[spread]=(x.BookSpread[spread]or 0)+1 end
    local depth=e:PublicDepth(key,1);x.BothTouchQuantity+=(depth.Bids[1]and depth.Bids[1].Quantity or 0)+(depth.Asks[1]and depth.Asks[1].Quantity or 0)
   end
  end
 end
 return {Rows=rows,Audit=e:Audit(),Terminal=CP.Capture(e,p)}
end
return T
