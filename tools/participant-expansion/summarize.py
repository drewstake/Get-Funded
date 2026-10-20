"""Summarize the final verified release; exclude private saved-account contents."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/participant-expansion-20261019'
def read(name):
    return json.loads((OUT / name).read_text())

offline = read('tests-final.json')
native = read('studio-release-validation.json')
benchmark = read('benchmark-release.json')
assert offline['Failures'] == 0 and native['Success'] and native['Failures'] == 0
assert benchmark['Success'] and len(benchmark['Runs']) == 2
release = read('release.json')
for path, item in release.items():
    source = (ROOT / item['File']).read_text(encoding='utf-8-sig')
    assert hashlib.sha256(source.replace('\r\n', '\n').encode()).hexdigest() == item['Hash'], path

baseline = read('benchmark-interim.json')['Runs'][0]
comparison = []
for run in benchmark['Runs']:
    assert run['Participants'] == 1170 and run['Seconds'] == 3600 and run['Depleted'] == 0
    for market in run['Markets'].values():
        assert market['TwoSidedFraction'] == 1
    comparison.append({
        'Seed': run['Seed'], 'Seconds': run['Seconds'], 'Trades': run['Trades'],
        'MeanStepMs': run['MeanStepMs'], 'P95StepMs': run['P95StepMs'],
        'Depleted': run['Depleted'], 'LiquidityPaused': run['LiquidityPaused'],
        'RawBytes': run['RawBytes'], 'StoredBytesWithHeadroom': run['StoredBytesWithHeadroom'],
        'Markets': run['Markets'], 'Audit': run['Audit'],
    })

summary = {
    'CheckpointVersion': 23, 'PopulationPolicyVersion': 2,
    'PerMarketBefore': 130, 'PerMarketAfter': 390, 'TotalAfter': 1170,
    'CountsPerMarket': {'Maker':60,'Liquidity':72,'Momentum':36,'Value':60,'Reversion':36,
                       'Protective':24,'Scalper':72,'Whale':12,'Reserve':18},
    'ExistingBotFundingReset': False, 'AddedBotsOnCompleteV1World': 780,
    'OfflineChecks': offline['Total'], 'NativeChecks': native['Total'],
    'SavedWorld': native['SavedWorld'], 'Runs': comparison,
    'BaselineMeanStepMs': baseline['MeanStepMs'],
    'FirstSeedDepthRatios': {key:
        (benchmark['Runs'][0]['Markets'][key]['TopFiveBid'] + benchmark['Runs'][0]['Markets'][key]['TopFiveAsk']) /
        (market['TopFiveBid'] + market['TopFiveAsk']) for key, market in baseline['Markets'].items()},
    'Sources': {path: item['Hash'] for path,item in release.items()},
    'Published': False, 'RBXLSaved': False, 'DataStoreWrites': False,
}
if (OUT/'installed.json').exists():
    installed = read('installed.json')
    assert installed['Installed'] == summary['Sources']
    summary['InstalledSources'] = installed['Count']
(OUT/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps({k:summary[k] for k in ['TotalAfter','OfflineChecks','NativeChecks','FirstSeedDepthRatios']},indent=2))
