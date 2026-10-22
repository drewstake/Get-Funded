from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent;folder=R/sys.argv[1];out={}
for arm in ['Baseline','Candidate']:
 rows=[json.loads(p.read_text())for p in sorted(folder.glob(arm+'-*.json'))]
 for d in rows:
  if isinstance(d['Results'],dict):d['Results']=d['Results']['Results']
 out[arm]={'Suites':len(rows),'Crashes':[(d['Suite'],d['Results'])for d in rows if not d['Ok']],
 'Passed':sum(bool(x['Passed'])for d in rows if d['Ok']for x in d['Results']),
 'Failures':[(d['Suite'],x['Name'],x.get('Detail'))for d in rows if d['Ok']for x in d['Results']if not x['Passed']]}
b={(s,n)for s,n,_ in out['Baseline']['Failures']}
out['NewFailures']=[x for x in out['Candidate']['Failures']if tuple(x[:2])not in b]
b={s for s,_ in out['Baseline']['Crashes']};out['NewCrashes']=[x for x in out['Candidate']['Crashes']if x[0]not in b]
out['Complete']=out['Baseline']['Suites']==21 and out['Candidate']['Suites']==22
(R/(folder.name+'-comparison.json')).write_text(json.dumps(out,indent=2))
print(json.dumps({a:{k:(len(v)if isinstance(v,list)else v)for k,v in out[a].items()}for a in ['Baseline','Candidate']},indent=2))
print('Complete',out['Complete'],'new failures',out['NewFailures'],'new crashes',out['NewCrashes'])
