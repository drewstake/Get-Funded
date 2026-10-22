from pathlib import Path
import json, math, statistics as st

ROOT=Path(__file__).resolve().parent
def mean(v): return st.mean(v) if v else 0
def percentile(v,q): return sorted(v)[max(0,math.ceil(len(v)*q)-1)] if v else 0
def sign(v):return (v>0)-(v<0)
def measures(bars,tick):
    colors=[sign(b['Close']-b['Open']) for b in bars]
    runs=[];prev=0;n=0
    for x in colors:
        if x==prev and x:n+=1
        else:
            if n:runs.append(n)
            prev=x;n=1 if x else 0
    if n:runs.append(n)
    closes=[b['Close'] for b in bars];eff=[];ranges=[];wicks=[]
    for i in range(0,len(bars)-29,30):
        xs=bars[i:i+30];ranges.append((max(b['High'] for b in xs)-min(b['Low'] for b in xs))/xs[0]['Open']*100)
    for i in range(0,len(closes)-9,10):
        xs=closes[i:i+10];path=sum(abs(b-a)for a,b in zip(xs,xs[1:]))
        if path:eff.append(abs(xs[-1]-xs[0])/path)
    for b in bars:
        if b['High']>b['Low']:wicks.append(1-abs(b['Close']-b['Open'])/(b['High']-b['Low']))
    pullbacks=[];i=4
    # A >=4-tick prior 3-minute move, followed by a >=2-tick/15% retracement,
    # then recovery of the prior extreme within 8 minutes. No overlapping events.
    while i<len(closes)-1:
        leg=closes[i-1]-closes[i-4];side=sign(leg)
        if abs(leg)<4*tick or sign(closes[i]-closes[i-1])!=-side:i+=1;continue
        peak=closes[i-1];depth=0;recovered=False
        for j in range(i,min(len(closes),i+8)):
            depth=max(depth,(peak-closes[j])*side)
            if (closes[j]-peak)*side>=0:
                if depth>=max(2*tick,abs(leg)*.15):pullbacks.append({'Ticks':depth/tick,'Duration':j-i+1});i=j;recovered=True
                break
        i+=1
    alternating=sum(all(colors[k] and colors[k]==-colors[k-1] for k in range(i-2,i+1)) for i in range(3,len(colors)))
    return {'LongestRun':max(runs,default=0),'Runs':runs,'Range30':ranges,'WickFraction':mean(wicks),
            'Pullbacks':len(pullbacks),'PullbackDepthTicks':mean([p['Ticks']for p in pullbacks]),
            'PullbackDuration':mean([p['Duration']for p in pullbacks]),'Efficiency10':mean(eff),
            'Alternating4Fraction':alternating/max(1,len(colors)-3),
            'MeanMinuteRangePercent':mean([(b['High']-b['Low'])/b['Open']*100 for b in bars])}

def summarize(folder='results'):
    data={(d['Case'],d['Arm']):d for p in (ROOT/folder).glob('*.json')for d in [json.loads(p.read_text(encoding='utf8'))]}
    cases=sorted(n for n,a in data if a=='Baseline' and (n,'Candidate')in data)
    out={};windows=[]
    for arm in ['Baseline','Candidate']:
        ds=[data[n,arm] for n in cases];xs=[];allruns=[];ranges=[]
        for d in ds:
            for key,m in d['Markets'].items():
                x=measures(m['Bars'],.1 if key=='BG'else .25);x.update({k:m[k]for k in ['FlipRate','SpreadP95','NoQuoteFraction','OneSecondRV']});x['ReversionBuys']=m['ReversionBuys'];x['ReversionSells']=m['ReversionSells'];x['Volume']=m['Volume'];xs.append(x);allruns+=x['Runs'];ranges+=x['Range30'];windows.append({'Case':d['Case'],'Arm':arm,'Market':key,**x})
        if not xs:continue
        out[arm]={'Cases':len(cases),'MarketHours':len(xs),**{k:mean([x[k]for x in xs]) for k in ['LongestRun','Pullbacks','PullbackDepthTicks','PullbackDuration','Efficiency10','Alternating4Fraction','WickFraction','MeanMinuteRangePercent','FlipRate','SpreadP95','NoQuoteFraction','OneSecondRV']},
          'MedianLongestRun':st.median(x['LongestRun']for x in xs),'RunP95':percentile(allruns,.95),'MeanRange30':mean(ranges),'TargetWindows':sum(.7<=x<=1.5 for x in ranges),'Windows30':len(ranges),
          'Volume':sum(x['Volume']for x in xs),'ReversionBuys':sum(x['ReversionBuys']for x in xs),'ReversionSells':sum(x['ReversionSells']for x in xs),
          'Transfers':sum(d['Final']['Transferred']-d['Initial']['Transferred']for d in ds),'Recoveries':sum(d['Final']['Recovered']-d['Initial']['Recovered']for d in ds),'Replay':all(d['Replay']for d in ds),'Kinds':{}}
        for kind in ['Reversion','Maker','Momentum','Whale']:
            out[arm]['Kinds'][kind]={'EquityChangeExTransfers':sum(d['Final']['ByKind'][kind]['Equity']-d['Initial']['ByKind'][kind]['Equity']-d['Final']['ByKind'][kind]['RecoveryNet']+d['Initial']['ByKind'][kind]['RecoveryNet']for d in ds),
              'Recoveries':sum(d['Final']['ByKind'][kind]['Recoveries']-d['Initial']['ByKind'][kind]['Recoveries']for d in ds),
              'InitialAboveFloor':sum(d['Initial']['ByKind'][kind]['AboveOwnRiskFloor']for d in ds),'FinalAboveFloor':sum(d['Final']['ByKind'][kind]['AboveOwnRiskFloor']for d in ds)}
    return {'Cases':cases,'Aggregate':out,'Markets':windows}
if __name__=='__main__':
    import sys
    folder=sys.argv[1]if len(sys.argv)>1 else 'results';d=summarize(folder)
    (ROOT/(folder+'-summary.json')).write_text(json.dumps(d,indent=2),encoding='utf8')
    print(json.dumps(d['Aggregate'],indent=2))
