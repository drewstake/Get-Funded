from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,sys,shutil
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
plan=json.loads((R/'experiment.json').read_text());stage=sys.argv[1]if len(sys.argv)>1 else 'development'
names=sys.argv[2:]or plan['Candidates'];cases=plan['Development' if stage=='development'else 'Validation']
def call(args,label):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),*args],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'{label}.log').write_text(p.stdout+p.stderr,encoding='utf8')
 assert p.returncode==0,(label,p.stderr)
 print('done',label,flush=True)
def run(case):
 base=R/f'{stage}-baseline';base.mkdir(exist_ok=True)
 if not (base/f'{case}-Baseline.json').exists():call(['benchmark','Baseline',case,'variants/episode',base.name],f'{stage}-Baseline-{case}')
 for name in names:
  folder=R/f'{stage}-{name}';folder.mkdir(exist_ok=True)
  shutil.copy2(base/f'{case}-Baseline.json',folder/f'{case}-Baseline.json')
  if not (folder/f'{case}-Candidate.json').exists():call(['benchmark','Candidate',case,'variants/'+name,folder.name],f'{stage}-{name}-{case}')
with ThreadPoolExecutor(max_workers=4)as pool:
 for f in as_completed([pool.submit(run,c)for c in cases]):f.result()
