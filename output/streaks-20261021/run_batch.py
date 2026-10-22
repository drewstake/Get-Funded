from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import subprocess,sys,time,shutil
R=Path(__file__).resolve().parent;W=R.parents[1];L=R.parent/'momentum-20261021/runtime/lune.exe'
variant=sys.argv[1];cases=sys.argv[2:]or ['Seed71','Seed7919','Seed104729','Current','Older','Aged']
out=R/('results-'+variant);out.mkdir(exist_ok=True)
def run(case):
    baseline=R.parent/'reversion-20261021/results'/f'{case}-Baseline.json'
    if baseline.exists():shutil.copy2(baseline,out/baseline.name)
    arms=['Candidate']if baseline.exists()else ['Baseline','Candidate']
    for arm in arms:
        result=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'benchmark',arm,case,'variants/'+variant,out.name],cwd=W,capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        (R/'logs'/f'{variant}-{case}-{arm}.log').write_text(result.stdout+result.stderr,encoding='utf8')
        if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    return case
t=time.time()
with ThreadPoolExecutor(max_workers=3)as pool:
    for job in as_completed([pool.submit(run,n)for n in cases]):print('done',variant,job.result(),round(time.time()-t),flush=True)
