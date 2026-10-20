import collections
import datetime
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / 'output' / 'bot-investigation-20261014'
read = lambda name: json.loads((out / name).read_text())
live = read('live-evidence.json')
baseline = [read(f'baseline-{seed}-21600.json') for seed in (73521, 5501, 4407)]
value_comparisons = []
hold_comparisons = []
for run in baseline:
    seed = run['Seed']
    two_hours = next(row['Pnl'] for row in run['Market']['Series'] if row['Time'] == 7200)
    value = read(f'value_fast-{seed}-7200.json')
    hold = read(f'scalper_longer-{seed}-7200.json')
    value_comparisons.append({'Seed': seed, 'BaselinePnl': two_hours['Value'], 'CurrentFairEstimatePnl': value['Groups']['Value']['Pnl']})
    keys = ['Scalper/Momentum', 'Scalper/Reversion']
    before = sum(two_hours[key] for key in keys)
    after = sum(hold['Groups'][key]['Pnl'] for key in keys)
    hold_comparisons.append({'Seed': seed, 'BaselinePnl': before, 'FourTimesHoldPnl': after, 'LossReductionPercent': 100 * (after - before) / -before})

aggregates = {}
for run in baseline:
    for name, data in run['Groups'].items():
        group = aggregates.setdefault(name, {'PnlBySeed': {}, 'Closes': 0, 'Reasons': {}, 'FillContracts': 0, 'TakerContracts': 0, 'Markout30': 0, 'MarkoutVolume': 0, 'TakerMarkout30': 0, 'TakerMarkoutVolume': 0, 'PassiveMarkout30': 0, 'PassiveMarkoutVolume': 0})
        group['PnlBySeed'][str(run['Seed'])] = data['Pnl']
        for field in ['Closes', 'FillContracts', 'TakerContracts', 'Markout30', 'MarkoutVolume', 'TakerMarkout30', 'TakerMarkoutVolume', 'PassiveMarkout30', 'PassiveMarkoutVolume']:
            group[field] += data[field]
        for reason, values in data['Reasons'].items():
            target = group['Reasons'].setdefault(reason, {'Count': 0, 'Pnl': 0})
            target['Count'] += values['Count']
            target['Pnl'] += values['Pnl']
for group in aggregates.values():
    for kind in ['', 'Taker', 'Passive']:
        group[kind + 'Mean30SecondMarkoutPerContract'] = group[kind + 'Markout30'] / max(1, group[kind + 'MarkoutVolume'])

live_groups = read('live-summary.json')['Groups']
style_groups = {}
for bot in live['Bots']:
    if bot['Kind'] == 'Scalper':
        group = style_groups.setdefault(bot['Style'], {'Count': 0, 'Pnl': 0, 'Equity': 0, 'CannotTradeConfiguredSize': 0})
        group['Count'] += 1
        group['Pnl'] += bot['Realized'] + bot['Unrealized']
        group['Equity'] += bot['Equity']
        group['CannotTradeConfiguredSize'] += bot['CapacityFlat'] < bot['Size']

result = {
    'ProductionSnapshotUTC': datetime.datetime.fromtimestamp(live['SavedAt'], datetime.timezone.utc).isoformat(),
    'SnapshotAgeAtReadSeconds': live['ReadAt'] - live['SavedAt'],
    'ProductionStore': {'Name': 'MarketReign_Continuous_v1', 'Scope': 'Live', 'Key': 'primary-exchange'},
    'LiveGroupSummary': live_groups,
    'LiveScalperStyles': style_groups,
    'LiveCapacityProbes': read('capacity-probes.json'),
    'NoTrendDecisionProbes': read('decision-probes.json'),
    'BaselineMethod': 'Three fresh isolated active-market simulations, six simulated hours each. Saved Live config; current local strategy/matching source; no humans or legacy markets. Not a historical replay of production.',
    'BaselineGroups': aggregates,
    'ValueEstimateComparisons': value_comparisons,
    'ScalperHoldComparisons': hold_comparisons,
    'CounterfactualLimitations': 'Same seed and starting population per comparison. Changing a strategy changes subsequent order flow and random draw scheduling, so these are whole-market counterfactuals, not identical price paths. Three seeds are diagnostic evidence, not production readiness.',
    'Provenance': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / 'tmp' / 'bot-investigation' / 'modules').glob('*.luau')},
    'AuditResults': [{'Seed': run['Seed'], 'Variant': run['Variant'], 'Audit': run['Audit']} for run in baseline] + [{'Seed': seed, 'Variant': variant, 'Audit': read(f'{variant}-{seed}-7200.json')['Audit']} for seed in (73521,5501,4407) for variant in ('value_fast','scalper_longer')],
    'Findings': [
        {'Status': 'Confirmed by direct engine capacity probes', 'Finding': '145 flat bots with positive cash cannot fund one contract. Another 14 flat scalpers can fund one contract but always request two. None of the 145 is Locked.'},
        {'Status': 'Confirmed in controlled decision probes', 'Finding': 'Without a trend, inventory or fair-value gap, generic traders still submit on about 61 percent of eligible decisions and scalpers on 84 percent.'},
        {'Status': 'Supported by three counterfactual seeds', 'Finding': 'Refreshing Value belief to current simulator fair value before each decision changes two-hour losses to profits in all three seeds.'},
        {'Status': 'Measured in three six-hour baselines', 'Finding': 'Scalpers close mostly on holding-time expiry. Timed exits have negative total realized Pnl in every seed and style.'},
        {'Status': 'Supported by three counterfactual seeds', 'Finding': 'Four times longer scalper holds reduce losses 26.6-35.1 percent over two simulated hours but do not produce profits.'},
        {'Status': 'Confirmed in strategy source', 'Finding': 'Range-bound sets Trend=0 but adds no pull to a fixed anchor. Fair value is smoothed toward a wandering anchor. Reversion does not check for a reverting regime.'},
        {'Status': 'Measured in baselines; mechanism supported by source', 'Finding': 'Resting fills often have negative 30-second markouts. Makers center 83 percent on last price and 17 percent on fair, and retain quotes at least 18 simulated seconds; reserves quote current fair and can reprice after two.'},
        {'Status': 'Observed; historical attribution remains incomplete', 'Finding': 'Production momentum is profitable and makers are depleted in BT, but fresh baseline momentum loses and makers win across all three seeds. Profitability depends on market state; lifetime figures alone do not prove durable strategy advantage.'},
    ],
    'HistoricalLimitations': 'Production checkpoint strips bot History and Fills. No historical exact win rate, exit attribution, counterparty profit transfer, or deployed-code timeline can be recovered from this snapshot. Profits aggregate over different bot ages and prior versions.',
    'LiveMutations': False,
}
(out / 'investigation-summary.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
scalpers = [aggregates[k] for k in ['Scalper/Momentum','Scalper/Reversion']]
closes = sum(g['Closes'] for g in scalpers)
timed = sum(g['Reasons']['Timed exit']['Count'] for g in scalpers)
print(json.dumps({'ValueComparisons': value_comparisons, 'HoldComparisons': hold_comparisons, 'ScalperCloses': closes, 'TimedCloses': timed, 'TimedPercent': timed / closes * 100, 'TimedPnl': sum(g['Reasons']['Timed exit']['Pnl'] for g in scalpers), 'BaselineMeanMarkouts': {name: g['Mean30SecondMarkoutPerContract'] for name, g in aggregates.items()}, 'Report': str(out / 'investigation-summary.json')}, indent=2))
