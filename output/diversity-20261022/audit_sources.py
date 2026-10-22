from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent;P=R.parent/'microstructure-20261022'
original=list((R/'original').rglob('*.luau'));assert len(original)==105
assert all(p.read_text(encoding='utf8')==(P/'original'/p.relative_to(R/'original')).read_text(encoding='utf8')for p in original)
allowed={'Participants.luau','WorldCheckpoint.luau','MarketConfig.luau','BotWhale.luau','BotDiversity.luau','BotDiversityTests.luau','BotOrderFlowTests.luau','BotParticipationTests.luau','OrderFlowMarketTests.luau','BotWhaleTests.luau','BotSignalsTests.luau','BotRefreshTests.luau','MakerLiquidityTests.luau'}
report={}
for d in sorted((R/'variants').iterdir()):
 m=json.loads((d/'manifest.json').read_text());assert set(m)<=allowed
 assert set(m)=={p.name for p in d.glob('*.luau')}
 assert all(hashlib.sha256((d/n).read_text(encoding='utf8').encode()).hexdigest()==h for n,h in m.items()),d.name
 cp=(d/'WorldCheckpoint.luau').read_text();version=31 if (d/'integration.json').exists()else 30
 assert f'Version={version},Readable={{[{version}]=true,'in cp
 p=(d/'Participants.luau').read_text();assert 'local center=reference-inventory/a.Limit'not in p
 report[d.name]={'Frozen':True,'Files':m,'MakerInventoryQuoteDisplacementRemoved':True,'ExperimentalCheckpoint':version,'NewFunding':False}
(R/'source-scope-audit.json').write_text(json.dumps({'OriginalModules':105,'OriginalsUnchanged':True,'Variants':report},indent=2))
print('Verified original export and',len(report),'frozen strategy variants')
