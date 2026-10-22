from pathlib import Path
import json,shutil,hashlib
R=Path(__file__).resolve().parent;P=R.parent/'counterflow-20261021'
for d in ['snapshots','logs','diagnostics','suites','variants','results-baseline']:(R/d).mkdir(exist_ok=True)
parts=sorted((R/'capture').glob('part-*.txt'),key=lambda p:int(p.stem.split('-')[1]))
(R/'snapshots/normalized-CurrentBX.json').write_bytes(b''.join(p.read_bytes() for p in parts))
checks=[]
for p in (R/'original').rglob('*.luau'):
 old=P/'original'/p.relative_to(R/'original')
 checks.append({'File':str(p.relative_to(R/'original')),'SHA256':hashlib.sha256(p.read_bytes()).hexdigest(),'MatchesPrior':old.exists() and p.read_text()==old.read_text()})
assert len(checks)==105 and all(x['MatchesPrior'] for x in checks)
snapshot=json.loads((R/'snapshots/normalized-CurrentBX.json').read_text())
assert snapshot['Config']['NewsFrequency']==0
(R/'baseline-verification.json').write_text(json.dumps({'Sources':checks,'Capture':json.loads((R/'capture/metadata.json').read_text()),'NewsFrequency':snapshot['Config']['NewsFrequency']},indent=2))
for name in ['LocalLab.luau','ExactJson.luau','MomentumBenchmark.luau','Diagnose.luau','analyze.py','shape_metrics.py','plot_comparison.py']:
 (R/name).write_text((P/name).read_text().replace('counterflow-20261021','feedback-20261021'),encoding='utf8')
for name in ['Seed71','Seed7919','Seed104729','Older','Aged']:
 shutil.copy2(P/'snapshots'/f'normalized-{name}.json',R/'snapshots'/f'normalized-{name}.json')
print('Verified 105 identical Studio modules, news disabled; current saved step',snapshot['Engine']['Step'])
