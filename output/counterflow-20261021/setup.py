from pathlib import Path
import shutil, json
R=Path(__file__).resolve().parent
P=R.parent/'streaks-20261021'
shutil.copytree(P/'original',R/'original',dirs_exist_ok=True)
for p in (P/'candidate').glob('*.luau'):
    shutil.copy2(p,R/'original'/('shared' if p.stem=='MarketConfig' else 'server')/p.name)
for name in ['LocalLab.luau','ExactJson.luau','MomentumBenchmark.luau','Diagnose.luau','analyze.py','plot_comparison.py','read_diagnostics.py']:
    text=(P/name).read_text(encoding='utf8').replace('streaks-20261021','counterflow-20261021')
    (R/name).write_text(text,encoding='utf8')
for folder in ['snapshots','logs','diagnostics','suites','variants','results-profit','results-profit-patient']:
    (R/folder).mkdir(exist_ok=True)
for name in ['Seed71','Seed7919','Seed104729','Current','Older','Aged','InstalledV2']:
    shutil.copy2(P/'snapshots'/f'normalized-{name}.json',R/'snapshots'/f'normalized-{name}.json')
(R/'experiment.json').write_text(json.dumps({
    'Baseline':'Installed checkpoint28, Momentum2, Maker8, Whale1; verified against Studio',
    'Hypothesis':'Staggered profit-taking and optional price-sensitive builds interrupt trend-following feedback',
    'Development':['Seed71','Seed7919','Seed104729','Latest','Older','Aged'],
    'Validation':['Seed42017','Seed88069','LatestLater','AgedLater'],
    'Gates':{'LongRun8CandleShareRatio':.75,'Directional10WindowRatio':.75,'LongestRunRatio':.8,'PullbackRatio':1.5,'StrictCaseWins':4,'OneSecondRVRatio':1.0,'FifteenSecondMidpointRVRatio':1.0,'OneMinuteRVRatio':.9,'MinuteRangeRatio':.9,'Mean30RangeRatio':.9,'RecoveryRatioMaximum':1.1,'Alternating4Maximum':.08},
    'Safety':'Exact full checkpoint replay, no new native test failures, zero inventory/cash audit, no added funding, finite no-recovery endurance',
    'Selection':'At most two code-frozen development variants; no Studio edits unless a candidate passes development and separate validation. No extension of failed validation.'
},indent=2),encoding='utf8')
print('Prepared isolated counterflow lab')
