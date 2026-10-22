# Candle microstructure investigation, 22 October 2026

## Objective and state

Read the supplied goal objective and all three requested prior reports in full. Also read earlier Maker and Reversion failures to avoid bundling their rejected approaches. The objective is useful one-minute matched-order pullbacks, not candle-color flips or spread bounce.

Authoritative baseline: 105 actual Server/shared Studio ModuleScripts exported and compared byte-normalized against the prior verified source; all equal. Verified baseline: checkpoint 28, Momentum 2, Maker quote policy 8, Whale 1, news disabled. Studio began in Play and later switched to Edit externally; the agent did not control Play. No source mutations, DataStore writes, saves, publications or Play restarts issued.

Read-only Studio DataStore capture: step 10,932,654; time 2,733,163.5; save sequence 10,065. Captured snapshot and source hashes in baseline-verification.json. BX last 180 completed one-minute bars: legacy meaningful-long-leg occupancy 98.89%, maximum 24 minutes.

## Frozen design

All six development cases fork identical snapshots: seeds 71, 7919, 104729 and CurrentBX, Older, Aged. Older/Aged and seed snapshots retain previously described lineage and policy migration; no claim they are independent newly warmed v28 worlds. Adaptation 20 minutes, measurement 60 minutes, three markets. Separate holdouts are still untouched: seeds 42017, 88069, CurrentBXLater, AgedLater. Iterative development is allowed; a holdout failure cannot be retuned or rescued by adding cases.

Retain prior shape/movement/funding gates. Additional gates frozen before results: at least one more strict completed pullback in total, CurrentBX minute volatility >=90% baseline, aggregate 30-minute range >=80% baseline. The requested 0.7–1.5% range is a soft target; this floor prevents replacing waves with flat trading. Visual inspection remains necessary.

## Round 1: isolated causal ablations

- reserve-delay: apply the existing three-second depletion delay also after reprice cancellation, preventing cancel/replace in one decision.
- reserve-rest: suppress voluntary Reserve repricing, retaining original expiry and funded renewal.
- maker-rest: suppress ordinary Maker price chasing, retain adverse stale-risk cancellation and depth withdrawal.
- maker-no-skew: remove only inventory-dependent reservation-price displacement; preserve inventory-sensitive sizes and all caps.

Every variant has a source hash manifest and experimental checkpoint 29; none is a release candidate. No combination before seeing isolated results. Only strategy modules and checkpoint version metadata are changed in local variants.

## Measurement audit

The original meaningful retracement detector is unchanged: max(6 ticks, 0.025% of extreme price, 20% of preceding leg). It measures detection-to-detection durations, including quiet minutes and truncated boundary legs. Strict completed pullbacks use a preceding three-minute >=12-tick move and recovery within eight samples. Added descriptive event classification distinguishes recovery to prior extreme, crossing of preceding anchor (full reversal), and unresolved right edge. It does not replace gates. Eleven synthetic edge cases pass in measurement-audit.json.

The old ten-minute-window metric is ten closes/nine intervals; the original label is retained for comparison. RV is square-root sum squared log returns, not annualized. Recovery deltas exclude adaptation. Initial harness depth container was unused; spread and missing-side data are executable quotes. Initial enhanced trace depth is gross nearby pending quantity and must not be presented as executable depth.

## Harness and trace work

run_batch.py runs four local Luau processes, checks frozen source hashes, caches completed paired results and preserves all variants. run_traces.py captures actual incoming/passive lifecycle events, inventory and same-slot replacement IDs and verifies an instrumented current replay against a complete uninstrumented terminal checkpoint. Trace output is observational evidence, distinct from controlled ablation effects.

## Completed investigation and decision

All six rounds are complete: 15 frozen variants, six paired development cases per variant, 96 unique runs and 288 measured market-hours. Round plans, all raw results and patches are preserved. The inventory/quote recurrence was isolated in the actual matching engine and the complete six-case baseline fixture reproduced exactly in native Studio. Final executable-depth and lifecycle instrumentation preserves the complete uninstrumented checkpoint.

Eight finite endurance runs (baseline and three combinations, two cases each) completed with zero recovery transfers, positive terminal equity for every bot, positive volume in every market/30-minute block, and exact checkpoint continuation. All 15 current-world migration probes passed their narrow state-preservation, round-trip and old-reader rejection checks.

No candidate passes all unchanged development gates. The final 30-lane follow-up still fails occupancy, maximum leg, relative range and CurrentBX movement. All candidates are rejected. Independent validation remains untouched, and full native candidate regression/runtime parity were not entered. Studio remains in Edit with all 105 source and editor buffers matching baseline; nothing installed or published. RESULTS.md and decision.json are the authoritative complete delivery.
