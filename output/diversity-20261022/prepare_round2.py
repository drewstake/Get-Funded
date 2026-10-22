from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
variants={'midquote':'control','midquote-portfolio':'portfolio','midquote-mixed':'mixed'}
for name,parent in variants.items():
 d=R/'variants'/name;d.mkdir(exist_ok=False)
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 p=files['Participants.luau'];needle=' local center=reference'
 assert p.count(needle)==1
 p=p.replace(needle," -- Public executable midpoint removes the last-print-at-spread-edge recentering term.\n local bid,ask=e:PublicPrices(a.Key)\n local center=bid and ask and (bid+ask)/(2*c.Tick)or reference")
 files['Participants.luau']=p;patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(variants);plan['Rounds'].append('round2-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round2-plan.json').write_text(json.dumps({'Basis':'Initial four completed control/stretch/portfolio cases show that portfolio demand restores CurrentBX movement but still yields smooth segments and jumps. Maker no-skew still recenters new quotes on last execution at the spread edge. Test executable midpoint instead to remove this separate quote recentering term.',
 'SelectionTiming':'Round 1 is still finishing all six cases; this hypothesis uses already completed development cases only, not holdouts.',
 'Variants':{n:'Same as '+p+' except Maker center uses executable public midpoint (last execution fallback only without two-sided quotes)'for n,p in variants.items()},
 'Preserved':'Same inventory-sensitive quantities, finite quote funding, resting/refill clocks, all risk/accounting modules and unchanged gates. No direct price, candle or cash writes.'},indent=2))
print('Frozen',list(variants))
