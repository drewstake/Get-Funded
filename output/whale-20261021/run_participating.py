from concurrent.futures import ThreadPoolExecutor,as_completed
from pathlib import Path
import subprocess,time
r=Path(__file__).resolve().parent
cases=['Seed71','Seed7919','Seed104729','Current','Older','Aged']
def run(name):
 p=subprocess.run([str(r.parent/'momentum-20261021/runtime/lune.exe'),'run',str(r/'LocalLab.luau'),'benchmark','Candidate',name,'variants/participating','results-participating'],cwd=r.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (r/'logs'/f'participating-{name}.log').write_text(p.stdout+p.stderr,encoding='utf8')
 if p.returncode:raise RuntimeError(p.stdout+p.stderr)
 return p.stdout.strip()
with ThreadPoolExecutor(max_workers=3)as pool:
 for job in as_completed({pool.submit(run,n):n for n in cases}):print(job.result(),flush=True)
