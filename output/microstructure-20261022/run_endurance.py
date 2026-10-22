from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,json,sys,shutil,hashlib
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
names=sys.argv[1:]or ['no-skew-reserve-delay'];cases=['Seed71','CurrentBX']
prior=json.loads((R/'endurance-plan.json').read_text()).get('Variants',[])if(R/'endurance-plan.json').exists()else[]
(R/'endurance-plan.json').write_text(json.dumps({'Cases':cases,'Variants':list(dict.fromkeys(prior+names)),'AdaptSeconds':1200,'MeasureSeconds':5400,'Recovery':'Only BotParticipation.Rebalance disabled for entire adaptation and measurement. All risk pauses, stops, matching and limits remain.','Role':'Finite development endurance; does not rescue failed shape gates or substitute for independent validation.'},indent=2))
def run(case):
 for name,arm in [('baseline','Baseline')]+[(n,'Candidate')for n in names]:
  folder=R/('no-recovery-'+name);folder.mkdir(exist_ok=True)
  if name!='baseline':
   manifest=json.loads((R/'variants'/name/'manifest.json').read_text())
   assert all(hashlib.sha256((R/'variants'/name/f).read_text(encoding='utf8').encode()).hexdigest()==h for f,h in manifest.items())
  if not(folder/f'{case}-{arm}.json').exists():
   p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'norecycle',arm,case,'variants/'+(names[0]if name=='baseline'else name),folder.name],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
   (R/'logs'/f'endurance-{name}-{case}.log').write_text(p.stdout+p.stderr)
   assert p.returncode==0,p.stderr
  if name!='baseline':shutil.copy2(R/'no-recovery-baseline'/f'{case}-Baseline.json',folder/f'{case}-Baseline.json')
  print('endurance done',name,case,flush=True)
with ThreadPoolExecutor(max_workers=2)as pool:
 for f in as_completed([pool.submit(run,c)for c in cases]):f.result()
