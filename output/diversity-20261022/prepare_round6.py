from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;name='last-reserve-balanced';parent='last-reserve-diverse'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
c=files['MarketConfig.luau'];assert c.count('MakerLanes = {Count=20,')==1
files['MarketConfig.luau']=c.replace('MakerLanes = {Count=20,','MakerLanes = {Count=15,')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round6-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round6-plan.json').write_text(json.dumps({'Basis':'Completed six-case institutional design at 20 lanes passes all gates except spread (6.389 vs 6.0). Returning to 10 lanes lowers spread to 4.611 but fails aggregate long legs and CurrentBX volatility. Test four Makers per lane (15 lanes) between those measured supply levels.',
 'Variant':name,'Change':'Only lane count 20 -> 15. No extra capital, bot count, quantity or risk changes. Trader profiles and private RNG policies identical.',
 'Selection':'Bracketed development liquidity/impact tradeoff only; gates and untouched holdouts preserved.'},indent=2))
print('Frozen',name)
