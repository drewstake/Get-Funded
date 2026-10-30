local H={}
function H.Start(root,config,snapshot)
 local E,P=require(root.MarketEngine),require(root.Participants)
 local e,p
 if snapshot then e,p=require(root.WorldCheckpoint).Restore(snapshot,config)else e=E.new(config,20261021);p=P.new(e)end
 local run={E=e,P=p,Start=e.Time,End=e.Time+2100,Markets={},InitialDepleted=0}
 for _,a in ipairs(p.Agents)do if e:Summary(e.Accounts[a.Id]).Equity<=0 then run.InitialDepleted+=1 end end
 for key,b in pairs(e.Books)do if not b.Spec.CloseOnly then run.Markets[key]={Low=math.huge,High=-math.huge,Reference=b.Last or b.Reference,Trades=0,Volume=0,Missing=0,Spreads={},Up=0,Down=0}end end
 local trade=e._trade
 e._trade=function(self,b,incoming,resting,qty)
  trade(self,b,incoming,resting,qty)
  if self.Time>=run.Start+300 and run.Markets[b.Key]then local s=run.Markets[b.Key];s.Low=math.min(s.Low,b.Last);s.High=math.max(s.High,b.Last);s.Trades+=1;s.Volume+=qty end
 end
 return run
end
function H.Advance(run)
 local e,p=run.E,run.P;local start=os.clock()
 while e.Time<run.End and os.clock()-start<6 do
  p:Step()
  if e.Time>=run.Start+300 and e.Step%4==0 then for key,s in pairs(run.Markets)do
   local b=e.Books[key];local bid,ask=e:PublicPrices(key)
   if bid and ask then local mid=(bid+ask)/2;table.insert(s.Spreads,math.round((ask-bid)/b.Spec.Tick));if s.Prev then if mid>s.Prev then s.Up+=1 elseif mid<s.Prev then s.Down+=1 end end;s.Prev=mid
   else s.Missing+=1 end
  end end
  if e.Step%120==0 then task.wait()end
 end
 if e.Time<run.End then return {Done=false,Elapsed=e.Time-run.Start}end
 e:Audit()
 local result={Done=true,Elapsed=e.Time-run.Start,MeasuredSeconds=1800,Markets={},Depleted=0,InitialDepleted=run.InitialDepleted}
 for _,a in ipairs(p.Agents)do if e:Summary(e.Accounts[a.Id]).Equity<=0 then result.Depleted+=1 end end
 for key,s in pairs(run.Markets)do
  table.sort(s.Spreads);local narrow,count,ranges=0,0,0;local b=e.Books[key]
  for _,bar in ipairs(b.Candles['1m'])do if bar.Time>=run.Start+300 and bar.Time<run.End then local range=(bar.High-bar.Low)/b.Spec.Tick;count+=1;ranges+=range;if range<=1.01 then narrow+=1 end end end
  result.Markets[key]={RangePercent=(s.High-s.Low)/s.Reference*100,RangeTicks=s.High-s.Low,Trades=s.Trades,Volume=s.Volume,Missing=s.Missing,Spread95=s.Spreads[math.ceil(#s.Spreads*.95)],MaxSpread=s.Spreads[#s.Spreads],Up=s.Up,Down=s.Down,OneTickMinutes=narrow,Minutes=count,MeanMinuteTicks=ranges/math.max(1,count)}
 end
 return result
end
return H
