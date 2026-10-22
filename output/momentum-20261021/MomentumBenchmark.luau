local B={}
local function clone(v)if type(v)~='table'then return v end;local t={}for k,x in pairs(v)do t[k]=clone(x)end;return t end
local function percentile(values,q)table.sort(values);return values[math.max(1,math.ceil(#values*q))]or 0 end
local function returns(bars)
 local xs={};local flips,pairs,total=0,0,0
 for i=2,#bars do
  local x=bars[i].Close-bars[i-1].Close;table.insert(xs,x);total+=math.abs(x)
  if #xs>1 and x~=0 and xs[#xs-1]~=0 then pairs+=1;if x*xs[#xs-1]<0 then flips+=1 end end
 end
 local n=#xs;local mean=0;for _,x in ipairs(xs)do mean+=x end;mean/=math.max(1,n)
 local variance,cov=0,0;for i,x in ipairs(xs)do variance+=(x-mean)^2;if i>1 then cov+=(x-mean)*(xs[i-1]-mean)end end
 return {FlipRate=pairs>0 and flips/pairs or 0,ReturnCorrelation=variance>0 and cov/variance or 0,PathLength=total}
end
local function health(e,p)
 local result={ByKind={},Recovered=p.ParticipationRecovered or 0,Transferred=p.ParticipationTransferred or 0}
 local H=require(p.LabRoot.BotParticipation)
 for _,a in ipairs(p.Agents)do
  local ac=e.Accounts[a.Id];local summary=e:Summary(ac);local state,_,_,eligible=H.Inspect(e,a,summary)
  local s=result.ByKind[a.Kind]or {Count=0,Eligible=0,Equity=0,Realized=0,RecoveryNet=0,Recoveries=0,Inventory=0,States={}}
  result.ByKind[a.Kind]=s;s.Count+=1;s.Eligible+=eligible and 1 or 0;s.Equity+=summary.Equity;s.Realized+=ac.Realized
  s.RecoveryNet+=ac.ParticipationCapitalNet or 0;s.Recoveries+=ac.ParticipationRecoveries or 0;s.States[state]=(s.States[state]or 0)+1
  for _,pos in pairs(ac.Positions)do s.Inventory+=pos.Quantity end
 end
 return result
end
-- LabRoot is external context, never attached to checkpointed population state.
function B.Run(root,snapshot,name,arm,lab,options)
 options=options or {};local CP=require(root.WorldCheckpoint);local c=require(root.Shared.MarketConfig)
 local e,p=CP.Restore(snapshot,c)
 local start=e.Time;local measured=math.ceil((start+(options.Adapt or 1200))/60)*60;local finish=measured+(options.Measure or 1800)
 local stats={};local kinds={};for _,a in ipairs(p.Agents)do kinds[a.Id]=a.Kind end
 local initial
 -- Temporarily provide context to health through a wrapper, avoiding any saved references.
 local function captureHealth()p.LabRoot=root;local out=health(e,p);p.LabRoot=nil;return out end
 local trade=e._trade
 e._trade=function(self,b,incoming,resting,qty)
  trade(self,b,incoming,resting,qty)
  if self.Time>=measured and self.Time<finish then
   local s=stats[b.Key];s.Trades+=1;s.Volume+=qty
   local kind=kinds[incoming.Owner]or 'Player';s.Aggressor[kind]=(s.Aggressor[kind]or 0)+qty
  end
 end
 for key,b in pairs(e.Books)do if not b.Spec.CloseOnly then stats[key]={Trades=0,Volume=0,Aggressor={},Spreads={},NoQuote=0,Samples=0,Depth={},MidBars={}}end end
 local steps=0;local cpu=0;local block=os.clock()
 while e.Time<finish do
  p:Step();steps+=1
  if not initial and e.Time>=measured then initial=captureHealth()end
  if e.Time>=measured and e.Time<finish and e.Step%4==0 then
   for key,s in pairs(stats)do
    local b=e.Books[key];local bid,ask=e:PublicPrices(key);s.Samples+=1
    if bid and ask then
     table.insert(s.Spreads,(ask-bid)/b.Spec.Tick)
     local mid=(bid+ask)/2;local bucket=math.floor(e.Time/60)*60;local bar=s.MidBars[#s.MidBars]
     if not bar or bar.Time~=bucket then bar={Time=bucket,Open=mid,High=mid,Low=mid,Close=mid};table.insert(s.MidBars,bar)end
     bar.High=math.max(bar.High,mid);bar.Low=math.min(bar.Low,mid);bar.Close=mid
    else s.NoQuote+=1 end
   end
  end
  if steps%20==0 then
   cpu+=os.clock()-block
   lab.Progress={Case=name,Arm=arm,Elapsed=e.Time-start,Total=finish-start,Completed=#lab.Results}
   task.wait();block=os.clock()
  end
 end
 cpu+=os.clock()-block
 local final=captureHealth();local audit=e:Audit();local markets={}
 for key,s in pairs(stats)do
  local bars={};local low,high=math.huge,-math.huge;local narrow=0
  for _,bar in ipairs(e.Books[key].Candles['1m'])do if bar.Time>=measured and bar.Time+60<=finish then
   table.insert(bars,clone(bar));low=math.min(low,bar.Low);high=math.max(high,bar.High)
   if (bar.High-bar.Low)/e.Books[key].Spec.Tick<=1.01 then narrow+=1 end
  end end
  local row=returns(bars);row.Bars=bars;row.RangePercent=#bars>0 and (high-low)/bars[1].Open*100 or 0
  row.ChopRatio=row.PathLength/math.max(e.Books[key].Spec.Tick,high-low)
  row.Trades=s.Trades;row.Volume=s.Volume;row.Aggressor=s.Aggressor;row.OneTickMinutes=narrow
  row.SpreadP50=percentile(s.Spreads,.5);row.SpreadP95=percentile(s.Spreads,.95);row.NoQuoteFraction=s.NoQuote/math.max(1,s.Samples)
  row.Midpoint=returns(s.MidBars);markets[key]=row
 end
 -- Branch from a serialized terminal state; changing source never counts as a replay test.
 local encoded=CP.Encode(CP.Capture(e,p));local re,rp=CP.Restore(CP.Decode(encoded),c)
 for i=1,80 do p:Step();rp:Step();if i%20==0 then task.wait()end end
 assert(e.TradeHash==re.TradeHash and e.NextTrade==re.NextTrade and p.Random.State==rp.Random.State,'Replay diverged')
 local function equal(a,b,path)
  path=path or 'state';assert(type(a)==type(b),path..' type');if type(a)~='table'then assert(a==b,path..' differs');return end
  for k,v in pairs(a)do equal(v,b[k],path..'.'..tostring(k))end;for k in pairs(b)do assert(a[k]~=nil,path..' extra '..tostring(k))end
 end
 equal(CP.Capture(e,p),CP.Capture(re,rp));e:Audit();re:Audit()
 return {Case=name,Arm=arm,Seed=e.Seed,Start=start,MeasuredStart=measured,MeasuredSeconds=finish-measured,
  Markets=markets,Initial=initial,Final=final,Audit=audit,Replay=true,RawBytes=encoded.RawBytes,CpuSeconds=cpu,Steps=steps}
end
function B.Start(lab)
 lab.Results={};lab.Progress={Phase='Preparing seeds'};lab.Running=true;lab.Error=nil
 task.spawn(function()
  local ok,err=pcall(function()
   local H=game:GetService('HttpService');local root=lab.Baseline;local CP=require(root.WorldCheckpoint);local C=require(root.Shared.MarketConfig)
   for _,seed in ipairs({71,7919,104729})do
    local e=require(root.MarketEngine).new(C,seed);local p=require(root.Participants).new(e)
    while e.Time<1800 do p:Step();if e.Step%20==0 then lab.Progress={Phase='Preparing seed',Seed=seed,Elapsed=e.Time};task.wait()end end
    lab.Snapshots['Seed'..seed]=CP.Capture(e,p)
   end
   for _,name in ipairs({'Seed71','Seed7919','Seed104729','Current','Older','Aged'})do
    for _,arm in ipairs({'Baseline','Candidate'})do
     local result=B.Run(lab[arm],lab.Snapshots[name],name,arm,lab)
     table.insert(lab.Results,result)
     H:PostAsync('http://127.0.0.1:8817/results/'..name..'-'..arm..'.json',H:JSONEncode(result),Enum.HttpContentType.ApplicationJson)
    end
   end
  end)
  lab.Running=false;lab.Error=not ok and tostring(err)or nil;lab.Progress={Done=ok,Completed=#lab.Results,Error=lab.Error}
 end)
end
return B
