from pathlib import Path
import json
R=Path(__file__).resolve().parent
rows=[]
for folder in sorted(R.glob('no-recovery-*')):
 if not folder.is_dir():continue
 for p in folder.glob('*.json'):
  d=json.loads(p.read_text());name=folder.name.removeprefix('no-recovery-')
  if d['Arm']=='Baseline'and name!='baseline':continue
  blocks={key:[sum(b['Volume']for b in m['Bars'][i:i+30])for i in range(0,len(m['Bars']),30)]for key,m in d['Markets'].items()}
  zero=d['Final']['Transferred']==d['Initial']['Transferred']and d['Final']['Recovered']==d['Initial']['Recovered']
  assert zero and all(v>0 for xs in blocks.values()for v in xs)and d['Replay']
  kinds={}
  for k,final in d['Final']['ByKind'].items():
   initial=d['Initial']['ByKind'][k]
   assert final['PositiveEquity']==final['Count'],(name,d['Case'],k,'nonpositive equity')
   kinds[k]={'EquityChangeExTransfers':final['Equity']-initial['Equity']-final['RecoveryNet']+initial['RecoveryNet'],
    'Count':final['Count'],'PositiveEquity':final['PositiveEquity'],'AboveOwnFloorStart':initial['AboveOwnRiskFloor'],'AboveOwnFloorEnd':final['AboveOwnRiskFloor'],'EligibleEnd':final['Eligible']}
  rows.append({'Variant':name,'Case':d['Case'],'RecoveryTransfers':d['Final']['Transferred']-d['Initial']['Transferred'],'Recoveries':d['Final']['Recovered']-d['Initial']['Recovered'],'Blocks':blocks,'Kinds':kinds,'Audit':d['Audit'],'Replay':d['Replay'],'SpreadP95':{k:m['SpreadP95']for k,m in d['Markets'].items()},'MissingFraction':{k:m['NoQuoteFraction']for k,m in d['Markets'].items()}})
(R/'endurance-summary.json').write_text(json.dumps(rows,indent=2))
for r in rows:print(r['Variant'],r['Case'],'Maker P&L',round(r['Kinds']['Maker']['EquityChangeExTransfers'],2),'Maker above floor',r['Kinds']['Maker']['AboveOwnFloorEnd'],'/180','zero recovery',r['RecoveryTransfers'],'volume',r['Blocks'])
