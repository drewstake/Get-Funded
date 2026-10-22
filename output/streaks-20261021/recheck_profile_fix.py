from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,shutil,time
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
cases=['Seed71','Seed7919','Seed104729','Current','Older','Aged','Seed907','Seed65537','CurrentLater','OlderLater']
def run(case):
 folder='development-v3'if case in cases[:6]else'holdout-v3';out=R/folder;out.mkdir(exist_ok=True)
 original=R/('results-shorter-thinner'if folder=='development-v3'else'holdout')/f'{case}-Baseline.json';shutil.copy2(original,out/original.name)
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'benchmark','Candidate',case,'candidate-v3',folder],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'v3-{case}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr;return case
t=time.time()
with ThreadPoolExecutor(max_workers=5)as pool:
 for j in as_completed([pool.submit(run,n)for n in cases]):print('done',j.result(),round(time.time()-t),flush=True)
