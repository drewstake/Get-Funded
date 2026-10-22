from pathlib import Path
import json
from metrics import summarize
R=Path(__file__).resolve().parent;plan=json.loads((R/'experiment.json').read_text());rows=[];details={}
names=plan['Candidates']
for name in names:
 folder=R/('development-'+name)
 if len(list(folder.glob('*-Candidate.json')))!=6:continue
 d=summarize(folder.name);(R/(folder.name+'-metrics.json')).write_text(json.dumps(d,indent=2));details[name]=d
 a=d['Aggregate']['Candidate'];current=next(x for x in d['Markets']if x['Arm']=='Candidate'and x['Market']=='BX'and x['Case']=='CurrentBX')
 failures=[k for k,v in d['Gates'].items()if not v]
 rows.append([name,f"{a['MeaningfulLong8']*100:.2f}%",f"{a['MeaningfulMaxLeg']:.2f}",str(round(a['MeaningfulCounters']*18)),str(round(a['MeaningfulPullbacks']*18)),f"{a['OneMinuteRV']:.4f}%",f"{a['MeanRange30']:.4f}%",f"{a['SpreadP95']:.3f}",f"${a['Recovery']/1e6:.3f}m",', '.join(failures)or'Numeric pass; chart review required'])
headers=['Frozen arm','Long-leg occupancy','Max leg (mean min)','Counter events','Strict pullbacks','Minute RV','30m range','p95 spread (mean ticks)','Recovery','Failed development gates']
text='# Complete six-case development results\n\nSame snapshots, 20-minute adaptation, 60-minute measured candles, three markets per case. All listed runs have exact serialized replay and positive terminal equity. Values are development results, not independent validation.\n\n'
text+='| '+' | '.join(headers)+' |\n| '+' | '.join(['---']*len(headers))+' |\n'
b=next(iter(details.values()))['Aggregate']['Baseline']
text+='| Installed baseline | '+f"{b['MeaningfulLong8']*100:.2f}% | {b['MeaningfulMaxLeg']:.2f} | {b['MeaningfulCounters']*18:.0f} | {b['MeaningfulPullbacks']*18:.0f} | {b['OneMinuteRV']:.4f}% | {b['MeanRange30']:.4f}% | {b['SpreadP95']:.3f} | ${b['Recovery']/1e6:.3f}m | Reference |\n"
text+='\n'.join('| '+' | '.join(row)+' |'for row in rows)+'\n'
text+='\nEvery arm has an immutable source manifest and patch in `variants/<name>/`, paired raw data in `development-<name>/`, and exact metrics in `development-<name>-metrics.json`. Candle figures are named `development-<name>-BX.png`, `-BT.png`, and `-BG.png`.\n'
reviews=json.loads((R/'chart-review.json').read_text())['RejectedNumericPasses']
text+='\n## Current saved BX world and liquidity\n\nCurrent-BX columns refer only to BX in that saved case; missing-quote and volume columns average all eighteen measured market-hours. Volume counts matched contracts once. Chart links contain all six paired cases at comparable vertical scales.\n\n'
text+='| Arm | Current BX long-leg occupancy | Max leg | Counter events | Strict pullbacks | Minute RV | Missing quotes (mean) | Matched volume (mean) | Charts |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
for name,d in details.items():
 a=d['Aggregate']['Candidate'];c=next(x for x in d['Markets']if x['Arm']=='Candidate'and x['Case']=='CurrentBX'and x['Market']=='BX')
 links=' / '.join(f'[{market}](development-{name}-{market}.png)'for market in ['BX','BT','BG'])
 text+=f"| {name} | {c['MeaningfulLong8']*100:.2f}% | {c['MeaningfulMaxLeg']}m | {c['MeaningfulCounters']} | {c['MeaningfulPullbacks']} | {c['OneMinuteRV']:.4f}% | {a['NoQuoteFraction']*100:.4f}% | {a['Volume']:,.1f} | {links} |\n"
text+='\n## Numerical passes rejected on chart review\n\n'
for name,review in reviews.items():text+=f"- **{name}:** {review['Reason']} [Candles]({review['Evidence']}).\n"
text+='\n## Compatibility derivatives and aborted implementations\n\nThe two compatibility derivatives are not additional economic hypotheses: `last-reserve-diverse-ready` and `inner-patient-stretch-ready` reproduce their parents across all six measured paths and accounting results. Their broader regression results are in RESULTS.md; the second retains one new geometry-test failure in its immutable source.\n\n'
for name in plan['AbortedCandidates']:
 text+=f'- **{name}:** incomplete and rejected; [reason](variants/{name}/rejection.json). Partial files and source manifests are retained and excluded from full-batch averages.\n'
(R/'DEVELOPMENT.md').write_text(text,encoding='utf8');(R/'development-all-summary.json').write_text(json.dumps({n:{k:v for k,v in d.items()if k!='Markets'}for n,d in details.items()},indent=2))
print('Complete six-case arms:',len(rows),'/',len(names))
