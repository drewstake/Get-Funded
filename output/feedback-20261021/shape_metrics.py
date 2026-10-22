from pathlib import Path
import json,statistics,math,sys
from analyze import measures
R=Path(__file__).resolve().parent
def avg(v): return statistics.mean(v) if v else 0
def shape(bars,tick):
    closes=[b['Close'] for b in bars]
    # A doji or a one-tick flicker does not break an otherwise uninterrupted leg.
    # Reverse only after a cumulative two-tick retracement from the running extreme.
    runs=[];direction=0;start=0;extreme=closes[0];anchor=extreme
    for i,price in enumerate(closes[1:],1):
        if not direction:
            if abs(price-anchor)>=2*tick-1e-8:direction=1 if price>anchor else -1;extreme=price
        elif (price-extreme)*direction>=0:extreme=price
        elif (extreme-price)*direction>=2*tick-1e-8:
            runs.append(i-start);start=i;direction=-direction;extreme=price
    if direction:runs.append(len(closes)-start)
    directional=[]
    for i in range(len(closes)-9):
        xs=closes[i:i+10];path=sum(abs(b-a) for a,b in zip(xs,xs[1:]));move=abs(xs[-1]-xs[0])
        directional.append(move>=8*tick and path>0 and move/path>=.9)
    return {'LongRun8CandleShare':sum(n for n in runs if n>=8)/len(bars),'SignificantLongestRun':max(runs,default=0),'Directional10WindowFraction':avg(directional)}
def summarize(folder):
    data=[json.loads(p.read_text(encoding='utf8')) for p in (R/folder).glob('*.json')]
    rows=[];ag={}
    for d in data:
        for key,m in d['Markets'].items():
            x=measures(m['Bars'],.1 if key=='BG' else .25)
            rows.append({'Case':d['Case'],'Arm':d['Arm'],'Market':key,**x,**shape(m['Bars'],.1 if key=='BG' else .25),**{k:m[k] for k in ['OneSecondRV','FifteenSecondMidpointRV','NoQuoteFraction','Volume','SpreadP95']},'MeanRange30':avg(x['Range30'])})
    fields=['LongRun8CandleShare','SignificantLongestRun','Directional10WindowFraction','LongestRun','Pullbacks','OneSecondRV','FifteenSecondMidpointRV','OneMinuteRV','MeanMinuteRangePercent','MeanRange30','Alternating4Fraction','SpreadP95','NoQuoteFraction']
    for arm in ['Baseline','Candidate']:
        xs=[r for r in rows if r['Arm']==arm];ds=[d for d in data if d['Arm']==arm]
        if not xs:continue
        ag[arm]={k:avg([r[k] for r in xs]) for k in fields}
        ag[arm].update({'TotalPullbacks':sum(r['Pullbacks'] for r in xs),'Recovery':sum(d['Final']['Transferred']-d['Initial']['Transferred'] for d in ds),'Replay':all(d['Replay'] for d in ds),'Insolvent':sum(s['Count']-s['PositiveEquity'] for d in ds for s in d['Final']['ByKind'].values()),'Eligible':sum(s['Eligible'] for d in ds for s in d['Final']['ByKind'].values())})
    wins={k:[] for k in ['Shape','Pullbacks']}
    cases=sorted({d['Case'] for d in data})
    if set(ag)=={'Baseline','Candidate'}:
        for n in cases:
            a={arm:[x for x in rows if x['Case']==n and x['Arm']==arm] for arm in ['Baseline','Candidate']}
            if not all(a.values()):continue
            if avg([x['LongRun8CandleShare'] for x in a['Candidate']])<avg([x['LongRun8CandleShare'] for x in a['Baseline']]):wins['Shape'].append(n)
            if sum(x['Pullbacks'] for x in a['Candidate'])>sum(x['Pullbacks'] for x in a['Baseline']):wins['Pullbacks'].append(n)
    return {'Cases':cases,'Aggregate':ag,'Wins':wins,'Markets':rows}
if __name__=='__main__':
    folder=sys.argv[1];d=summarize(folder);(R/(folder+'-shape.json')).write_text(json.dumps(d,indent=2),encoding='utf8');print(json.dumps({'Cases':d['Cases'],'Aggregate':d['Aggregate'],'Wins':d['Wins']},indent=2))
