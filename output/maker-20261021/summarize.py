from pathlib import Path
import json,statistics
r=Path(__file__).resolve().parent
data={(x['Case'],x['Arm']):x for p in (r/'results').glob('*.json')for x in [json.loads(p.read_text(encoding='utf8'))]}
cases=sorted(n for n,a in data if a=='Baseline'and(n,'Candidate')in data)
out={};windows=[]
for arm in ['Baseline','Candidate']:
 xs=[data[n,arm]for n in cases];ms=[m for x in xs for m in x['Markets'].values()]
 if not ms:continue
 out[arm]={'Runs':len(xs),'Windows':len(ms),'InTarget':sum(.7<=m['RangePercent']<=1.5 for m in ms),
 'MeanRange':statistics.mean(m['RangePercent']for m in ms),'MedianRange':statistics.median(m['RangePercent']for m in ms),
 'MeanFlip':statistics.mean(m['FlipRate']for m in ms),'MeanMidFlip':statistics.mean(m['Midpoint']['FlipRate']for m in ms),'MeanChop':statistics.mean(m['ChopRatio']for m in ms),
 'MeanSpreadP95':statistics.mean(m['SpreadP95']for m in ms),'MeanMissing':statistics.mean(m['NoQuoteFraction']for m in ms),
 'MakerUtil':statistics.mean(m['MakerUtil']for m in ms),'MakerHighUtil':statistics.mean(m['MakerHighUtil']for m in ms),
 'MakerFillAge':sum(m['MakerFillAge']*m['Passive'].get('Maker',0)for m in ms)/max(1,sum(m['Passive'].get('Maker',0)for m in ms)),
 'MakerPassiveVolume':sum(m['Passive'].get('Maker',0)for m in ms),'MakerAggressiveVolume':sum(m['Aggressor'].get('Maker',0)for m in ms),
 'Volume':sum(m['Volume']for m in ms),'Transfers':sum(x['Final']['Transferred']-x['Initial']['Transferred']for x in xs),
 'Recoveries':sum(x['Final']['Recovered']-x['Initial']['Recovered']for x in xs),
 'MakerRecoveries':sum(x['Final']['ByKind']['Maker']['Recoveries']-x['Initial']['ByKind']['Maker']['Recoveries']for x in xs),
 'MakerEquityChangeExTransfers':sum(x['Final']['ByKind']['Maker']['Equity']-x['Initial']['ByKind']['Maker']['Equity']-(x['Final']['ByKind']['Maker']['RecoveryNet']-x['Initial']['ByKind']['Maker']['RecoveryNet'])for x in xs),
 'ReplayPassed':all(x['Replay']for x in xs)}
 for x in xs:
  for k,m in x['Markets'].items():windows.append({'Case':x['Case'],'Arm':arm,'Market':k,**{p:m[p]for p in ['RangePercent','FlipRate','ChopRatio','SpreadP95','NoQuoteFraction','MakerUtil','MakerHighUtil','MakerFillAge']}})
print(json.dumps(out,indent=2));(r/'comparison-summary.json').write_text(json.dumps({'Aggregate':out,'Windows':windows},indent=2),encoding='utf8')
