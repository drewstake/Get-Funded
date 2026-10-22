from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
variants={'portfolio-dense':'portfolio','mixed-wide-dense':'mixed-wide'}
for name,parent in variants.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 c=files['MarketConfig.luau'];assert c.count('MakerLanes = {Count=20,')==1
 files['MarketConfig.luau']=c.replace('MakerLanes = {Count=20,','MakerLanes = {Count=10,')
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(variants);plan['Rounds'].append('round4-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round4-plan.json').write_text(json.dumps({'Basis':'All six portfolio cases pass numerical development gates but chart review shows quiet stretches and abrupt jumps. All six mixed-wide cases pass every numerical gate except spread. Test restoring the original 10 Maker lanes (six Makers per lane), now that independent demand replaces the removed inventory-price feedback.',
 'Variants':variants,'Change':'Only lane count 20 -> original 10; same 60 Makers, same finite capital, quote sizes, refresh clocks, risk, and all trader behaviors.',
 'Selection':'Completed development only; no holdouts opened; thresholds unchanged.'},indent=2))
print('Frozen',list(variants))
