from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;name='last-reserve-dense';parent='last-reserve-diverse'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
c=files['MarketConfig.luau'];assert c.count('MakerLanes = {Count=20,')==1
files['MarketConfig.luau']=c.replace('MakerLanes = {Count=20,','MakerLanes = {Count=10,')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round5-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round5-plan.json').write_text(json.dumps({'Basis':'All six last-reserve-diverse cases produce 148 meaningful counter events and 33 strict pullbacks; occupancy 61.94%, maximum leg 17.5m, minute RV .343%, mean range .416%. Only spread fails: mean p95 6.389 ticks vs fixed 6-tick floor. Test original 10 Maker lanes with the same independent institutional strategies.',
 'Variant':name,'Change':'Only Maker lane count 20 -> original 10. Same 60 Makers, same quotes sizes, funding, refresh clocks, inventory limits, and new trader role profiles.',
 'Selection':'Completed development evidence only. Separate validation untouched; spread threshold and all other gates unchanged.'},indent=2))
print('Frozen',name)
