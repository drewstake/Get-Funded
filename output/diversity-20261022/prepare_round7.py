from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;name='last-reserve-tight';parent='last-reserve-diverse'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
p=files['Participants.luau'];needle='local spread=math.max(1,math.floor(stress*0.8+b.Volatility*0.2))';assert p.count(needle)==1
files['Participants.luau']=p.replace(needle,needle+'\n if self.Config.MakerMaxHalfSpreadTicks then spread=math.min(spread,self.Config.MakerMaxHalfSpreadTicks)end')
c=files['MarketConfig.luau'];files['MarketConfig.luau']=c.replace(' MakerQuotePolicyVersion = 8,',' MakerQuotePolicyVersion = 8,\n MakerMaxHalfSpreadTicks = 3, -- Bound a maker\'s requested half-spread, not the actual book spread.')
c=files['WorldCheckpoint.luau'];assert c.count('"MakerRepricePause"')==1
files['WorldCheckpoint.luau']=c.replace('"MakerRepricePause"','"MakerRepricePause","MakerMaxHalfSpreadTicks"')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round7-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round7-plan.json').write_text(json.dumps({'Basis':'Last-reserve-diverse passes every development numerical gate except spread. Increasing same-lane maker count to 4 or 6 loses movement/shape. Test the separate volatility-dependent requested spread mechanism.',
 'Variant':name,'Change':'Cap each maker requested half-spread at three ticks; actual funded executable book can still be wider. Same staggered lanes, quote lots, repricing/refill deadlines, accounts and risk. Only legal resting order prices change.',
 'Selection':'Unchanged six-case gates and chart review. Reserved validation untouched. Must inspect funding adverse selection and no-recovery endurance if promising.'},indent=2))
print('Frozen',name)
