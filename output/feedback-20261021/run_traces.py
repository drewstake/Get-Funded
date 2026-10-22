from pathlib import Path
import subprocess
from concurrent.futures import ThreadPoolExecutor,as_completed
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
def run(job):
 case,mode=job
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),mode,'Baseline',case],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'{mode}-{case}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr
 print('done',case,mode,flush=True)
with ThreadPoolExecutor(max_workers=2)as pool:
 for f in as_completed([pool.submit(run,j)for j in [('CurrentBX','diagnose'),('Seed71','diagnose'),('CurrentBX','tracecontrol')]]):f.result()
