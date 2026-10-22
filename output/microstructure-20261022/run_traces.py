from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess,json,sys
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
def run(args):
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),*args],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/('-'.join(args[:3])+'.log')).write_text(p.stdout+p.stderr)
 assert p.returncode==0,p.stderr
 print('done',*args[:3],flush=True)
jobs=[['diagnose','Baseline',n]for n in ['CurrentBX','Seed71']]+[['tracecontrol','Baseline','CurrentBX']]
with ThreadPoolExecutor(max_workers=3)as pool:list(pool.map(run,jobs))
a=json.loads((R/'diagnostics/CurrentBX-diagnose-terminal.json').read_text());b=json.loads((R/'diagnostics/CurrentBX-tracecontrol-terminal.json').read_text())
assert a==b,'Instrumentation changes economic state'
(R/'instrumentation-parity.json').write_text(json.dumps({'FullCheckpointExact':True,'Case':'CurrentBX','Step':a['Engine']['Step'],'TradeHash':a['Engine']['TradeHash']},indent=2))
