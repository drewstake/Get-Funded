"""Summarize reproducible probes and experiments, without editing game sources."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from collections import Counter
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'output/bot-diagnostics-20261018'
SEEDS = (73521, 5501, 4407)

def read(name):
    return json.loads((OUT / name).read_text())

def compact(d):
    gates = Counter()
    for values in d['Gates'].values():
        gates.update(values)
    return {
        'Seed': d['Seed'], 'Variant': d['Variant'], 'Seconds': d['Seconds'],
        'Groups': {kind: {field: g[field] for field in (
            'DeltaPnl', 'Submits', 'Rejected', 'Closes', 'Reasons', 'StopMovedAway',
            'StopMovedCloser', 'StopSlipDollars', 'StopContracts', 'NoContractCapital',
        )} for kind, g in d['Groups'].items() if kind in ('Reversion', 'Protective', 'Scalper')},
        'ScalperGates': dict(gates),
        'MinimumMoveBlockedPercent': 100 * gates['MinMove'] / gates['Decisions'],
        'AllScalpersFlatPercent': 100 * d['Samples']['AllScalpersFlat'] / d['Samples']['Count'],
        'Markets': {key: {
            'AverageSpreadTicks': m['Spread'] / m['TwoSided'],
            'Average64ExecutionRangeTicks': m['RecentRange'] / m['Samples'],
        } for key, m in d['Samples']['Markets'].items()},
        'Audit': d['Audit'],
    }

baseline = [compact(read(f'baseline-{seed}-7200.json')) for seed in SEEDS]
fresh = [compact(read(f'current_fair-{seed}-7200.json')) for seed in SEEDS]
manifest = read('source-manifest.json')
changed = [name for name, digest in manifest.items()
           if hashlib.sha256((source_file(ROOT, name)).read_text(encoding='utf-8-sig').encode()).hexdigest() != digest]
assert not changed, f'Source changed during investigation: {changed}'
comparison = {}
for kind in ('Protective', 'Reversion'):
    comparison[kind] = {
        'BaselinePnlBySeed': [round(d['Groups'][kind]['DeltaPnl'], 2) for d in baseline],
        'CurrentFairPnlBySeed': [round(d['Groups'][kind]['DeltaPnl'], 2) for d in fresh],
        'BaselineMeanPnl': sum(d['Groups'][kind]['DeltaPnl'] for d in baseline) / len(baseline),
        'CurrentFairMeanPnl': sum(d['Groups'][kind]['DeltaPnl'] for d in fresh) / len(fresh),
    }
report = {
    'Scope': 'Current workspace source, three seeds, two simulated hours per fresh run; no connected Roblox Studio session. Not a replay of the pasted live report.',
    'ProductionSourcesUnchanged': True,
    'Findings': {
        'Scalper': 'Entry filter compares a several-tick movement threshold to only 8-35 recent executions. Gate, not capital or order rejection, dominates in these runs. All scalpers being flat is common even though entries and closes do occur.',
        'Protective': 'Slow belief update lags fair-value trends. Edge uses this stale belief, producing countertrend entries even when trade price equals current fair value. Stops do not make that signal profitable.',
        'Reversion': 'Shares the lagging belief and explicitly opposes recent momentum; has no trend/regime condition requiring a genuine deviation from current fair value or evidence of reversal.',
        'AdditionalRisk': 'Bots may repeatedly add to positions and move stops away as average entry changes. Both strategies also enter in neutral conditions because of random signal noise. Neither changing stops alone nor reducing noise alone resolved losses in the exploratory single-seed comparisons.',
    },
    'Comparison': comparison,
    'Baseline': baseline,
    'CurrentFairExperiment': fresh,
    'ExploratorySingleSeed': [compact(read(f'{variant}-73521-7200.json')) for variant in ('lower_noise', 'fixed_stop', 'no_fade')],
    'NeutralAndScalperProbes': read('probes.json'),
    'DirectionalProbes': read('direction-probes.json'),
    'HistoricalStudioContinuation': compact(read('saved-1-1800.json')),
    'Limitations': [
        'Experimental variants only exist in detached harness copies. No live funding, game code, or saved worlds were changed.',
        'Current-fair experiment resets only Protective/Reversion beliefs to current internal fair value before each decision; all ordinary belief-update RNG draws still execute.',
        'Shared-book paths and subsequent RNG consumption diverge after a behavior change. Equal seeds/durations are sensitivity experiments, not a controlled replay of identical trades.',
        'Fresh-population results and a historical Studio checkpoint do not determine the exact historical contribution of each cause to the pasted cumulative P&L.',
        'Synthetic directional probes test decisions, not trading returns. Account/inventory/cash audits passed for completed simulations.',
        'No broker fees exist in these experiments; spread, slippage, position management, and directional exposure still affect P&L.',
    ],
}
(OUT / 'findings.json').write_text(json.dumps(report, indent=2))
print(json.dumps({'Comparison': comparison, 'ScalperRuns': [{k: d[k] for k in ('Seed','MinimumMoveBlockedPercent','AllScalpersFlatPercent','ScalperGates')} for d in baseline], 'ProductionSourcesUnchanged': True}, indent=2))
