from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import subprocess,json,time,shutil
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe'
cases=json.loads((R/'experiment.json').read_text())['Development']
def run(case):
    for arm,variant,folder in [('Baseline','profit','results-profit'),('Candidate','profit','results-profit'),('Candidate','profit-patient','results-profit-patient')]:
        args=[str(L),'run',str(R/'LocalLab.luau'),'benchmark',arm,case,'variants/'+variant,folder]
        p=subprocess.run(args,cwd=R.parents[1],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        (R/'logs'/f'{variant}-{arm}-{case}.log').write_text(p.stdout+p.stderr,encoding='utf8')
        assert p.returncode==0,p.stderr
        print('done',variant,arm,case,flush=True)
    shutil.copy2(R/'results-profit'/f'{case}-Baseline.json',R/'results-profit-patient'/f'{case}-Baseline.json')
with ThreadPoolExecutor(max_workers=6) as pool:
    for f in as_completed([pool.submit(run,c) for c in cases]):f.result()
