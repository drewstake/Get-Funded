from pathlib import Path
import json
R=Path(__file__).resolve().parent
results=[json.loads((R/f'results-{v}-gates.json').read_text(encoding='utf8')) for v in ['profit','profit-patient']]
assert all(not r['Passed'] for r in results)
ag=[results[0]['Aggregate']['Baseline'],results[0]['Aggregate']['Candidate'],results[1]['Aggregate']['Candidate']]
rows=[('Candles in significant legs of 8+ minutes (%)','LongRun8CandleShare',100),('Mean longest significant leg (minutes)','SignificantLongestRun',1),('Mean longest candle-color streak','LongestRun',1),('Completed pullbacks across 18 market-hours','TotalPullbacks',1),('One-second realized volatility (%)','OneSecondRV',1),('15-second midpoint volatility (%)','FifteenSecondMidpointRV',1),('One-minute realized volatility (%)','OneMinuteRV',1),('Mean 30-minute range (%)','MeanRange30',1),('Recovery funding','Recovery',1)]
table='| Metric | Installed baseline | Profit-taking | Profit-taking + patient builds |\n|---|---:|---:|---:|\n'
table+='\n'.join('| '+name+' | '+' | '.join(f'{a[key]*scale:,.3f}' for a in ag)+' |' for name,key,scale in rows)
text=f'''# One-sided candle follow-up

**The screenshot identifies a remaining problem. Neither new candidate passed, so no Studio code, tuning, checkpoints or safeguards were changed by this follow-up.** The game remains checkpoint 28, Momentum 2, Maker quote policy 8 and Whale 1, with news disabled. No publication or RBXL save was performed.

## What the previous metrics missed

The last change improved some aggregate statistics, but that did not establish that the smooth directional legs were fixed. Candle-color counts can treat dojis as streak breaks. One-second volatility can increase without producing useful counter-moves visible on a one-minute chart. A larger count of completed pullbacks can coexist with worse long legs elsewhere.

The latest actual saved-world checkpoint was captured read-only from the Studio DataStore. All 105 runtime modules matched the installed baseline. Across its last 180 completed BX candles, **91.7%** belonged to significant directional legs lasting at least eight minutes, the longest leg lasted **22 minutes**, and only **one** completed pullback met the existing event definition. This validates the complaint with exchange data, independently of the screenshot's zoom or vertical scale. These historical measurements are separate from the paired forward simulations below.

## Remaining behavior in the code

`BotMomentum.Signal` still enters Trend and Breakout positions following an observed directional move. Once a build starts, the executor continues buying or selling toward its inventory target, subject to its funded capacity, risk limits and deadline. The installed strategy exits for time, capacity, drawdown, sustained thesis failure or a trailing stop. It has no ordinary profit-taking exit during a still-favorable move. Shortening those cycles changed their timing without ensuring persistent counterflow inside a leg.

`BotSignals.Reversal` requires a genuine recent turn and distance from a recent extreme. Both ordinary Reversion entries and reversion-style Scalpers use it. They can reinforce a reversal once it begins, but cannot reliably initiate counterflow during a smooth continuing leg. Value bots provide some opposing flow, while their observed-price belief follows a 6–18-second half-life. Makers and Reserves quote around executed prices. These are interacting mechanisms; this follow-up does not establish that a single parameter alone explains every wave.

A new execution trace on the installed baseline, seed 71, attributed **+5,323 signed candle-direction-aligned ticks** to Momentum opening/building, versus **−2,521** to its reducing exits, **−2,057** to Value openings and only **−75** to Reversion openings. Momentum opening/building volume was 6,844 contracts versus 206 Reversion opening contracts. These sums span three markets with different tick values: they diagnose timing/direction, not economic P&L, and are not causal proof by themselves. The earlier no-Momentum-entry ablation remains the causal evidence that Momentum materially drives the feedback.

## Two tested changes

Both candidates retain funded matching, account/inventory/margin caps, risk pauses, existing stops, manual protection authority, execution slippage caps, zero-sum recovery and the deterministic scheduler. They add no capital or bot population and never write prices. Candidate files are isolated under `variants/`.

1. **Profit-taking:** Each Momentum agent receives a deterministic private target of 0.4–1.1 times its stop distance, with a six-tick minimum, and a minimum age of 20–50% of its individual horizon, bounded to 12–90 simulated seconds. A profitable executable bid/ask triggers its existing paced reduce-only exit. A favorable last print without a profitable executable quote is insufficient. Targets and ages differ by trader; no shared reversal clock is introduced.
2. **Profit-taking plus patient builds:** The same exits, plus a finite execution-price budget anchored at the signal price. Remaining entry slices wait if a purchase becomes more expensive, or a sale cheaper, than the larger of four ticks or 30% of the stop distance. The existing build deadline still expires. This affects entry orders only; it does not defer risk exits.

Both also correct only the known impossible Momentum confirmation windows. Valid windows remain unchanged. Thus these are bundled policy comparisons, not clean estimates of the isolated profit-taking effect. Proposed Momentum version 4 and checkpoint 29 exist only in the lab and were never installed or written to the game store.

## Paired experiment and decision

Cases: seeds **71, 7919 and 104729**, plus **Latest, Older and Aged** saved worlds. Older/Aged retain their earlier saved-world lineage; they are not independent random seeds. Each version forks the same corresponding snapshot, adapts for 20 simulated minutes, and measures 60 minutes in BX, BT and BG: **18 market-hours per version**, 54 total. The baseline is the installed Momentum-2/Maker-8 simulation, not the older pre-fix simulation.

Two production candidates were frozen before comparisons and not tuned afterward. The predeclared screen requires material improvements in long-leg occupancy, highly directional ten-minute windows and longest color streaks, with more completed pullbacks, preserved volatility/range, bounded recovery funding and exact checkpoint replay. The actual Latest/BX case must also improve; cross-market averages cannot conceal a worse result there. These requirements are recorded in `experiment.json` and evaluated in `gates.py`. The case-specific BX requirement was recorded before any candidate comparison completed. The 0.7–1.5% range remains a soft target, while the screen prevents replacing the wave problem with a materially flatter market.

{table}

**Profit-taking fails:** more completed pullbacks coexist with longer maximum legs, weaker 15-second midpoint volatility and about 23% more recovery funding. Latest/BX's longest candle-color run worsened from 12 to 31 candles in the paired forward hour. The direct chart comparison does not support installation.

**Patient builds also fail:** long-leg occupancy is unchanged in aggregate, longest runs worsen, one-minute volatility falls about 13%, and the specific Latest/BX case fails the pullback and significant-streak requirements. Lower recovery funding is useful but cannot compensate for failure of the requested chart behavior.

No candidate qualified for the planned separate validation seeds/world continuations, full native regression suite or no-recovery endurance stage. Those stages were not run, and no unseen-validation success is claimed. There was no relaxation of failed gates or extra sample extension. This experiment rejects these two policies as a fix; it does not prove that profit-taking or price-sensitive execution can never be useful.

## Safety evidence and limits

Each candidate passed all **18 focused local Momentum tests**, including four added checks for symmetric funded profit exits, executable-quote requirements, private profile diversity/valid windows, and exact checkpoint continuation. Both used the same tested fixture suite; the final suite output on disk is the patient variant. Every one of the 18 benchmark runs passed exchange accounting audits and an exact full-state encoded-checkpoint branch after another 80 steps. All agents retained positive equity in the measured runs. Funding figures above include ordinary recovery, so these results do not demonstrate independence from recycling or indefinite sustainability.

No test failure was waived. Because price-action screening failed, the candidates were not promoted to native Studio testing or installation. Live source readback at the end confirms the original installed baseline and news-disabled configuration. Simulation activity and its ordinary autosaves continue normally.

## Evidence and reproduction

- `baseline-verification.json` records the verified source count and read-only saved checkpoint.
- `current-chart-diagnosis.json` records the actual recent chart measurements.
- `diagnostics/Seed71.json` contains executed-order attribution.
- `results-profit/` and `results-profit-patient/` contain every raw paired result, including OHLC and funding.
- `results-*-gates.json` record the failures; `variants/*/manifest.json` preserves frozen production hashes.
- `shape_metrics.py` counts significant legs: only a cumulative two-tick retracement from the running extreme reverses a leg; dojis and sub-threshold flickers do not reset it. Long-leg occupancy includes intervening quiet minutes. A directional ten-minute window must move at least eight ticks and have net movement at least 90% of total close-to-close path length.
- Existing completed-pullback and volatility definitions remain in `analyze.py` and `MomentumBenchmark.luau`. A pullback needs a prior three-minute move of four ticks, a retracement of two ticks or 15%, and recovery within eight minutes, with no overlapping events. Reported realized volatility is square-root summed squared log returns over the measured hour, not annualized.
- Reproduce with `python output/counterflow-20261021/run_development.py`, then `python output/counterflow-20261021/gates.py`. The harness executes the exported Luau matching/accounting implementation, not a substitute price generator.

All paired BX charts use actual matched-order OHLC and the same vertical scale within each pair:

'''
for name in ['profit','profit-patient']:
    path=R/f'results-{name}-BX.png';text+=f'[{name} comparison](<{path.as_posix()}>)\n\n'
text+='The remaining candle-shape problem is **not resolved**. No additional game change is justified by these results.\n'
(R/'RESULTS.md').write_text(text,encoding='utf8')
(R/'decision.json').write_text(json.dumps({'Installed':False,'Reason':'Both candidates fail predeclared candle-shape and volatility/funding checks','Retained':{'Checkpoint':28,'Momentum':2,'Maker':8,'Whale':1,'NewsFrequency':0},'Published':False},indent=2),encoding='utf8')
print('Report written: both candidates rejected; Studio unchanged.')
