from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,json,sys
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe';names=sys.argv[1:]or ['rolling-portfolio-robust','rolling-patient-robust']
def focused(name):
 folder=R/('focused-'+name);folder.mkdir(exist_ok=True)
 for suite in ['BotDiversityTests','BotWhaleTests','MakerLiquidityTests','OneSidedWhaleTests']:
  p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'suite','Candidate',suite,'variants/'+name,folder.name],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
  (R/'logs'/('focused-'+name+'-'+suite+'.log')).write_text(p.stdout+p.stderr,encoding='utf8');assert p.returncode==0,p.stderr
  d=json.loads((folder/('Candidate-'+suite+'.json')).read_text());assert d['Ok']and all(x['Passed']for x in d['Results']),d
  print('Focused passed',name,suite,len(d['Results']),flush=True)
with ThreadPoolExecutor(max_workers=2)as pool:list(pool.map(focused,names))
subprocess.run([sys.executable,'-X','utf8',str(R/'run_batch.py'),'development',*names],check=True)
