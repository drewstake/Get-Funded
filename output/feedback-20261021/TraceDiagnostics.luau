local D={}
function D.Run(root,snapshot)
 local CP=require(root.WorldCheckpoint)
 local e,p=CP.Restore(snapshot,require(root.Shared.MarketConfig))
 local start=math.ceil((e.Time+1200)/60)*60;local finish=start+3600
 local agents={};for _,a in ipairs(p.Agents)do agents[a.Id]=a end
 local rows,cycles,lastEntry={},{},{}
 local function row(key)
  if e.Time<start or e.Time>=finish then return nil end
  local id=key..':'..math.floor(e.Time/60);local x=rows[id]
  if not x then x={Market=key,Time=math.floor(e.Time/60)*60,Flows={},Inventory={},Quotes={},States={},ValueGap=0,ValueSamples=0};rows[id]=x end
  return x
 end
 local old=e._trade
 e._trade=function(self,b,inc,rest,qty)
  local prior=b.Last or b.Reference;local a=agents[inc.Owner];local ac=self.Accounts[inc.Owner];local pos=ac.Positions[b.Key]
  local closing=pos and inc.Direction~=pos.Direction and math.min(qty,pos.Quantity)or 0
  local positionId=pos and pos.Id;local state=a and(a.Momentum or a.Whale)
  local phase=state and state.Phase or ''
  local reason=inc.Protection or (closing>0 and pos.Triggered) or (closing>0 and(phase=='Reducing'and state.ExitReason or 'Closing'))or 'Opening'
  old(self,b,inc,rest,qty)
  local x=row(b.Key);if not x then return end;x.Open=x.Open or prior;x.Close=b.Last
  local label=(a and a.Kind or 'Player')..'/'..tostring(reason)..'/'..phase
  local f=x.Flows[label]or{Buy=0,Sell=0,Move=0,Trades=0,OpenContracts=0,CloseContracts=0,Passive={}};x.Flows[label]=f
  f[inc.Direction==1 and 'Buy'or 'Sell']+=qty;f.Move+=b.Last-prior;f.Trades+=1;f.OpenContracts+=qty-closing;f.CloseContracts+=closing
  local passive=agents[rest.Owner];local kind=passive and passive.Kind or 'Player';f.Passive[kind]=(f.Passive[kind]or 0)+qty
  if a and(a.Kind=='Momentum'or a.Kind=='Whale')and not positionId and qty>closing then
   table.insert(cycles,{Agent=a.Id,Market=a.Key,Kind=a.Kind,Time=e.Time,Direction=inc.Direction,Price=prior,Previous=lastEntry[a.Id],Phase=phase,Horizon=state and state.Horizon})
   lastEntry[a.Id]={Time=e.Time,Direction=inc.Direction,Price=prior}
  end
 end
 local function quoteRow(o,a)
  local x=row(o.Contract);if not x then return end
  local q=x.Quotes[a.Kind]or{Cancels=0,Age=0,WithdrawBuy=0,WithdrawSell=0,NewBuy=0,NewSell=0,RepriceUp=0,RepriceDown=0};x.Quotes[a.Kind]=q;return q
 end
 local cancel=e.Cancel
 e.Cancel=function(self,owner,id,...)
  local o=self.Orders[id];local a=agents[owner]
  if o and a and(a.Kind=='Maker'or a.Kind=='Reserve'or a.Kind=='Liquidity')then
   local q=quoteRow(o,a);if q then q.Cancels+=1;q.Age+=self.Time-o.Time;q[o.Direction==1 and 'WithdrawBuy'or 'WithdrawSell']+=o.Remaining end
  end
  return cancel(self,owner,id,...)
 end
 -- Track the SAME quote slot over successive decisions. Adjacent depth levels are
 -- not replacements of each other, and are never counted as repricing evidence.
 for _,method in ipairs({'_maker','_reserve'})do
  local original=p[method];local remembered={}
  p[method]=function(self,a)
   original(self,a)
   local slots=remembered[a.Id]or {};remembered[a.Id]=slots
   for slot,id in pairs(a.Quotes or {})do
    local o=e.Orders[id]
    if o then
     local prev=slots[slot]
     if prev and prev.Id~=id then
      local q=quoteRow(o,a)
      if q then
       q.SlotReplacements=(q.SlotReplacements or 0)+1
       q.SlotUp=(q.SlotUp or 0)+(o.Price>prev.Price and 1 or 0)
       q.SlotDown=(q.SlotDown or 0)+(o.Price<prev.Price and 1 or 0)
       q.SlotPriceChange=(q.SlotPriceChange or 0)+o.Price-prev.Price
       q.SlotLifetime=(q.SlotLifetime or 0)+o.Time-prev.Time
      end
     end
     slots[slot]={Id=id,Price=o.Price,Time=o.Time}
    end
   end
  end
 end
 local submit=e.Submit
 e.Submit=function(self,owner,request,...)
  local ok,result=submit(self,owner,request,...);local a=agents[owner]
  if ok and a and(a.Kind=='Maker'or a.Kind=='Reserve'or a.Kind=='Liquidity')then
   local q=quoteRow(request,a)
   if q then
    q[request.Direction==1 and 'NewBuy'or 'NewSell']+=result.Remaining or 0
   end
  end
  return ok,result
 end
 if root.TraceOff then e._trade=old;e.Cancel=cancel;e.Submit=submit;p._maker=nil;p._reserve=nil end
 while e.Time<finish do
  p:Step()
  if e.Time>=start and e.Step%240==0 then
   for _,a in ipairs(p.Agents)do local x=row(a.Key)
    if x then
     local pos=e.Accounts[a.Id].Positions[a.Key];x.Inventory[a.Kind]=(x.Inventory[a.Kind]or 0)+(pos and pos.Quantity*pos.Direction or 0)
     local s=a.Momentum or a.Whale;local key=a.Kind..'/'..(s and s.Phase or 'Other');x.States[key]=(x.States[key]or 0)+1
     if a.Kind=='Value'then x.ValueGap+=a.Belief-(e.Books[a.Key].Last or e.Books[a.Key].Reference);x.ValueSamples+=1 end
    end
   end
  end
 end
 local out={};for _,v in pairs(rows)do table.insert(out,v)end;table.sort(out,function(a,b)return a.Time==b.Time and a.Market<b.Market or a.Time<b.Time end)
 p._maker=nil;p._reserve=nil
 return {Rows=out,Cycles=cycles,Audit=e:Audit(),Step=e.Step,TradeHash=e.TradeHash,Terminal=CP.Capture(e,p)}
end
return D
