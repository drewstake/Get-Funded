from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe';(R/'details').mkdir(exist_ok=True)
def run(case,arm):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'benchmark',arm,case,'candidate','details'],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'details-{case}-{arm}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr;return case,arm
with ThreadPoolExecutor(max_workers=3)as pool:
 for j in as_completed([pool.submit(run,n,a)for n in ['Seed907','CurrentLater']for a in ['Baseline','Candidate']]):print(j.result(),flush=True)
