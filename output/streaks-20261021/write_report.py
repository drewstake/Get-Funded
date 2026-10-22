from pathlib import Path
import json,difflib,hashlib
from analyze import summarize
R=Path(__file__).resolve().parent
dev=summarize('results-shorter-thinner');hold=summarize('holdout');end=summarize('no-recycling')
g=json.loads((R/'installation-gates.json').read_text(encoding='utf8'));detail=json.loads((R/'details-summary.json').read_text(encoding='utf8'))
def table(d):
 b,c=d['Aggregate']['Baseline'],d['Aggregate']['Candidate']
 rows=[('Mean largest same-color streak (candles)',b['LongestRun'],c['LongestRun']),('Completed pullbacks (total)',b['PullbacksPerMarketHour']*b['MarketHours'],c['PullbacksPerMarketHour']*c['MarketHours']),('One-second realized volatility (%)',b['OneSecondRV'],c['OneSecondRV']),('One-minute close-to-close volatility (%)',b['OneMinuteRV'],c['OneMinuteRV']),('Mean minute high-low range (%)',b['MeanMinuteRangePercent'],c['MeanMinuteRangePercent']),('Mean 30-minute high-low range (%)',b['MeanRange30'],c['MeanRange30']),('Four-candle alternation fraction',b['Alternating4Fraction'],c['Alternating4Fraction']),('Mean 95th-percentile spread (ticks)',b['SpreadP95'],c['SpreadP95']),('Recovery transfers',b['Transfers'],c['Transfers'])]
 return '| Metric | Baseline | Candidate |\n|---|---:|---:|\n'+'\n'.join(f'| {n} | {x:,.4f} | {y:,.4f} |'for n,x,y in rows)
text='''# Candle streak diagnosis and tested correction

**Applied to Get Funded! in Studio after development, independent-world, funding and native-runtime checks passed.** Play was restarted. No publication or RBXL save was performed. The selected policy is checkpoint v28, Momentum v2, Maker quote policy v8 and unchanged Whale v1. News remains disabled.

## Cause supported by code and controlled tests

Momentum is the dominant measured source of the long directional runs. The prior policy combined 60–1,200-second price horizons, 90–240-second builds and positions held for up to 1,800 seconds. Both its breakout traders and most trend followers entered while the same public price trend was continuing. Different horizons did not ensure different entry directions. Existing builds repeatedly crossed the spread against a price history that included their own preceding executions.

The Maker book followed the latest trade, and consumed quotes could return after three simulated seconds. A displaced quote could also be canceled and replaced during the same Maker decision. That made supply follow the directional execution sequence closely. The old order book could absorb counterflow without disrupting the long candle runs. Maker replacement timing is a contributing mechanism, not the sole demonstrated cause.

In the seed-71 execution trace, Momentum opening/building orders contributed 3,636 ticks of candle-direction-aligned movement; Value entries contributed -2,164. In the Current saved-world trace the corresponding figures were +4,259 and -1,750. These are signed sums across three markets, not a claim that ticks equal economic volatility or that this observational attribution alone proves causality. Raw per-minute, per-strategy records are in `diagnostics/`.

The causal probe suppressed only new Momentum entry signals while retaining existing positions, exits, stops, funding and the other strategies. Across three seeds and three saved worlds, the average largest streak fell from 19.94 to 10.94 candles and completed pullbacks rose from 6 to 14. However, one-second volatility fell from 0.297% to 0.180%, and mean 30-minute range fell from 0.558% to 0.189%. Turning Momentum off therefore identified its role but was not an acceptable fix.

Source evidence: `original/server/BotMomentum.luau` (`Signal` and `Step`), `original/server/Participants.luau` (`_maker`), `original/server/OrderFlowMarket.luau` (`Reference`), and `original/shared/MarketConfig.luau`. `MarketEngine:_trade` remains the sole writer of executed last prices.

## Installed behavior

- Momentum retains three independent cohorts, now observing 20–90, 90–240 and 240–600 seconds. Builds last 30–120 seconds. Holding time is one to two times the individual horizon, bounded to 60–900 seconds. Risk fractions, target inventory fractions, margin limits, child-order slippage caps, stops and exit machinery are unchanged.
- Makers display a 0.45 size multiplier instead of 0.9. Their account capital, population and inventory limits are unchanged. Resting and partially filled orders retain existing FIFO rules.
- Filled, expired and repriced Maker slots wait before replacing liquidity. The base delay is 12 simulated seconds, multiplied by a deterministic, identity-derived factor from 0.6 to 1.4. These factors consume no shared RNG and persist in the checkpoint. A smaller displayed lot does not create new inventory or cash.
- Maker policy adoption cancels entry orders only, preserving position-linked/manual reduce-only exits. Restore itself does not execute trades, cancel orders, alter positions or transfer money. New behavior begins on the ordinary scheduled decisions. New Makers still establish their initial opening quotes; the replacement delay applies to subsequent slot replacement.

This is a targeted change to the existing strategies. No new bot type, artificial price adjustment, forced candle color, scheduled reversal or news event was added. The rejected Reversion and inventory-unwind Maker implementations were not installed.

## Comparison design

All 105 live ModuleScripts were checked against the baseline export before testing and against Edit/editor source before installation. The baseline was checkpoint v27 with the already installed Momentum and Whale policies.

Development: seeds 71, 7919 and 104729, plus Current, Older and Aged saved-world checkpoints. Each paired arm starts from the identical checkpoint, adapts for 20 simulated minutes, and then measures 60 minutes in BX, BT and BG. Fresh-seed snapshots include 30 minutes of baseline warmup. This provides 18 market-hours per version.

Independent validation: seeds 907 and 65537, plus CurrentLater and OlderLater. The latter are previously unexamined continuations of saved worlds, evolved another 30 minutes using baseline code; they share ancestry with development worlds and are not independent random seeds. These four cases provide another 12 market-hours per version. The moderate 0.45 quote-size candidate was frozen before these comparisons; it was not retuned on their results.

Nine active-policy variants were explored in development, plus the Momentum-entry ablation. Most reduced volatility too much. More aggressive Whale execution lengthened streaks. The stronger 0.25 Maker-size variant showed larger development improvements, but was not selected for installation: the moderate version was chosen before holdout results to retain more displayed depth and avoid its observed fresh-seed quote gaps. Unselected source and results remain in `variants/` and `results-*`.

The original screening plan included a no-decrease rule for 30-minute range. That rule was stricter than the user's explicit instruction to treat range as a tuning target. It was transparently revised before holdout comparisons to report range as a tradeoff; the streak, pullback, short-term volatility, funding and safeguard gates remained. The change is recorded in `experiment.json`.

## Development results

'''+table(dev)+'''

Completed pullbacks increased in four of six cases and tied in the other two. Individual market traces can still regress; aggregate improvement does not guarantee every chart will improve.

## Independent validation results

'''+table(hold)+'''

Completed pullbacks increased in three of four validation cases and tied in the fourth. Candle sign-flip frequency increased from 9.9% to 24.2%, while four-candle alternating patterns remained only 2.5% of windows. This was not a forced red/green alternation.

The mean 30-minute range remains below the preferred 0.7–1.5% target. Target coverage was 4 of 24 validation windows, versus 8 of 24 baseline windows. One-minute close-to-close volatility was essentially unchanged in validation and slightly lower in development. The improvement is in shorter-term movement, wicks and interruptions within trends, not larger uninterrupted directional excursions. The CurrentLater BX trace still has a 22-candle run; this update reduces the problem rather than eliminating long trends.

## Check that volatility is not just spread bounce

The validation run was repeated with additional instrumentation on seed 907 and CurrentLater. Executions, candles, accounts and terminal audits matched the original validation results exactly. No economic behavior was changed by this instrumentation.

| Sampling measure | Baseline | Candidate |
|---|---:|---:|
'''
for key,label in [('OneSecondRV','Executed prices, 1 second'),('OneSecondMidpointRV','Executable quote midpoint, 1 second'),('FifteenSecondRV','Executed prices, 15 seconds'),('FifteenSecondMidpointRV','Executable quote midpoint, 15 seconds')]:
 text+=f"| {label} | {detail['Aggregate']['Baseline'][key]:.4f}% | {detail['Aggregate']['Candidate'][key]:.4f}% |\n"
text+='''
The aggregate 15-second executed-price and midpoint increases were approximately 25% and 24%. Spreads do widen somewhat, but the measured increase is not solely alternating trades between an unchanged bid and ask. The two-case diagnostic is not a separate large-sample performance claim.

## Funding and safeguards

The independent comparison used about 28% less recovery funding than baseline. No capital, leverage, recovery entitlement or risk allowance was increased. Maker losses excluding transfers declined in both development and validation. Whale P&L became negative in validation (about -285,625 versus +2,617,533 baseline), but all 144 repeated Whale observations remained above their risk floor, with no Whale recoveries. This tradeoff is retained in the result files rather than hidden behind aggregate profit.

An additional 20-minute adaptation plus 90-minute measurement on seed 907 and CurrentLater disabled only the isolated lab's recovery-transfer operation. Margin, risk pauses, liquidation, protections and matching remained active. All 1,170 agents in each run retained positive equity, zero recovery transfers occurred, and matched volume remained positive in every 30-minute block in all three markets. Maker losses across the two runs were about 1.20 million versus 1.98 million baseline, and 351 of 360 repeated Maker observations ended above their risk floor versus 346 baseline. This demonstrates finite funded operation over the test interval, not indefinite profitability.

The native Studio suite passed 251 checks versus 246 baseline, with the same 38 existing failures (37 TradeLimitsTests fixtures and one SecurityTests fixture) and no new failure or suite crash. Five new cases cover Maker replacement clocks, profile diversity, manual exits/stop removal, economic read-only migration and exact replay with pending replacements. One existing Momentum fixture was corrected to check its actual time budget: faster build profiles can have several contracts due in the first bucket, so repeated calls are bounded by that budget rather than assuming exactly one contract. Production Momentum execution code was unchanged.

Every completed benchmark and endurance run passed accounting and zero-net-inventory audits, serialized its terminal state and matched the complete restored state after another 80 steps. Native Studio and local Luau matched the entire candidate state after 400 steps, with trade hash 1134040309. Only empty JSON object/array representation is normalized; numerical state is exact. Checkpoint and policy downgrades fail closed.

Two 120-second saved-world transition probes retained both sides of the book throughout. Maximum observed spread during transition was 10 and 14 ticks versus 5 and 11 baseline. Existing player execution collars and all price protections were unchanged.

## Installation and reproducibility

Ten modules were updated: three production/config modules (`Participants`, `MarketConfig`, `WorldCheckpoint`) and seven test modules. All 105 Edit sources and editor buffers were checked before mutation; installed sources were read back. `pre-apply/` contains backups, and Studio change-history waypoints bracket the edit. Play was restarted with the tested policies. Studio and Live persistence use separate DataStore scopes in `WorldService`.

The complete decision is recorded in `installation-gates.json`; `candidate-manifest.json` records source hashes. `runtime-parity.json`, `suite-comparison.json`, `applied.json`, `live-verification-*.json`, `transition/`, `no-recycling/` and the raw result folders provide the supporting evidence. Temporary detached test modules were removed.

From the workspace root, `python output/streaks-20261021/run_final.py holdout` reruns the frozen validation, and `run_final.py endurance` reruns the funding check. `analyze.py`, `validate_details.py` and `installation_gates.py` compute metrics and gates. The local harness runs the actual exported Luau exchange with exact JSON decoding; it does not generate substitute price paths.

Largest streak uses one-minute candle body color, with dojis breaking a streak. A completed pullback requires a prior three-minute move of at least four ticks, a retracement of at least two ticks or 15% of that move, and recovery within eight minutes; events do not overlap. Volatility is square-root summed squared log returns over the measured hour, not an annualized estimate. Full definitions are in `analyze.py` and `MomentumBenchmark.luau`.

All seed and saved-world candle pairs are shown, using actual matched-order OHLC and a shared vertical scale within each pair:

'''
for label,name in [('Development BX','results-shorter-thinner-BX.png'),('Independent validation BX','holdout-BX.png'),('Independent validation BT','holdout-BT.png'),('Independent validation BG','holdout-BG.png')]:text+=f'[{label}](<{(R/name).as_posix()}>)\n\n'
(R/'RESULTS.md').write_text(text,encoding='utf8')
patch=[]
for f in sorted((R/'candidate').glob('*.luau')):
 original=R/'original'/('shared'if f.stem=='MarketConfig'else'server')/f.name
 patch.extend(difflib.unified_diff(original.read_text(encoding='utf8').splitlines(True),f.read_text(encoding='utf8').splitlines(True),fromfile='original/'+f.name,tofile='candidate/'+f.name))
(R/'streak-correction.patch').write_text(''.join(patch),encoding='utf8')
print('Report and patch written')
