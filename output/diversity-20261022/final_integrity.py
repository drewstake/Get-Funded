from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
plan=json.loads((R/'experiment.json').read_text());cases=set(plan['Development']);rows=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
snapshots={c:sha(R/'snapshots'/('normalized-'+c+'.json'))for c in cases}
for name in plan['Candidates']+plan['Integrations']:
 folder=R/('development-'+name)
 paths=list(folder.glob('*-Candidate.json'));assert len(paths)==6,name
 assert {json.loads(p.read_text())['Case']for p in paths}==cases,name
 for p in paths:
  d=json.loads(p.read_text());case=d['Case'];baseline=folder/(case+'-Baseline.json')
  assert sha(baseline)==sha(R/'development-baseline'/(case+'-Baseline.json')),baseline
  assert d['Replay'] and all(x['PositiveEquity']==x['Count']for x in d['Final']['ByKind'].values()),p
  assert all(v==0 for v in d['Audit']['Inventory'].values()),p
  assert all(len(m['Bars'])==60 for m in d['Markets'].values()),p
  rows.append({'Variant':name,'Case':case,'ResultSHA256':sha(p),'SnapshotSHA256':snapshots[case],
   'BaselineByteIdentical':True,'Replay':d['Replay'],'PositiveEquityAllAccounts':True,
   'NetInventoryZero':True,'CashError':d['Audit']['CashError'],'EquityError':d['Audit']['EquityError']})
assert not any((R/'snapshots'/('normalized-'+c+'.json')).exists()for c in plan['Validation'])
aborted={n:json.loads((R/'variants'/n/'rejection.json').read_text())for n in plan['AbortedCandidates']}
out={'CompleteBehaviorArms':len(plan['Candidates']),'CompleteCompatibilityDerivatives':len(plan['Integrations']),
 'CandidateRuns':len(rows),'CandidateMeasuredMarketHours':len(rows)*3,'ReusedBaselineRuns':6,
 'ValidationGenerated':False,'MaxAbsoluteCashAuditError':max(abs(x['CashError'])for x in rows),
 'MaxAbsoluteEquityAuditError':max(abs(x['EquityError'])for x in rows),'Aborted':aborted,'Rows':rows}
(R/'run-integrity.json').write_text(json.dumps(out,indent=2));print(json.dumps({k:v for k,v in out.items()if k not in ['Rows','Aborted']},indent=2))
