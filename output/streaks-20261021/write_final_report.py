from pathlib import Path
import json,difflib
from analyze import summarize
R=Path(__file__).resolve().parent
dev=summarize('development-v3');hold=summarize('holdout-v3');end=summarize('no-recycling-v3')
detail=json.loads((R/'details-summary-v3.json').read_text(encoding='utf8'))
def table(d):
 b,c=d['Aggregate']['Baseline'],d['Aggregate']['Candidate']
 rows=[('Average largest candle-color streak',b['LongestRun'],c['LongestRun']),('Completed pullbacks (total)',b['PullbacksPerMarketHour']*b['MarketHours'],c['PullbacksPerMarketHour']*c['MarketHours']),('One-second realized volatility (%)',b['OneSecondRV'],c['OneSecondRV']),('One-minute close-to-close volatility (%)',b['OneMinuteRV'],c['OneMinuteRV']),('Mean minute high-low range (%)',b['MeanMinuteRangePercent'],c['MeanMinuteRangePercent']),('Mean 30-minute range (%)',b['MeanRange30'],c['MeanRange30']),('Four-candle alternating fraction',b['Alternating4Fraction'],c['Alternating4Fraction']),('Mean 95th-percentile spread (ticks)',b['SpreadP95'],c['SpreadP95']),('Recovery transfers',b['Transfers'],c['Transfers'])]
 return '| Metric | Baseline | Final candidate |\n|---|---:|---:|\n'+'\n'.join(f'| {n} | {x:,.4f} | {y:,.4f} |'for n,x,y in rows)
def outcomes(d):
 out=[]
 for case in d['Cases']:
  values={a:sum(x['Pullbacks']for x in d['Markets']if x['Case']==case and x['Arm']==a)for a in ['Baseline','Candidate']}
  out.append(f"{case}: {values['Baseline']} → {values['Candidate']}")
 return '; '.join(out)
b,c=hold['Aggregate']['Baseline'],hold['Aggregate']['Candidate'];eb,ec=end['Aggregate']['Baseline'],end['Aggregate']['Candidate']
def link(label,path):return f'[{label}](<{(R/path).as_posix()}>)'
text=f'''# Candle streak diagnosis and tested correction

**Applied to Get Funded! in Studio after the comparison and safety checks passed.** Final policies: checkpoint v28, Momentum v3, Maker quote policy v8 and unchanged Whale v1. Play was restarted. No publication or RBXL save was performed. News remains disabled.

## What caused the streaks

Momentum is the dominant measured driver. Its old cohorts observed 60–1,200 seconds, built positions for 90–240 seconds and held them for up to 1,800 seconds. Both breakout traders and most trend followers entered while the same public trend was continuing. Their different horizons still produced mostly same-side entry pressure. New fills reinforced the price history used by the next Momentum decision.

Maker quotes followed the latest execution. Consumed quotes could return after three seconds; a displaced quote could be canceled and replaced in the same decision. This replenishing supply followed the directional flow closely. It is a contributing mechanism, not the sole established cause.

Execution attribution on seed 71 found +3,636 candle-direction-aligned ticks from Momentum opening/building orders versus -2,164 from Value entries. The Current world gave +4,259 versus -1,750. These are signed diagnostic sums across three markets, not comparable economic volatility units or causal proof by themselves. Raw traces are in `diagnostics/`.

A controlled probe then blocked only new Momentum entry signals, retaining existing positions, exits, stops, funding and every other strategy. Across three seeds and three saved worlds, average largest streaks fell **19.94 → 10.94 candles**, and completed pullbacks rose **6 → 14**. But short-term volatility fell **0.297% → 0.180%**, and 30-minute range fell **0.558% → 0.189%**. That confirms Momentum's role while showing why disabling it is the wrong fix.

Evidence: {link('original Momentum signal and execution code','original/server/BotMomentum.luau')}, {link('original Maker execution code','original/server/Participants.luau')}, {link('execution-based reference','original/server/OrderFlowMarket.luau')}, and {link('original settings','original/shared/MarketConfig.luau')}. `MarketEngine:_trade` remains the sole writer of executed last prices.

## Final implementation

- Momentum keeps three independent cohorts, now observing 20–90, 90–240 and 240–600 seconds. Builds last 30–120 seconds. Holdings last one to two times the individual's horizon, bounded to 60–900 seconds. Risk fractions, target inventory fractions, margin, slippage, stops and slice/exit execution are unchanged.
- Makers display a 0.45 size multiplier instead of 0.9. Capital, population and inventory limits are unchanged. Existing FIFO/rest rules remain.
- Consumed, expired and repriced Maker slots wait before replacement. A 12-second base delay is multiplied by an identity-derived factor of 0.6–1.4. Factors are deterministic, consume no shared RNG and persist in checkpoints. Initial opening quotes still establish the book; subsequent replacement is delayed.
- Maker adoption withdraws entry intent while preserving manual/position-linked reduce-only exits. Restore itself does not trade, cancel orders, change positions or transfer money.
- Momentum profile initialization corrects only an impossible confirmation window: if confirmation is at least as long as the lookback, it is bounded inside the lookback. Every already-valid profile remains unchanged. This prevents a fast trader from being permanently unable to form a signal.

No bot type, extra capital, artificial price change, forced candle color, news event or scheduled reversal was added. The rejected Reversion and inventory-unwind Maker implementations remain absent.

## Experiment and selection

All 105 live modules were matched to the baseline export. Baseline was checkpoint v27 with the existing Momentum/Whale policies. Each arm starts from the identical checkpoint, adapts for 20 simulated minutes, and measures 60 minutes in BX, BT and BG.

Development: seeds 71, 7919 and 104729 plus Current, Older and Aged worlds, providing 18 market-hours per version. Fresh seeds have 30 minutes of baseline warmup. Validation: seeds 907 and 65537 plus CurrentLater and OlderLater, providing another 12 market-hours per version. Later worlds are baseline continuations of saved worlds by 30 minutes, not independent random seeds.

Nine active-policy designs and a Momentum-entry ablation were explored. Most reduced volatility too much; more urgent Whale execution lengthened streaks. The moderate 0.45 Maker-size design was frozen before the separate validation runs. A stronger 0.25 variant improved development metrics but was not selected because the moderate version retained more displayed depth and avoided its observed fresh-seed quote gaps.

The initial screening plan had a no-decrease rule for 30-minute range. That was stricter than the user's explicit tuning-target constraint, so it was revised before validation to report range as a tradeoff. Other gates remained. The revision is recorded in `experiment.json`; range is never forced.

A post-install profile audit found an impossible fast-trader window. An initially broader correction changed valid profiles and failed the cross-world pullback-majority gate; it was rejected. The final narrow correctness fix was then rerun on all ten paired cases, the funding probes and the native suite. The validation cases were reused for this correctness check, not presented as an additional unseen sample. Rejected outputs are retained under `*-broad-rejected`.

## Final development results

{table(dev)}

Completed pullbacks by case: {outcomes(dev)}.

## Final separate validation results

{table(hold)}

Completed pullbacks by case: {outcomes(hold)}.

The 0.7–1.5% target was reached in **{c['TargetWindows']} of {c['Windows30']}** validation windows versus **{b['TargetWindows']} of {b['Windows30']}** baseline windows. Mean range remains below the preferred target. One-minute close-to-close volatility changed by {(c['OneMinuteRV']/b['OneMinuteRV']-1)*100:+.1f}%; the larger improvement is in shorter-term movement and interruptions within trends. Long runs remain possible: the largest candidate validation streak was {max(x['LongestRun']for x in hold['Markets']if x['Arm']=='Candidate')} candles. This is an improvement, not a guarantee of mixed colors in every interval.

## Volatility beyond bid-ask bounce

Additional instrumentation repeated seed 907 and CurrentLater. Candles, executions, accounts and terminal audits matched the corresponding validation runs exactly.

| Measure | Baseline | Final candidate |
|---|---:|---:|
'''
for f,label in [('OneSecondRV','Executed prices, 1 second'),('OneSecondMidpointRV','Quote midpoint, 1 second'),('FifteenSecondRV','Executed prices, 15 seconds'),('FifteenSecondMidpointRV','Quote midpoint, 15 seconds')]:text+=f"| {label} | {detail['Aggregate']['Baseline'][f]:.4f}% | {detail['Aggregate']['Candidate'][f]:.4f}% |\n"
text+=f'''
Both 15-second executed-price and midpoint volatility increased. Spreads widen somewhat, but the increase is not solely trading back and forth between unchanged quotes. The two-case diagnostic is not a separate large-sample performance claim.

## Funding and safety

Validation used {(1-c['Transfers']/b['Transfers'])*100:.1f}% less recovery funding. No capital, leverage, recovery entitlement or risk allowance increased. Whale equity change excluding transfers was {c['Kinds']['Whale']['EquityChangeExTransfers']:,.0f} versus {b['Kinds']['Whale']['EquityChangeExTransfers']:,.0f} baseline; individual strategy profitability is not assumed.

Seed 907 and CurrentLater also ran for 20 minutes of adaptation plus 90 measured minutes with only the lab's recovery-transfer operation disabled. All risk pauses, margin, liquidation, protection and matching remained active. No recovery transfers occurred; all 1,170 agents in each run retained positive equity, and every 30-minute block in every market had matched volume. Maker losses across the two runs were {abs(ec['Kinds']['Maker']['EquityChangeExTransfers']):,.0f} versus {abs(eb['Kinds']['Maker']['EquityChangeExTransfers']):,.0f} baseline. {ec['Kinds']['Maker']['FinalAboveFloor']} of 360 repeated Maker observations ended above their risk floor versus {eb['Kinds']['Maker']['FinalAboveFloor']} baseline. This demonstrates funded operation over the tested interval, not indefinite profitability.

The final native suite passed **253 checks versus 246 baseline**, with the same **38 existing failures** (37 TradeLimitsTests fixtures and one SecurityTests fixture), no new failures and no suite crash. New cases cover replacement latency, deterministic profiles, manual exits/stop removal, read-only migration, pending-clock replay, impossible Momentum windows and preservation of valid narrow windows. One old Momentum fixture now checks its actual time budget rather than assuming one contract is due in every first bucket.

Every completed benchmark and endurance run passed accounting and zero-net-inventory audits and compared a complete serialized/restored state after 80 more steps. Native Studio and local Luau matched the entire final state after 400 steps, trade hash **1134040309**. Only empty JSON object/array representation is normalized; numerical state is exact. Checkpoint and policy downgrades fail closed.

Two 120-second saved-world transition checks retained both book sides throughout. Maximum spread was 10 and 14 ticks versus 5 and 11 baseline. A v28/Momentum-v2 checkpoint transition to v3 also retained both sides and passed the audit. Player execution collars and all protection rules were unchanged.

## Installation and artifacts

Final changes span eleven modules: four production/config modules (`Participants`, `MarketConfig`, `WorldCheckpoint`, `BotMomentum`) and seven test modules. Source/editor preflights, readback, backups and Studio history waypoints were used. Play was restarted with the final code; the saved exchange resumed. Studio and Live use separate DataStore scopes. No publication or RBXL save was performed.

`candidate-v3/` contains final source; `candidate-manifest-v3.json` records hashes. `installation-gates-v3.json`, `suite-comparison.json`, `runtime-parity.json`, `applied.json`, `applied-profile-fix.json` and `live-verification-*.json` record checks and application. `development-v3/`, `holdout-v3/`, `details-v3/`, `no-recycling-v3/` and `transition-v3/` contain final results. `pre-apply/` and `pre-profile-fix/` retain source backups. Detached test modules were removed.

From the workspace root, `recheck_profile_fix.py` repeats the ten paired candidate comparisons against the retained baseline results; `recheck_aux_v3.py` repeats the funding and detailed volatility checks. `analyze.py`, `validate_details.py --v3` and `installation_gates.py --v3` compute the final metrics and gates. The local harness runs exported Luau matching/accounting code with exact JSON decoding, not a substitute price model.

Largest streak uses minute body color; dojis break streaks. A completed pullback requires a prior three-minute move of at least four ticks, a retracement of at least two ticks or 15%, and recovery within eight minutes, without overlapping events. Volatility is square-root summed squared log returns over the measured hour, not annualized. The 90-minute funding tests have nine market-hours per arm. Definitions are in `analyze.py` and `MomentumBenchmark.luau`.

Actual OHLC comparisons show every case, with the same vertical scale within each pair:

'''
for label,path in [('Development BX','development-v3-BX.png'),('Validation BX','holdout-v3-BX.png'),('Validation BT','holdout-v3-BT.png'),('Validation BG','holdout-v3-BG.png')]:text+=link(label,path)+'\n\n'
(R/'RESULTS.md').write_text(text,encoding='utf8')
patch=[]
for f in sorted((R/'candidate-v3').glob('*.luau')):
 original=R/'original'/('shared'if f.stem=='MarketConfig'else'server')/f.name
 patch.extend(difflib.unified_diff(original.read_text(encoding='utf8').splitlines(True),f.read_text(encoding='utf8').splitlines(True),fromfile='original/'+f.name,tofile='candidate-v3/'+f.name))
(R/'streak-correction.patch').write_text(''.join(patch),encoding='utf8');print('Final report and patch written')
