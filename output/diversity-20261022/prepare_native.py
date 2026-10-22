from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parent;name=sys.argv[1]
candidate=R/'variants'/name;m=json.loads((candidate/'manifest.json').read_text())
assert all(hashlib.sha256((candidate/n).read_text(encoding='utf8').encode()).hexdigest()==h for n,h in m.items())
bundle={p.relative_to(R/'original').as_posix():p.read_text(encoding='utf8')for p in (R/'original').rglob('*.luau')}
candidate_bundle=dict(bundle)
for n in m:candidate_bundle[('shared/'if n=='MarketConfig.luau'else'server/')+n]=(candidate/n).read_text(encoding='utf8')
if 'BotDiversityTests.luau'not in m:candidate_bundle['server/BotDiversityTests.luau']=(R/'BotDiversityTests.luau').read_text(encoding='utf8')
(R/'native-sources.json').write_text(json.dumps({'Baseline':bundle,'Candidate':candidate_bundle}),encoding='utf8')
(R/'native-plan.json').write_text(json.dumps({'Variant':name,'Hashes':m,'ParityCases':['Seed71','CurrentBX'],'Steps':400,'DetachedOnly':True},indent=2))
(R/'native').mkdir(exist_ok=True)
print('Prepared detached native verification bundle for',name,'without changing Studio')
