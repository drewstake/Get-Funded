from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,sys,shutil,time
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe';mode=sys.argv[1]
out=R/('holdout'if mode=='holdout'else'no-recycling');out.mkdir(exist_ok=True)
cases=['Seed907','Seed65537','CurrentLater','OlderLater']if mode=='holdout'else['Seed907','CurrentLater']
def run(case):
 for arm in ['Baseline','Candidate']:
  p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'benchmark'if mode=='holdout'else'norecycle',arm,case,'candidate',out.name],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
  (R/'logs'/f'{mode}-{case}-{arm}.log').write_text(p.stdout+p.stderr)
  assert p.returncode==0,p.stderr
 return case
t=time.time()
with ThreadPoolExecutor(max_workers=3)as pool:
 for j in as_completed([pool.submit(run,n)for n in cases]):print('done',mode,j.result(),round(time.time()-t),flush=True)
