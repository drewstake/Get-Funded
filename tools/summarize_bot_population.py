"""Build the comparison and completion evidence from finished local runs."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/bot-population-20261014'
SEEDS=[5501,4407,73521]
def read(name):return json.loads((OUT/name).read_text())
def write(name,value):(OUT/name).write_text(json.dumps(value,indent=2))
def audit(r):
    a=r['Audit']
    assert abs(a['CashError'])<.01 and abs(a['EquityError'])<.01 and all(v==0 for v in a['Inventory'].values())
comparisons=[]
for seed in SEEDS:
    old=read(f'baseline-{seed}-21600.json');new=read(f'proposed-{seed}-21600.json')
    for r in [old,new]:audit(r);assert r['Seconds']==21600
    comparisons.append({'Seed':seed,'Baseline':old,'Proposed':new})
ablations=[]
for seed in SEEDS:
    old=read(f'native-population-only-{seed}-7200.json');new=read(f'native-proposed-{seed}-7200.json')
    for r in [old,new]:audit(r);assert r['Seconds']==7200
    ablations.append({'Seed':seed,'PopulationOnly':old,'WithStrategyFixes':new})
summary={}
for label in ['Baseline','Proposed']:
    runs=[r[label]for r in comparisons]
    groups={}
    for name in runs[0]['Groups']:
        capital=sum(r['Groups'][name]['Capital']for r in runs);pnl=sum(r['Groups'][name]['Pnl']for r in runs)
        groups[name]={'WeightedReturn':pnl/capital,'ReturnsBySeed':[r['Groups'][name]['Return']for r in runs],
                      'PnlsBySeed':[r['Groups'][name]['Pnl']for r in runs]}
    summary[label]={'Groups':groups,'CannotFundOneContractBySeed':[sum(g['NoOneContractCapital']for g in r['Groups'].values())for r in runs],
                    'NoEntryCapacityBySeed':[sum(g['NoEntryCapacity']for g in r['Groups'].values())for r in runs],
                    'Markets':{key:{metric:sum(r['Markets'][key][metric]for r in runs)/len(runs) for metric in
                       ['AverageSpreadTicks','AverageDepth5PerSide','TwoSidedFraction','ProbeFillFraction','ProbeAverageSlippageTicks']}for key in ['BX','BT','BG']},
                    'VolumeBySeed':[r['Audit']['Volume']for r in runs],
                    'ReserveEquityShares':[r['Concentration']['ReserveShare']for r in runs]}
tests=[read('native-all-tests.json')]
assert all(t['Failures']==0 for t in tests)
test_count=sum(len(rows)for t in tests for rows in t['Results'].values())
migration=read('live-migration-dry-run.json');assert migration['SecondRestoreIdentical'] and migration['ActiveBots']==390
benchmark=read('native-live-benchmark.json')
for label in ['Before','After']:audit(benchmark[label])
write('comparison-summary.json',{'Seeds':SEEDS,'HoursPerRun':6,'Runtime':'Lune, normalized isolated copies of current source and preserved baseline',
 'Summary':summary,'StrategyAblation':[{'Seed':r['Seed'],'Groups':{g:{label:r[label]['Groups'][g]for label in ['PopulationOnly','WithStrategyFixes']}for g in ['Value','Scalper']}}for r in ablations],
 'NativeLiveBenchmark':benchmark,'TestCount':test_count,'TestFailures':0,
 'Limits':['Six simulated hours is not long-term solvency evidence. No recurring funding was added.',
  'Fixed seeds and equal durations do not imply identical market paths: decisions consume RNG differently and alter prices.',
  'Raw-book 100-contract probes are hypothetical and omit player execution quotas.',
  'The native benchmark includes saved legacy/player accounts, but not network/UI or new connected-player traffic.']})
unchanged={}
for name in ['MarketEngine','FundedAccounts','PlayerExecution','ProtectiveOrders','TradeProtection','MarketServer.server','TerminalUI','ChartView']:
    before=ROOT/'backups/bot-population-20261014/src'/f'{name}.luau';after=ROOT/'src'/f'{name}.luau'
    unchanged[name]=before.read_bytes()==after.read_bytes()
assert all(unchanged.values()),'Unrelated production code changed since baseline capture'
write('source-manifest.json',{'Files':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in sorted((ROOT/'src').glob('*.luau'))},
                            'PreservedExistingProductionChanges':unchanged})
print(json.dumps({'Tests':test_count,'Failures':0,'Summary':summary,'NativeBenchmark':benchmark},indent=2))
write('completion-audit.json',{
 'Objective':'Implement the bot population, funding, strategy, migration and validation requirements from the user goal file.',
 'Requirements':[
  {'Item':'Inspect baseline and preserve unrelated fixes','Evidence':['baseline-hashes.json','source-manifest.json','native-all-tests.json'],'Result':'Verified'},
  {'Item':'Exact counts/capital; deterministic individual diversity; balanced scalper styles','Evidence':['src/MarketConfig.luau','src/BotPopulation.luau','BotPopulationTests: Exact capital, counts, styles, diversity and reproducibility'],'Result':'Verified'},
  {'Item':'Separate funding from P&L; margin/position sizing and downsizing; finite reserve exposure','Evidence':['BotPopulationTests','live-migration-dry-run.json','src/BotPopulation.luau','src/Participants.luau'],'Result':'Verified'},
  {'Item':'Control aggregate flow; preserve instrument quote differences','Evidence':['src/MarketConfig.luau','DepthRealismTests','comparison-summary.json'],'Result':'Implemented and measured; depth/volume tradeoffs reported'},
  {'Item':'Address value estimate lag and scalper churn without future information or forced profits','Evidence':['src/Participants.luau','BotPopulationTests','comparison-summary.json StrategyAblation'],'Result':'Implemented; controlled three-seed population-held-constant comparisons completed'},
  {'Item':'Versioned saved-state migration, dry run, idempotency, players/legacy/obligations/P&L preserved','Evidence':['live-migration-dry-run.json','BotPopulationTests','src/WorldCheckpoint.luau','tools/DryRunBotPopulation.luau'],'Result':'Verified on detached historical Live snapshot; no production writes'},
  {'Item':'Multiple equal-duration baseline/proposed tests and requested market/account metrics','Evidence':['comparison-summary.json','baseline-*-21600.json','proposed-*-21600.json'],'Result':'Three seeds, six simulated hours each; accounting audits passed'},
  {'Item':'18x benchmark including matching/checkpoint costs and retained legacy population','Evidence':['native-live-benchmark.json'],'Result':'Completed in native Studio using detached saved-world copies; limits documented'},
  {'Item':'Implementation, tests, comparison and deployment/migration plan delivered locally','Evidence':['src/BotPopulation.luau','src/Participants.luau','native-all-tests.json','comparison-summary.json','deployment-plan.json'],'Result':'Complete locally; publication and production migration excluded by user instruction'}
 ],'TestCount':test_count,'TestFailures':0,'NoClaimOfPermanentSolvency':True})
