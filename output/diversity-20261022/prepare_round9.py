from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;parent='last-reserve-diverse';name='last-reserve-contiguous'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
s=files['MarketConfig.luau'];needle='MakerLanes = {Count=20,SpacingTicks={BX=6,BT=18,BG=6}}';assert s.count(needle)==1
files['MarketConfig.luau']=s.replace(needle,'MakerLanes = {Count=20,SpacingTicks={BX=1,BT=3,BG=1}}')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round9-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round9-plan.json').write_text(json.dumps({'Basis':'Read-only CurrentBX quote statistics show half-spread <=3 for every BX/BG sampled second and 99.5% of BT seconds, while actual spreads repeatedly reach 9/27 ticks. Requested-width cap failed. This points to gaps after depletion, not ordinary requested widths.',
 'Variant':name,'Change':'Place successive independent Maker lanes one tick apart in BX/BG and three ticks in BT (same price-scale ratio). Keep 20 lanes and three funded Makers per lane, all quantities and refill delays. The book may still be empty or wide; no forced quotes, price writes or refill.',
 'Hypothesis':'Nearby independently funded next levels absorb depletion without increasing the number at the best quote. Observe the movement/liquidity tradeoff under identical institutional order flow policies.',
 'Selection':'Unchanged six-case development gates and chart review. Holdouts remain untouched.'},indent=2))
print('Frozen',name)
