from pathlib import Path
import json, statistics

root=Path(__file__).resolve().parent
records=[json.loads(p.read_text(encoding='utf-8')) for p in sorted((root/'results').glob('*.json'))]
rows=[]
for r in records:
    initial=r['Initial']['ByKind']['Momentum']; final=r['Final']['ByKind']['Momentum']
    print(r['Case'],r['Arm'],'range',','.join(f'{k}:{v["RangePercent"]:.3f}%' for k,v in r['Markets'].items()),
          'momentum pnl',round(final['Realized']-initial['Realized']),
          'recoveries',r['Final']['Recovered']-r['Initial']['Recovered'],'replay',r['Replay'])
    for market,m in r['Markets'].items():
        rows.append({'Case':r['Case'],'Arm':r['Arm'],'Market':market,'RangePercent':m['RangePercent'],
                     'FlipRate':m['FlipRate'],'ReturnCorrelation':m['ReturnCorrelation'],'ChopRatio':m['ChopRatio'],
                     'SpreadP95':m['SpreadP95'],'NoQuoteFraction':m['NoQuoteFraction'],'Volume':m['Volume'],
                     'MidpointFlipRate':m['Midpoint']['FlipRate'],'MidpointReturnCorrelation':m['Midpoint']['ReturnCorrelation'],
                     'MomentumVolume':m['Aggressor'].get('Momentum',0)})
summary={}
for arm in ('Baseline','Candidate'):
    rs=[r for r in records if r['Arm']==arm]; ms=[r for r in rows if r['Arm']==arm]
    if not rs:continue
    summary[arm]={'Runs':len(rs),'MarketWindows':len(ms),'InTarget':sum(.7<=m['RangePercent']<=1.5 for m in ms),
                  'MeanRange':statistics.mean(m['RangePercent']for m in ms),'MedianRange':statistics.median(m['RangePercent']for m in ms),
                  'MeanFlip':statistics.mean(m['FlipRate']for m in ms),'MeanChop':statistics.mean(m['ChopRatio']for m in ms),
                  'MeanSpreadP95':statistics.mean(m['SpreadP95']for m in ms),'MeanMissing':statistics.mean(m['NoQuoteFraction']for m in ms),
                  'MomentumAggressorVolume':sum(m['MomentumVolume']for m in ms),
                  'Transfers':sum(r['Final']['Transferred']-r['Initial']['Transferred']for r in rs),
                  'Recoveries':sum(r['Final']['Recovered']-r['Initial']['Recovered']for r in rs),
                  'MomentumRealizedChange':sum(r['Final']['ByKind']['Momentum']['Realized']-r['Initial']['ByKind']['Momentum']['Realized']for r in rs),
                  'MomentumEquityChangeExTransfers':sum((r['Final']['ByKind']['Momentum']['Equity']-r['Initial']['ByKind']['Momentum']['Equity'])-(r['Final']['ByKind']['Momentum']['RecoveryNet']-r['Initial']['ByKind']['Momentum']['RecoveryNet'])for r in rs),
                  'ReplayPassed':all(r['Replay']for r in rs)}
print(json.dumps(summary,indent=2))
(root/'comparison-summary.json').write_text(json.dumps({'Aggregate':summary,'Windows':rows},indent=2),encoding='utf-8')
