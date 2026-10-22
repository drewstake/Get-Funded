from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;parent='last-reserve-diverse'
names=['last-reserve-withdraw','last-reserve-faders']
for name in names:
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 c=files['MarketConfig.luau'];mode='Withdraw'if name.endswith('withdraw')else'Faders';assert c.count('ReserveMode="Mixed"')==1
 files['MarketConfig.luau']=c.replace('ReserveMode="Mixed"','ReserveMode="'+mode+'"')
 if mode=='Faders':
  s=files['BotDiversity.luau'];needle="s.Style=assigned and style or a.Kind=='Reversion'and 'Stretch'or 'Portfolio'";assert needle in s
  files['BotDiversity.luau']=s.replace(needle,"s.Style=assigned and(c.ReserveMode=='Faders'and 'Stretch'or style)or a.Kind=='Reversion'and 'Stretch'or 'Portfolio'")
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=names;plan['Rounds'].append('round8-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round8-plan.json').write_text(json.dumps({'Basis':'Mixed institutional cohort creates many strict pullbacks but misses spread. More maker depth and requested spread cap did not qualify. CurrentBX traces show Reserve portfolio incoming 1513 opening/1540 closing contracts, Stretch 1350/1225, all Stretch closes timed. Separate the contribution of removed passive supply from new flows, then replace the three institution portfolio mandates with price-sensitive independent stretch mandates.',
 'Variants':{names[0]:'Same six reassigned Reserve accounts settle inherited positions then withdraw. No new flow; causal supply ablation in the same last-price-centered book.',names[1]:'Same six reassigned Reserve accounts all use independent Stretch profiles instead of three Stretch/three Portfolio. Existing Value Portfolio accounts unchanged.'},
 'Fixed':'All six development worlds, original gates, maker policy and funded quantities. No new funding or account limits. Independent clocks/horizons/private RNG. No validation consumption.'},indent=2))
print('Frozen',names)
