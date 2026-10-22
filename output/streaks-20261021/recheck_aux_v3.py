from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,shutil
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
def run(case,kind):
 folder='no-recycling'if kind=='norecycle'else'details';out=R/(folder+'-v3');out.mkdir(exist_ok=True)
 shutil.copy2(R/folder/f'{case}-Baseline.json',out/f'{case}-Baseline.json')
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),kind,'Candidate',case,'candidate-v3',out.name],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'v3-{kind}-{case}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr;return case,kind
with ThreadPoolExecutor(max_workers=4)as pool:
 for j in as_completed([pool.submit(run,n,k)for n in ['Seed907','CurrentLater']for k in ['norecycle','benchmark']]):print('done',j.result(),flush=True)
