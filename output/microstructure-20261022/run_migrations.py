from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,sys
R=Path(__file__).resolve().parent; L=R.parent/'momentum-20261021/runtime/lune.exe'
(R/'migrations').mkdir(exist_ok=True)
names=sys.argv[1:]or sorted(p.name for p in (R/'variants').iterdir())
def run(name):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'migrationprobe','Candidate','CurrentBX','variants/'+name,'migrations'],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/('migration-'+name+'.log')).write_text(p.stdout+p.stderr)
 assert p.returncode==0,(name,p.stderr)
 print(p.stdout.strip(),flush=True)
with ThreadPoolExecutor(max_workers=2)as pool:list(pool.map(run,names))
