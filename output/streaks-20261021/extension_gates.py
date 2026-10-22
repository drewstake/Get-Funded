from pathlib import Path
import json,hashlib,shutil
from analyze import summarize
R=Path(__file__).resolve().parent
plan=json.loads((R/'extension-plan.json').read_text());d=summarize('extension-v3')
assert len(d['Cases'])==6,'Fixed extension batch incomplete'
(R/'extension-v3-summary.json').write_text(json.dumps(d,indent=2))
b,c=d['Aggregate']['Baseline'],d['Aggregate']['Candidate'];checks={}
wins=sum(sum(x['Pullbacks']for x in d['Markets']if x['Case']==n and x['Arm']=='Candidate')>sum(x['Pullbacks']for x in d['Markets']if x['Case']==n and x['Arm']=='Baseline')for n in d['Cases'])
checks['Fixed extension complete']=set(d['Cases'])==set(plan['Cases'])
checks['Extension strict majority']=wins>=4
checks['Extension pullbacks']=c['Pullbacks']>=b['Pullbacks']*1.5
checks['Extension volatility']=c['OneSecondRV']>=b['OneSecondRV']*1.1
checks['Extension streaks']=c['LongestRun']<b['LongestRun']
checks['Extension barcode']=c['Alternating4Fraction']<.1
checks['Extension recovery']=c['Transfers']<=b['Transfers']*1.1
checks['Extension replay']=c['Replay']and b['Replay']
checks['Source remained frozen']=all(hashlib.sha256((R/'candidate-v3'/n).read_bytes()).hexdigest()==h for n,h in plan['SourceHashes'].items())
joined=R/'validation-v3';joined.mkdir(exist_ok=True)
for folder in ['holdout-v3','extension-v3']:
 for p in(R/folder).glob('*.json'):shutil.copy2(p,joined/p.name)
all_d=summarize('validation-v3');(R/'validation-v3-summary.json').write_text(json.dumps(all_d,indent=2))
ab,ac=all_d['Aggregate']['Baseline'],all_d['Aggregate']['Candidate']
all_wins=sum(sum(x['Pullbacks']for x in all_d['Markets']if x['Case']==n and x['Arm']=='Candidate')>sum(x['Pullbacks']for x in all_d['Markets']if x['Case']==n and x['Arm']=='Baseline')for n in all_d['Cases'])
checks['Combined strict majority']=all_wins>=6 and len(all_d['Cases'])==10
checks['Combined pullbacks']=ac['Pullbacks']>=ab['Pullbacks']*1.5
checks['Combined volatility']=ac['OneSecondRV']>=ab['OneSecondRV']*1.1
checks['Combined streaks']=ac['LongestRun']<ab['LongestRun']
checks['Combined recovery']=ac['Transfers']<=ab['Transfers']*1.1
prior=json.loads((R/'installation-gates-v3.json').read_text())
checks.update({k:v for k,v in prior['Checks'].items()if k!='holdout-v3 majority'})
data={a:[json.loads(p.read_text(encoding='utf8'))for p in joined.glob('*-'+a+'.json')]for a in ['Baseline','Candidate']}
insolv={a:sum(s['Count']-s['PositiveEquity']for row in rows for s in row['Final']['ByKind'].values())for a,rows in data.items()}
eligible={a:sum(s['Eligible']for row in rows for s in row['Final']['ByKind'].values())for a,rows in data.items()}
checks['Combined insolvency']=insolv['Candidate']<=insolv['Baseline'];checks['Combined participation']=eligible['Candidate']>=eligible['Baseline']*.95
result={**prior,'Passed':all(checks.values()),'Checks':checks,'InitialHoldoutMajorityPassed':False,'Extension':{'Cases':d['Cases'],'Wins':wins,'Aggregate':d['Aggregate']},'CombinedValidation':{'Cases':all_d['Cases'],'Wins':all_wins,'Aggregate':all_d['Aggregate']},'ExtensionPlan':plan}
(R/'installation-gates-v3-extended.json').write_text(json.dumps(result,indent=2));print(json.dumps({'Passed':result['Passed'],'Checks':checks,'ExtensionWins':wins,'CombinedWins':all_wins,'ExtensionAggregate':{a:{k:v[k]for k in ['LongestRun','Pullbacks','OneSecondRV','MeanRange30','Transfers']}for a,v in d['Aggregate'].items()}},indent=2))
assert result['Passed']
