"""All six attacks on detached saved worlds. Never refreshes bots or writes services."""
from pathlib import Path
import argparse,subprocess,json,hashlib
ROOT=Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('variant',choices=['baseline','candidate']);p.add_argument('--label',default='stress');args=p.parse_args()
out=ROOT/'output/latency-20261027'/(args.label+'-'+args.variant)
assert not out.exists()
subprocess.run([str(ROOT/'.venv-build/Scripts/python.exe'),str(ROOT/'tools/protection-safety/prepare.py'),'--output',str(out)],check=True)
if args.variant=='baseline':
    import shutil
    for source in (ROOT/'output/latency-20261027/baseline/candidate').rglob('*.luau'):
        shutil.copyfile(source,out/'candidate'/source.name)
    for source in (ROOT/'output/latency-20261027/baseline/original').rglob('*.luau'):
        shutil.copyfile(source,out/'original'/source.name)
source=(ROOT/'tools/market-safety/stress.luau').read_text()
source=source.replace('__OUTPUT__',json.dumps(out.as_posix()))
source=source.replace("local selected=require('@lune/process').args[1]", """local selected=require('@lune/process').args[1]
local CP=require('./candidate/WorldCheckpoint')
local http=require('./environment').game:GetService('HttpService')
local saved=CP.Decode(http:JSONDecode(fs.readFile('output/latency-20261027/saved-checkpoint.json')).Checkpoint)
report.Scope='All six scenarios on independently restored copies of the saved BX world; no refresh or writes'
report.SavedStep=saved.Engine.Step""")
source=source.replace('local e=E.new(c,seed);local p=P.new(e)','local e,p=CP.Restore(saved,c)')
(out/'stress.luau').write_text(source,encoding='utf-8')
with (out/'stress.log').open('w') as log:
    result=subprocess.run([str(ROOT/'tools/runtime/lune.exe'),'run',str(out/'stress.luau')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
assert result.returncode==0, f'Failure: {out}/stress.log'
report=json.loads((out/'stress-results.json').read_text())
assert {r['Mode'] for r in report['Scenarios']}=={'buy','sell','cycle','passive','multi-owner','rich'}
assert all(r['RemainingAfterClose']==0 and r['MaxPlayerContracts']<=200 and r['MaxReserveContracts']<=200 and r['MaxReserveDepleted']==0 for r in report['Scenarios'])
(out/'validated-sources.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (out/'original').rglob('*.luau')},indent=2))
print('PASS all six saved-world scenarios:',args.variant)
