from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;arms={'rolling-portfolio':'last-reserve-inner','rolling-patient':'inner-patient-stretch'}
for name,parent in arms.items():
 files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 s=files['MarketConfig.luau'];version='3'if 'patient'in name else'2';needle='BotDiversity = {Version='+version+',';assert needle in s
 files['MarketConfig.luau']=s.replace(needle,'BotDiversity = {Version=4,RollingPortfolio={ReviewSeconds={30,90},ChangeFraction={.15,.35},EpisodeSeconds={600,1200}},')
 s=files['BotDiversity.luau'];needle='s.ReadyAt=e.Time+range(s,c.StartDelay);s.Recoveries=e.Accounts[a.Id].ParticipationRecoveries or 0';assert needle in s
 s=s.replace(needle,needle+'''
 if s.Style=='Portfolio'and c.RollingPortfolio then
  s.ReviewPeriod=range(s,c.RollingPortfolio.ReviewSeconds);s.TargetChange=range(s,c.RollingPortfolio.ChangeFraction)
  s.EpisodeLifetime=range(s,c.RollingPortfolio.EpisodeSeconds)
 end''')
 needle="s.ReadyAt=e.Time+s.Pause*range(s,stopped and c.StopCooldownMultiple or {.75,1.25})";assert needle in s
 s=s.replace(needle,needle+'\n s.EpisodeUntil=nil;s.ReviewAt=nil')
 needle='function D.Step(p,a)';assert needle in s
 s=s.replace(needle,(R/'RollingAllocator.luau').read_text(encoding='utf8')+'\n'+needle)
 needle="if s.PositionId and(not pos or pos.Id~=s.PositionId)then pause(e,a,s,c,true);return end";assert needle in s
 s=s.replace(needle,needle+"\n if s.Style=='Portfolio'and c.RollingPortfolio then D.Allocate(p,a,s);return end")
 files['BotDiversity.luau']=s
 d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']+=list(arms);plan['Rounds'].append('round13-plan.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round13-plan.json').write_text(json.dumps({'Basis':'Patient Stretch plus nearest-lane bridge passes all numerical gates (149 counter events,38 strict pullbacks), but current BX chart has a quiet middle and a late jump. Reject by chart review. Portfolio and countertrend time exits create inventory cycles; longer Portfolio cycles restored movement but produced a 41-minute leg.',
 'Variants':arms,'Change':'Existing Portfolio accounts instead review a bounded private inventory allocation every 30-90 seconds, with independent jitter. Each review moves the existing target by 15-35% of the same funded capacity. They can add or trim existing holdings without forced zero inventory at each review. Opposite objectives close first and cool down; maximum episode 600-1200 seconds then mandatory bounded reduction. All real stops, manual protections, child caps, risk limits and IOC execution remain.',
 'Ablation':'Rolling allocations with original versus patient Stretch policy, same neighboring Maker lane. No new accounts or capital and no public/hidden future price targets.',
 'Selection':'Complete six-case development and comparable actual OHLC review. Frozen before testing. Holdouts still ungenerated and gates unchanged.'},indent=2))
print('Frozen',list(arms))
