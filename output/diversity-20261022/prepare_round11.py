from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;parent='last-reserve-inner';name='inner-multihorizon'
files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
s=files['MarketConfig.luau'];needle='BotDiversity = {Version=2,ReserveMode="Mixed",';assert needle in s
files['MarketConfig.luau']=s.replace(needle,'BotDiversity = {Version=3,ReserveMode="Mixed",PortfolioClockScales={.5,1,3},')
s=files['BotDiversity.luau'];needle='s.ReadyAt=e.Time+range(s,c.StartDelay);s.Recoveries=e.Accounts[a.Id].ParticipationRecoveries or 0';assert needle in s
files['BotDiversity.luau']=s.replace(needle,needle+'''
 if s.Style=='Portfolio'and c.PortfolioClockScales then
  -- Different mandate horizons use each account's own persistent RNG and clocks.
  s.ClockCohort=math.min(#c.PortfolioClockScales,math.floor(random(s)*#c.PortfolioClockScales)+1)
  s.ClockScale=c.PortfolioClockScales[s.ClockCohort]
  s.Build*=s.ClockScale;s.Hold*=s.ClockScale;s.Pause*=s.ClockScale
 end''')
d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
for f,s in files.items():
 (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
 original=old.read_text(encoding='utf8')if old.exists()else''
 patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
(d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates'].append(name);plan['Rounds'].append('round11-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round11-plan.json').write_text(json.dumps({'Basis':'Nearest-lane bridge passes all aggregate gates but CurrentBX minute RV .357% fails the fixed .430% floor. Its current chart still has a prolonged small-motion section. Reassignment traces show portfolio mandates mostly time-limited; all currently share one 70-240 second hold range.',
 'Variant':name,'Change':'Portfolio accounts independently select short (.5x), existing (1x) or longer (3x) build/hold/cooldown durations from private saved RNG. Hold range is now 35-720 seconds across cohorts. Start delays remain private and unchanged. Stretch accounts, signal thresholds, maximum target, child size, execution cap and funding remain unchanged.',
 'Hypothesis':'Overlapping inventory demand on distinct horizons preserves finite persistent movement without a shared directional clock or direct price control. Longer builds may fill larger portions of the existing funded objective, so funding/endurance must be rechecked.',
 'Selection':'Same six development cases and unchanged gates/chart review. No independent validation data has been generated or read.'},indent=2))
print('Frozen',name)
