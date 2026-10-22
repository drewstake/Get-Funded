from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import subprocess, json, time

ROOT = Path(__file__).resolve().parent
WORK = ROOT.parents[1]
LUNE = ROOT.parent / 'momentum-20261021/runtime/lune.exe'
RUNNER = ROOT / 'LocalLab.luau'
(ROOT / 'endurance').mkdir(exist_ok=True)
(ROOT / 'logs').mkdir(exist_ok=True)
def command(mode, arm, name):
    output = subprocess.run([str(LUNE), 'run', str(RUNNER), mode, arm, name], cwd=WORK, capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    (ROOT / 'logs' / f'{mode}-{arm}-{name}.log').write_text(output.stdout + output.stderr, encoding='utf-8')
    if output.returncode: raise RuntimeError(f'{mode} {arm} {name}: {output.stdout} {output.stderr}')
    return output.stdout.strip()
def run_case(name):
    if name.startswith('Seed') and not (ROOT / f'snapshots/normalized-{name}.json').exists():
        command('seed', 'Baseline', name[4:])
    result = []
    for arm in ('Baseline', 'Candidate'):
        result.append(command('norecycle', arm, name))
    return result
started=time.time()
with ThreadPoolExecutor(max_workers=3) as pool:
    jobs={pool.submit(run_case,name):name for name in ('Seed71','Current')}
    for job in as_completed(jobs):
        try: print(jobs[job], job.result(), flush=True)
        except Exception as error: print('FAILED', jobs[job], str(error), flush=True)
print('Wall seconds:', time.time()-started, flush=True)
