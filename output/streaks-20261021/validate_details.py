from pathlib import Path
import json,statistics,sys
R=Path(__file__).resolve().parent
suffix='-v3'if '--v3'in sys.argv else''
rows=[]
for p in(R/('details'+suffix)).glob('*.json'):
 d=json.loads(p.read_text(encoding='utf8'));old=json.loads((R/('holdout'+suffix)/p.name).read_text(encoding='utf8'))
 for key in ['Initial','Final','Audit','Replay','MeasuredStart','MeasuredSeconds']:assert d[key]==old[key],(p.name,key)
 for k,m in d['Markets'].items():
  for f in ['Bars','Volume','Trades','OneSecondRV']:assert m[f]==old['Markets'][k][f],(p.name,k,f)
  rows.append({'Case':d['Case'],'Arm':d['Arm'],'Market':k,**{f:m[f]for f in ['OneSecondRV','OneSecondMidpointRV','FifteenSecondRV','FifteenSecondMidpointRV']}})
cases=sorted({r['Case']for r in rows if r['Arm']=='Candidate'} & {r['Case']for r in rows if r['Arm']=='Baseline'})
result={'Cases':cases,'MatchesOriginalExecution':True,'Aggregate':{},'Rows':rows}
for arm in ['Baseline','Candidate']:
 xs=[r for r in rows if r['Arm']==arm and r['Case']in cases]
 if xs:result['Aggregate'][arm]={f:statistics.mean(r[f]for r in xs)for f in ['OneSecondRV','OneSecondMidpointRV','FifteenSecondRV','FifteenSecondMidpointRV']}
(R/('details-summary'+suffix+'.json')).write_text(json.dumps(result,indent=2),encoding='utf8');print(json.dumps({k:v for k,v in result.items()if k!='Rows'},indent=2))
