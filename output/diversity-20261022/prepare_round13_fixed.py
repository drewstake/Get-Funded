from pathlib import Path
import json,hashlib,difflib
R=Path(__file__).resolve().parent;names=[]
for parent in ['rolling-portfolio','rolling-patient']:
 (R/'variants'/parent/'rejection.json').write_text(json.dumps({'Decision':'Aborted implementation error; do not evaluate or promote','Reason':'Rolling initialization overwrote an inherited Reserve reducing phase. Found by code review before benchmark completion; root process and child Lune jobs stopped. Preserve source manifest and partial evidence.','ValidationConsumed':False},indent=2))
 name=parent+'-safe';names.append(name);files={p.name:p.read_text(encoding='utf8')for p in (R/'variants'/parent).glob('*.luau')}
 s=files['BotDiversity.luau'];needle="s.Target=inventory;s.Phase='Allocating';s.EpisodeUntil=e.Time+s.EpisodeLifetime;s.ReviewAt=e.Time+s.ReviewPeriod";assert s.count(needle)==1
 s=s.replace(needle,"if s.Phase~='Reducing'then s.Target=inventory;s.Phase='Allocating'end\n  s.EpisodeUntil=e.Time+s.EpisodeLifetime;s.ReviewAt=e.Time+s.ReviewPeriod")
 s=s.replace("if s.Style=='Portfolio'and c.RollingPortfolio then D.Allocate(p,a,s);return end","if s.Style=='Portfolio'and c.RollingPortfolio and not(a.Kind=='Reserve'and c.ReserveMode=='Withdraw')then D.Allocate(p,a,s);return end")
 files['BotDiversity.luau']=s;d=R/'variants'/name;d.mkdir(exist_ok=False);patch=[]
 for f,s in files.items():
  (d/f).write_text(s,encoding='utf8');old=R/'original'/('shared'if f=='MarketConfig.luau'else'server')/f
  original=old.read_text(encoding='utf8')if old.exists()else''
  patch.extend(difflib.unified_diff(original.splitlines(True),s.splitlines(True),fromfile='original/'+f,tofile=name+'/'+f))
 (d/'change.patch').write_text(''.join(patch),encoding='utf8');(d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan=json.loads((R/'experiment.json').read_text());plan['Candidates']=[n for n in plan['Candidates']if n not in ['rolling-portfolio','rolling-patient']]+names;plan['AbortedCandidates']=['rolling-portfolio','rolling-patient'];plan['Rounds'].append('round13-correction.json');(R/'experiment.json').write_text(json.dumps(plan,indent=2))
(R/'round13-correction.json').write_text(json.dumps({'Originals':'rolling-portfolio and rolling-patient aborted for implementation error, not tuned market performance','Variants':names,'Correction':'Preserve inherited reducing phases during allocator initialization; withdrawal-only Reserve mode takes precedence. All intent, funding and risk parameters unchanged. Focused tests must pass before benchmarks.','Holdouts':'Untouched'},indent=2));print('Frozen',names)
