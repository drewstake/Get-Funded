from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;parent='last-reserve-diverse';name='last-reserve-inner'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
s=files['Participants.luau'];needle='local offset=lanes and lane*(lanes.SpacingTicks[a.Key]or 1)or 0';assert s.count(needle)==1
files['Participants.luau']=s.replace(needle,needle+'\n -- One neighboring funded lane bridges depletion; retain the rest of the existing depth ladder.\n if lane==1 then offset=math.max(1,math.round(offset/3))end')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round10-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round10-plan.json').write_text(json.dumps({'Basis':'All-lane compaction fixes spread (4.833 ticks) but sacrifices range/current BX movement. All institutional faders fix spread too but leave longer legs than mixed demand. Retain the strongest mixed demand and distant supply, moving only the first neighboring lane.',
 'Variant':name,'Change':'Only lane index 1 offset divided by three (6->2 BX/BG,18->6 BT). Every other lane, quantity, funding allowance, three-per-lane count, and withdrawal/refill clock remains unchanged.',
 'Hypothesis':'Bridge the immediate depletion gap with three existing independent funded makers per market, without moving all sixty makers closer or increasing best-lane count.',
 'Selection':'Original development gates, untouched reserved validation, and actual candle review.'},indent=2))
print('Frozen',name)
