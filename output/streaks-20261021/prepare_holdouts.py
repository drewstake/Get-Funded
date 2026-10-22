from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
def run(mode,name):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),mode,'Baseline',name],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'prepare-{name}.log').write_text(p.stdout+p.stderr)
 assert p.returncode==0,p.stderr
 return p.stdout
with ThreadPoolExecutor(max_workers=2)as pool:
 for j in as_completed([pool.submit(run,m,n)for m,n in [('seed','907'),('seed','65537'),('later','Current'),('later','Older')]]):print(j.result(),flush=True)
