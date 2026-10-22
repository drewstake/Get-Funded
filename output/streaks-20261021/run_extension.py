from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,hashlib,time,shutil
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
cases=[('Seed314159','seed','314159'),('Seed271828','seed','271828'),('Seed161803','seed','161803'),('CurrentPlus60','later','CurrentLater'),('OlderPlus60','later','OlderLater'),('AgedLater','later','Aged')]
plan={'Cases':[c[0]for c in cases],'Reason':'Corrected policy improves aggregate results but initial four-case pullback-majority check is inconclusive/failed; one fixed extra batch, no tuning','SourceHashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in(R/'candidate-v3').glob('*.luau')},'Acceptance':'All six complete; aggregate volatility and pullbacks improve; strict pullback improvement in at least four of six new cases and at least six of ten combined validation cases; all existing safety/funding gates retained.'}
(R/'extension-plan.json').write_text(json.dumps(plan,indent=2));out=R/'extension-v3';out.mkdir(exist_ok=True)
def command(mode,arm,name,folder=None):
 args=[str(L),'run',str(R/'LocalLab.luau'),mode,arm,name,'candidate-v3',folder or out.name]
 p=subprocess.run(args,cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'extension-{mode}-{arm}-{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr
def run(case,mode,name):
 command(mode,'Baseline',name)
 generated='Seed'+name if mode=='seed'else name+'Later'
 if generated!=case:shutil.copy2(R/'snapshots'/f'normalized-{generated}.json',R/'snapshots'/f'normalized-{case}.json')
 for arm in ['Baseline','Candidate']:command('benchmark',arm,case)
 for p in(R/'candidate-v3').glob('*.luau'):assert hashlib.sha256(p.read_bytes()).hexdigest()==plan['SourceHashes'][p.name]
 return case
t=time.time()
with ThreadPoolExecutor(max_workers=6)as pool:
 for j in as_completed([pool.submit(run,*c)for c in cases]):print('done',j.result(),round(time.time()-t),flush=True)
