from pathlib import Path
import json,hashlib,statistics,sys
from analyze import summarize
R=Path(__file__).resolve().parent
v3='--v3'in sys.argv;suffix='-v3'if v3 else''
checks={};evidence={}
for folder,expected in [('development-v3'if v3 else'results-shorter-thinner',6),('holdout'+suffix,4)]:
 d=summarize(folder);(R/(folder+'-summary.json')).write_text(json.dumps(d,indent=2),encoding='utf8')
 b,c=d['Aggregate']['Baseline'],d['Aggregate']['Candidate'];checks[folder+' complete']=len(d['Cases'])==expected
 checks[folder+' streaks']=c['LongestRun']<=b['LongestRun']*(.75 if expected==6 else 1)
 checks[folder+' pullbacks']=c['Pullbacks']>=b['Pullbacks']*1.5
 wins=sum(sum(x['Pullbacks']for x in d['Markets']if x['Case']==case and x['Arm']=='Candidate')>sum(x['Pullbacks']for x in d['Markets']if x['Case']==case and x['Arm']=='Baseline')for case in d['Cases'])
 checks[folder+' majority']=wins>expected/2
 checks[folder+' volatility']=c['OneSecondRV']>=b['OneSecondRV']*1.1
 checks[folder+' barcode']=c['Alternating4Fraction']<.1
 checks[folder+' recovery']=c['Transfers']<=b['Transfers']*1.1
 checks[folder+' replay']=b['Replay']and c['Replay']
 evidence[folder]={'Baseline':b,'Candidate':c,'CasesWithMorePullbacks':wins}
 data={arm:[json.loads(p.read_text(encoding='utf8'))for p in(R/folder).glob('*-'+arm+'.json')]for arm in ['Baseline','Candidate']}
 insolvent={a:sum(s['Count']-s['PositiveEquity']for d in ds for s in d['Final']['ByKind'].values())for a,ds in data.items()}
 eligible={a:sum(s['Eligible']for d in ds for s in d['Final']['ByKind'].values())for a,ds in data.items()}
 checks[folder+' insolvency']=insolvent['Candidate']<=insolvent['Baseline']
 checks[folder+' participation']=eligible['Candidate']>=eligible['Baseline']*.95
 evidence[folder]['Insolvent']=insolvent;evidence[folder]['Eligible']=eligible
detail=json.loads((R/('details-summary'+suffix+'.json')).read_text(encoding='utf8'));b,c=detail['Aggregate']['Baseline'],detail['Aggregate']['Candidate']
checks['Volatility beyond bid-ask bounce']=len(detail['Cases'])==2 and detail['MatchesOriginalExecution']and c['FifteenSecondRV']>b['FifteenSecondRV']and c['FifteenSecondMidpointRV']>b['FifteenSecondMidpointRV']
checks['Native exact full-state parity']=json.loads((R/'runtime-parity.json').read_text())['Differences']==0
suite=json.loads((R/'suite-comparison.json').read_text());checks['Native safeguards']=not suite['NewFailures']and not suite['Candidate']['Crashed']and suite['Candidate']['Passed']>=(253 if v3 else 251)
endurance=[]
for p in(R/('no-recycling'+suffix)).glob('*.json'):
 d=json.loads(p.read_text(encoding='utf8'));blocks={k:[sum(b['Volume']for b in m['Bars'][i:i+30])for i in range(0,90,30)]for k,m in d['Markets'].items()}
 checks[p.stem+' funded endurance']=d['Replay']and d['Final']['Transferred']==d['Initial']['Transferred']and d['Final']['Recovered']==d['Initial']['Recovered']and all(min(v)>0 for v in blocks.values())
 endurance.append({'Case':d['Case'],'Arm':d['Arm'],'Blocks':blocks,'Positive':sum(x['PositiveEquity']for x in d['Final']['ByKind'].values()),'Count':sum(x['Count']for x in d['Final']['ByKind'].values())})
checks['Endurance complete']=len(endurance)==4
checks['Transition quotes']=all(json.loads((R/('transition'+suffix)/f'{n}-Candidate.json').read_text())['Missing']==0 for n in ['CurrentLater','OlderLater'])
hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in(R/('candidate'+suffix)).glob('*.luau')};(R/('candidate-manifest'+suffix+'.json')).write_text(json.dumps(hashes,indent=2))
result={'Passed':all(checks.values()),'Checks':checks,'CandidateHashes':hashes,'Evidence':evidence,'Endurance':endurance,'Details':detail['Aggregate'],'RangeTradeoff':'Mean 30-minute range remains below the requested soft target; no price outcome is forced.'}
(R/('installation-gates'+suffix+'.json')).write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps({'Passed':result['Passed'],'Checks':checks,'Endurance':endurance},indent=2));assert result['Passed']
