"""Summarize the frozen V21 bot fix; later pricing changes need new validation."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
out = root / 'output/bot-fairness-20261019'
pairs = []
for seed, seconds in [(19381, 7200), (68473, 7200), (91753, 21600)]:
    comparison = {'Seed': seed, 'Seconds': seconds}
    for variant in ['baseline', 'final']:
        run = json.loads((out / f'{variant}-{seed}-{seconds}.json').read_text())
        comparison[variant] = {key: run[key] for key in ['Groups', 'TwoSidedFraction', 'Audit']}
    pairs.append(comparison)

report = {
    'Scope': 'Frozen V21 liquidity controls and public-information bot changes; not the subsequent V22 order-driven pricing change.',
    'Installed': False,
    'Findings': [
        'Liquidity randomly took liquidity and accumulated inventory with sparse protective stops.',
        'Reversal and value signals accessed hidden generator fair value unavailable to players.',
        'Maker quotes were last-price dominated, could cross, and remained stale during adverse moves.',
        'Bot scale-ins could widen an existing stop.',
        'Original bot accounting reconciled; historical capital ledger changes were not trading losses.',
    ],
    'Changes': [
        'Liquidity uses public executable midpoint, passive one-contract entries, no additions while holding, reduce-only exits and bounded quote lifetime.',
        'Liquidity gets stop protection and stops new exposure at 25% equity drawdown; existing triggered exits remain active. This is a risk control, not a guaranteed loss ceiling.',
        'Trading bots use public prices, history and executable depth; only Maker and Reserve retain internal fair value.',
        'Maker quotes use internal fair value with passive constraints and timely adverse repricing.',
        'Bot scale-ins cannot loosen stops. Saved-world migration preserves balances, positions and past losses.',
    ],
    'Validation': {
        'Offline': {'Passed': 149, 'Failures': 0, 'Report': 'tests-final.json'},
        'DetachedStudio': {'Passed': 55, 'Failures': 0, 'Report': 'studio-final-tests.json'},
        'SimulationCaveat': 'Simulations use the final trading logic, but began before the policy metadata bump from 1 to 2 and the paused protective-exit preservation correction. Regression tests cover both changes, including identical fresh-trade behavior for policy versions; no liquidity bot reached the pause threshold in these runs.',
        'Limitations': 'Three deterministic fresh-world scenarios are regression evidence, not a profitability guarantee or a replay of the original multi-day world. Liquidity and Reversion still lose money in these scenarios. Later V22 changes require new simulations.',
    },
    'Comparisons': pairs,
    'ReleaseManifest': 'release-manifest.json',
    'DeploymentOwner': 'Explain market surges and bot impact (01a152ca-11cd-7380-99aa-486135884e70); combine with newer V22 work before deployment.',
}
assert all(p['final']['Groups']['Liquidity']['Paused'] == 0 for p in pairs)
(out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
for p in pairs:
    print(p['Seed'], p['Seconds'], json.dumps({v: {
        'LiquidityPnl': p[v]['Groups']['Liquidity']['Pnl'],
        'WorstLiquidityReturn': p[v]['Groups']['Liquidity']['MinReturn'],
        'ScalperWinners': p[v]['Groups']['Scalper']['Positive'],
        'ReversionWinners': p[v]['Groups']['Reversion']['Positive'],
        'LiquidityDepleted': p[v]['Groups']['Liquidity']['Depleted'],
    } for v in ['baseline', 'final']}))
