from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;arms={'rolling-portfolio-depth':'rolling-portfolio-robust','rolling-patient-depth':'rolling-patient-robust'}
for name,parent in arms.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 s=files['MarketConfig.luau'];assert s.count('MakerLanes = {Count=20,')==1
 files['MarketConfig.luau']=s.replace('MakerLanes = {Count=20,','MakerLanes = {Count=10,')
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
 (d/'integration.json').write_text(json.dumps({'Parent':parent,'Checkpoint':31,'Change':'Only Maker lane count 20 to original 10. All source compatibility, nil-preserving quote selection and focused tests retained. Same sixty funded makers and per-order size, delayed replenishment, risk capacity and allocated capital.'},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(arms);plan['Rounds'].append('round14-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round14-plan.json').write_text(json.dumps({'Basis':'Complete six-case rolling runs increase mean range30 to .824% and1.201% but fail spread (6.944/7.111), quote availability and recovery ($12.319m/$31.472m versus $5.628m baseline). They sustain more inventory and order flow than finite Portfolio mandates. Current BX rolling/patient RV is .742/.881%, with 32.2% low-change intervals instead of the 62.7% in the rejected quiet candidate.',
 'Variants':arms,'Change':'Restore original 10 Maker lanes, six independently funded makers per lane. Keep current individual quote quantities and finite rest/refill delays. Keep the neighboring-lane bridge and every trader policy. No capital, inventory allowance or recovery-policy change.',
 'Hypothesis':'Restored supply can absorb the newly persistent demand and prevent empty-book/stop-walk cascades without losing the movement that prior finite-mandate depth experiments lacked. Patient versus original Stretch remains the isolated comparison.',
 'Selection':'Unchanged full development gates, actual candle coverage review, finite no-recovery endurance, native/migration/parity before any untouched validation.'},indent=2));print('Frozen',list(arms))
