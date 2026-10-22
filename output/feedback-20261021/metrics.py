from pathlib import Path
import json,sys,statistics as st,math
from analyze import measures
from shape_metrics import shape
R=Path(__file__).resolve().parent
def avg(xs):return st.mean(xs)if xs else 0
def meaningful(bars,tick):
 closes=[b['Close']for b in bars];direction=0;anchor=extreme=closes[0];start=0;legs=[];events=[]
 for i,price in enumerate(closes[1:],1):
  floor=max(6*tick,abs(extreme)*.00025)
  if not direction:
   if abs(price-anchor)>=floor:direction=1 if price>anchor else -1;extreme=price
  elif (price-extreme)*direction>=0:extreme=price
  elif (extreme-price)*direction>=max(floor,abs(extreme-anchor)*.2)-1e-8:
   legs.append(i-start);events.append({'Minute':i,'Ticks':abs(extreme-price)/tick,'PriorLegTicks':abs(extreme-anchor)/tick})
   anchor=extreme;extreme=price;start=i;direction=-direction
 if direction:legs.append(len(closes)-start)
 pullbacks=[];i=4
 while i<len(closes)-1:
  move=closes[i-1]-closes[i-4];side=(move>0)-(move<0);peak=closes[i-1]
  if abs(move)<12*tick or (closes[i]-peak)*side>=0:i+=1;continue
  depth=0
  for j in range(i,min(len(closes),i+8)):
   depth=max(depth,(peak-closes[j])*side)
   if (closes[j]-peak)*side>=0:
    if depth>=max(6*tick,abs(peak)*.00025,abs(move)*.2):pullbacks.append({'Ticks':depth/tick,'Duration':j-i+1});i=j
    break
  i+=1
 return {'MeaningfulLong8':sum(n for n in legs if n>=8)/len(bars),'MeaningfulMaxLeg':max(legs,default=0),'MeaningfulCounters':len(events),'CounterDepthTicks':avg([x['Ticks']for x in events]),'CounterEvents':events,'MeaningfulPullbacks':len(pullbacks),'MeaningfulPullbackEvents':pullbacks}
def summarize(folder):
 ds=[json.loads(p.read_text())for p in (R/folder).glob('*.json')];rows=[];ag={}
 for d in ds:
  for key,m in d['Markets'].items():
   tick=.1 if key=='BG'else.25;x=measures(m['Bars'],tick)
   rows.append({'Case':d['Case'],'Arm':d['Arm'],'Market':key,**x,**shape(m['Bars'],tick),**meaningful(m['Bars'],tick),**{k:m[k]for k in ['OneSecondRV','FifteenSecondMidpointRV','NoQuoteFraction','Volume','SpreadP95']},'MeanRange30':avg(x['Range30'])})
 fields=['MeaningfulLong8','MeaningfulMaxLeg','MeaningfulCounters','CounterDepthTicks','MeaningfulPullbacks','Directional10WindowFraction','LongRun8CandleShare','SignificantLongestRun','LongestRun','Pullbacks','OneSecondRV','FifteenSecondMidpointRV','OneMinuteRV','MeanMinuteRangePercent','MeanRange30','Alternating4Fraction','SpreadP95','NoQuoteFraction','Volume']
 for arm in ['Baseline','Candidate']:
  xs=[x for x in rows if x['Arm']==arm];ad=[d for d in ds if d['Arm']==arm]
  if not xs:continue
  ag[arm]={k:avg([x[k]for x in xs])for k in fields}
  ag[arm].update(Recovery=sum(d['Final']['Transferred']-d['Initial']['Transferred']for d in ad),Replay=all(d['Replay']for d in ad),Insolvent=sum(s['Count']-s['PositiveEquity']for d in ad for s in d['Final']['ByKind'].values()),TargetWindows=sum(.7<=r<=1.5 for x in xs for r in x['Range30']))
 cases=sorted(set(d['Case']for d in ds));gates={};wins=[]
 if set(ag)=={'Baseline','Candidate'}:
  b,c=ag['Baseline'],ag['Candidate']
  for k,ratio in [('MeaningfulLong8',.8),('MeaningfulMaxLeg',.85),('Directional10WindowFraction',.8)]:gates[k]=c[k]<=b[k]*ratio
  for k,ratio in [('MeaningfulCounters',1.3),('OneMinuteRV',.9),('MeanMinuteRangePercent',.9),('FifteenSecondMidpointRV',.9)]:gates[k]=c[k]>=b[k]*ratio
  for case in cases:
   pair={a:[x for x in rows if x['Case']==case and x['Arm']==a]for a in ag}
   if avg([x['MeaningfulLong8']for x in pair['Candidate']])<avg([x['MeaningfulLong8']for x in pair['Baseline']]):wins.append(case)
  gates.update(CaseWins=len(wins)>=math.ceil(len(cases)*2/3),Recovery=c['Recovery']<=b['Recovery']*1.1,Alternation=c['Alternating4Fraction']<=.08,Quotes=c['NoQuoteFraction']<=.001,Spread=c['SpreadP95']<=b['SpreadP95']*1.5,Replay=c['Replay'],Solvent=c['Insolvent']==0)
  current='CurrentBX'if 'CurrentBX'in cases else 'CurrentBXLater'
  if current in cases:
   x={a:next(x for x in rows if x['Case']==current and x['Market']=='BX'and x['Arm']==a)for a in ag}
   gates['CurrentBX']=x['Candidate']['MeaningfulLong8']<x['Baseline']['MeaningfulLong8']and x['Candidate']['MeaningfulMaxLeg']<=x['Baseline']['MeaningfulMaxLeg']and x['Candidate']['MeaningfulCounters']>x['Baseline']['MeaningfulCounters']
 return {'Aggregate':ag,'Gates':gates,'Pass':bool(gates)and all(gates.values()),'ShapeWins':wins,'Markets':rows}
if __name__=='__main__':
 folder=sys.argv[1];out=summarize(folder);(R/(folder+'-metrics.json')).write_text(json.dumps(out,indent=2));print(json.dumps({k:v for k,v in out.items()if k!='Markets'},indent=2))
