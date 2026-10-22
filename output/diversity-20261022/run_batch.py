from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,sys,shutil,hashlib,re
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
plan=json.loads((R/'experiment.json').read_text());stage=sys.argv[1]if len(sys.argv)>1 else 'development'
extra=sys.argv[2:];tags=[x.split('=',1)[1]for x in extra if x.startswith('--tag=')]
assert len(tags)<=1 and all(re.fullmatch('[A-Za-z0-9_-]+',x)for x in tags)
prefix=stage+('-'+tags[0]if tags else '')
names=[x for x in extra if not x.startswith('--tag=')]or plan['Candidates'];cases=plan['Development' if stage=='development'else 'Validation']
def call(args,label):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),*args],cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/f'{label}.log').write_text(p.stdout+p.stderr,encoding='utf8')
 assert p.returncode==0,(label,p.stderr)
 print('done',label,flush=True)
def run(case):
 base=R/f'{prefix}-baseline';base.mkdir(exist_ok=True)
 if not (base/f'{case}-Baseline.json').exists():call(['benchmark','Baseline',case,'variants/stretch',base.name],f'{prefix}-Baseline-{case}')
 for name in names:
  d=R/'variants'/name
  manifest=json.loads((d/'manifest.json').read_text())
  assert all(hashlib.sha256((d/f).read_text().encode()).hexdigest()==sha for f,sha in manifest.items()),name+' modified after freeze'
  folder=R/f'{prefix}-{name}';folder.mkdir(exist_ok=True)
  shutil.copy2(base/f'{case}-Baseline.json',folder/f'{case}-Baseline.json')
  if not (folder/f'{case}-Candidate.json').exists():call(['benchmark','Candidate',case,'variants/'+name,folder.name],f'{prefix}-{name}-{case}')
with ThreadPoolExecutor(max_workers=4)as pool:
 for f in as_completed([pool.submit(run,c)for c in cases]):f.result()
