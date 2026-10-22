from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent
arms={'inner-patient-stretch':'last-reserve-inner','diverse-patient-stretch':'last-reserve-diverse'}
for name,parent in arms.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 s=files['MarketConfig.luau'];needle='BotDiversity = {Version=2,ReserveMode="Mixed",';assert needle in s
 files['MarketConfig.luau']=s.replace(needle,'BotDiversity = {Version=3,ReserveMode="Mixed",PatientStretch=true,')
 s=files['BotDiversity.luau'];needle='s.ReadyAt=e.Time+range(s,c.StartDelay);s.Recoveries=e.Accounts[a.Id].ParticipationRecoveries or 0';assert needle in s
 s=s.replace(needle,needle+'''
 if s.Style=='Stretch'and c.PatientStretch then
  -- Countertrend inventory gets time commensurate with its own observed-price horizon.
  s.Build=math.max(s.Build,math.min(120,s.Horizon/2));s.Hold=math.max(s.Hold,s.Horizon)
 end''')
 needle=" if s.Phase=='Waiting'then";assert s.count(needle)==1
 s=s.replace(needle,'''
 if s.Phase=='Building'and s.Style=='Stretch'and c.PatientStretch then
  local signal=D.Signal(p,a,s);local side=s.Target>0 and 1 or -1
  if not signal or signal.Side~=side then
   if pos then s.Phase='Holding'else pause(e,a,s,c,false)end
  end
 end
'''+needle)
 files['BotDiversity.luau']=s
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(arms);plan['Rounds'].append('round12-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round12-plan.json').write_text(json.dumps({'Basis':'Longer independent Portfolio cohorts restore current BX movement (.496% RV), but leave a 41-minute leg and 100% long-leg occupancy; reject. Existing trace shows all institution Stretch closures were timed. Saved profiles expose a timing mismatch: one uses a 403-second signal horizon but stops building after 25 seconds and exits after 83 seconds, often far short of its existing funded target.',
 'Variants':arms,'Change':'Stretch build lasts at least half its private signal horizon, capped at 120 seconds; hold deadline at least that horizon (max420 seconds here). Stop building immediately if public extension no longer supports the fixed direction. Profit exits, original stops, manual protections, caps, target fractions and child sizes remain authoritative. Portfolio durations return to original policy.',
 'Ablation':'The same patient countertrend policy is tested with and without the nearest-Maker-lane bridge. All other input data/policies fixed within each parent comparison.',
 'Selection':'Original six-case development gates and candle review. Separate validation checkpoints remain ungenerated. No grid of durations or random seeds.'},indent=2))
print('Frozen',list(arms))
