from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,sys,hashlib
R=Path(__file__).resolve().parent;name=sys.argv[1];L=R.parent/'momentum-20261021/runtime/lune.exe'
m=json.loads((R/'variants'/name/'manifest.json').read_text());assert all(hashlib.sha256((R/'variants'/name/f).read_text(encoding='utf8').encode()).hexdigest()==h for f,h in m.items())
folder='local-suites-'+name;(R/folder).mkdir(exist_ok=True)
suites=['BotExitRetryTests','BotFairnessTests','BotMomentumTests','BotOrderFlowTests','BotParticipationTests','BotPublicInformationTests','BotRefreshTests','BotSignalsTests','BotWhaleTests','ExecutionChoiceTests','ExecutionIntegrityTests','MakerLiquidityTests','MarketTests','OrderFlowMarketTests','ProtectionScaleTests','ProtectiveOrdersTests','ScalperTests','SecurityTests','SharedDepthTests','TradeLimitsTests','WorldTests']
def run(arm,suite):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'suite',arm,suite,'variants/'+name,folder],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/('suite-'+name+'-'+arm+'-'+suite+'.log')).write_text(p.stdout+p.stderr,encoding='utf8');assert p.returncode==0,p.stderr
 d=json.loads((R/folder/(arm+'-'+suite+'.json')).read_text());results=d['Results'];results=results['Results']if isinstance(results,dict)else results;failed=not d['Ok']or any(not x['Passed']for x in results)
 print(arm,suite,'failures'if failed else'passed',flush=True)
with ThreadPoolExecutor(max_workers=2)as pool:
 futures=[pool.submit(run,arm,suite)for arm in ['Baseline','Candidate']for suite in suites+(['BotDiversityTests']if arm=='Candidate'else[])]
 for f in as_completed(futures):f.result()
out={}
for arm in ['Baseline','Candidate']:
 rows=[json.loads(p.read_text())for p in (R/folder).glob(arm+'-*.json')]
 for d in rows:
  if isinstance(d['Results'],dict):d['Results']=d['Results']['Results']
 out[arm]={'Suites':len(rows),'Crashes':[(d['Suite'],d['Results'])for d in rows if not d['Ok']],
 'Passed':sum(x['Passed']for d in rows if d['Ok']for x in d['Results']),
 'Failures':[(d['Suite'],x['Name'],x['Detail'])for d in rows if d['Ok']for x in d['Results']if not x['Passed']]}
b={(s,n)for s,n,_ in out['Baseline']['Failures']};out['NewFailures']=[x for x in out['Candidate']['Failures']if tuple(x[:2])not in b]
(R/(folder+'-comparison.json')).write_text(json.dumps(out,indent=2));print('New failures:',out['NewFailures'])
