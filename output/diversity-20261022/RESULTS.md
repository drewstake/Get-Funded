# Maker feedback and trader diversity — 22 October 2026

**No candidate qualifies for installation. The chart objective remains unsolved. Studio's 105 installed module sources and editor buffers still match the original baseline, checked at 2026-10-22T16:03:23Z. Nothing was installed, published, saved as an RBXL, or written to DataStores.**

This continuation tested **30 complete behavior arms**, two compatibility derivatives and four aborted implementations, across fifteen development rounds. There are **192 completed candidate runs, representing 576 measured market-hours**, plus six reused baseline runs. These totals exclude partial aborted runs, focused fixtures and endurance. The prior [15-arm microstructure investigation](../microstructure-20261022/RESULTS.md) remains preserved. Removing the identified Maker inventory feedback is achievable; replacing its movement with healthy, substantial within-trend pullbacks has not yet passed the required checks.

The machine-readable [decision](decision.json), [all-arm results](DEVELOPMENT.md), [run integrity](run-integrity.json) and [work log](WORK_LOG.md) preserve the outcome. Separate validation cases were **never generated or examined**. No numerical threshold was relaxed to promote a near miss.

## Baseline and comparison design

The actual installed baseline is checkpoint **28**, Momentum **2**, Maker quote policy **8**, Whale **1**, with news frequency **0**. All 105 source exports in `original/` match the previous actual-Studio export. The final read-only audit compares both `.Source` and the editor buffer, rather than trusting the local `src/` tree. Studio remained in Edit throughout this continuation; no Play controls were issued.

The current saved-world input is the read-only capture at step **10,932,654**, time **2,733,163.5**, sequence **10,065**. Every candidate forks the same six snapshots: Seed71, Seed7919, Seed104729, CurrentBX, Older and Aged. Archived seeds and older worlds carry earlier checkpoint-27/Momentum-1 state and adopt the installed baseline through its normal scheduler. Older/Aged share saved-world ancestry. They are not six independent freshly generated trajectories.

Each run has 20 minutes of adaptation, minute-boundary alignment and 60 measured completed one-minute candles in BX/BT/BG. Every reused baseline result is byte-identical to the cached reference. Snapshot SHA256 values and complete output hashes are in [run-integrity.json](run-integrity.json). Full encoded-and-decoded checkpoint continuation is compared exactly, not just via a trade hash.

Reserved validation consists of fresh seeds 42017/88069 and CurrentBXLater/AgedLater. Before any holdout generation, the copied later-world helper was corrected to advance the baseline by 7,200 seconds so its observation window cannot overlap development. Descendant saved worlds would still share ancestry; only the two fresh seeds would supply independent random starts. The [preregistered protocol](validation-protocol.json) permits one frozen candidate, all four cases, unchanged gates and no tuning after inspection. No candidate reached that stage. Native regression/parity and transition checks also remain required before any future installation; prepared harness files are not completed test results.

## What was established causally

The earlier controlled funded fixture established a specific recurrence: centering each new Maker quote on the last execution minus the same inventory discount repeatedly applies that discount even when inventory returns to exactly the same amount after each balanced buy/sell cycle. Long inventories of 7/21/47 contracts drift −40/−80/−160 ticks over 40 cycles; symmetric short inventories drift oppositely. Removing the inventory center displacement produces zero drift in all six fixtures. [Native baseline fixture parity](../microstructure-20261022/quote-drift-native-parity.json) was exact. That is evidence about the fixture, not native certification of the new strategies.

Every continuation variant removes this center displacement and retains inventory-sensitive quantities and funding limits. Most still reference the last matched price; executable-midpoint arms test a different reference. **This does not claim to eliminate every form of quote-following feedback.** The matching engine, price recording, margin engine and stop machinery are unchanged. There are no direct price or candle writes.

The prior isolated no-skew intervention lost about 21% of minute volatility and 47% of 30-minute range. That motivates replacing the lost movement with funded opposing demand. Additional trader *behaviors* are assigned to existing accounts, with no new accounts or grants:

- **Stretch:** existing Reversion accounts use independent public-price horizons to fade an extension before a turn; staged entry, finite target inventory, profit/time exits, existing stops and private cooldowns remain.
- **Portfolio:** existing Value accounts receive independent signed inventory objectives, private saved RNG and staggered build/hold/flatten cycles, independent of the current price direction.
- **Mixed institutions:** six of eighteen existing Reserve accounts per market are reassigned: three Portfolio and three Stretch. They settle inherited positions before new risk; twelve retain passive Reserve behavior. A withdrawal-only control separates removal of passive supply from the new trading flow.
- **Patient Stretch:** finite build/hold periods reflect the signal horizon; new building stops when the extension disappears. **Rolling Portfolio:** private targets can add or trim inventory at reviews without forced flattening each time; opposite targets close first and cool down, and every episode still expires.

The withdrawal-only arm produces 117 meaningful counter events and 22 strict pullbacks, versus 148/33 for mixed institutions. Both fail spread. This paired intervention supports contributions from both reduced passive supply and new trading behavior, rather than attributing all improvement to a new trader type.

Quote sampling showed that actual wide spreads frequently follow depletion: requested half-spread in BX/BG never exceeded three ticks, while executable gaps still reached 9 ticks; BT reached 27. Merely capping requested width failed. Restoring original Maker depth later fixes the aggregate spread failure under persistent rolling demand, but does not fix recovery transfers or missing quotes. These controlled changes identify interactions; they do not apportion market variance to individual causes.

The full trace records funded incoming and passive fills, entries, exits, stops, inventory, independent strategy phases and actual same-slot quote replacements. In the mixed-institution current BX trace, Reserve/Portfolio opens 1,513 and closes 1,540 contracts; Reserve/Stretch opens 1,350 and closes 1,225, all of its sampled closes timed. Those are account-participation counts, not unique exchange volume. Timed closure despite a long signal horizon motivated the patient-Style test. Instrumented and separately sampled quote-statistics runs finish at the same full terminal state. See [trace summary](trace-last-reserve-summary.json), [instrumentation parity](instrumentation-parity.json) and `diagnostics/`.

## Development outcomes

The following are development comparisons, not estimates from unseen data. Occupancy, maximum leg, RV, range and spread average eighteen market-hours per arm; strict pullbacks and recovery are totals. [DEVELOPMENT.md](DEVELOPMENT.md) includes **every completed arm**, current BX detail, missing quotes, matched volume and all paired candle links. Round plans and immutable `variants/<name>/manifest.json` and `change.patch` files retain each exact intervention.

| Arm | Long-leg occupancy | Mean max leg | Strict pullbacks | Minute RV | 30m range | Mean p95 spread | Recovery | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Installed baseline | 92.69% | 23.17m | 0 | 0.2568% | 0.4652% | 4.000 ticks | $5.628m | Reference |
| portfolio | 68.52% | 18.44m | 19 | 0.4121% | 0.4699% | 5.611 ticks | $1.646m | Chart rejection |
| last-reserve-diverse | 61.94% | 17.50m | 33 | 0.3433% | 0.4156% | 6.389 ticks | $0.745m | Spread |
| inner-patient-stretch | 64.26% | 18.83m | 38 | 0.3763% | 0.4224% | 5.444 ticks | $0.995m | Chart rejection |
| inner-patient-quote-safe | 59.17% | 16.78m | 47 | 0.3531% | 0.4130% | 5.556 ticks | $1.680m | Chart rejection |
| rolling-portfolio-robust | 74.35% | 17.44m | 27 | 0.7918% | 0.8237% | 6.944 ticks | $12.319m | MeaningfulLong8, Recovery, Quotes, Spread |
| rolling-patient-robust | 75.00% | 19.56m | 33 | 1.3284% | 1.2010% | 7.111 ticks | $31.472m | MeaningfulLong8, Recovery, Quotes, Spread |
| rolling-portfolio-depth | 72.78% | 19.56m | 14 | 1.0615% | 0.9314% | 5.333 ticks | $8.204m | Recovery, Quotes |
| rolling-patient-depth | 68.43% | 17.56m | 26 | 0.9771% | 0.9000% | 5.111 ticks | $8.335m | Recovery, Quotes, CurrentBX |
| rolling-cost-aware | 76.11% | 18.22m | 23 | 0.6837% | 0.6803% | 4.556 ticks | $3.239m | MeaningfulLong8, Quotes |
| rolling-touch-participation | 79.54% | 19.39m | 11 | 0.5271% | 0.5431% | 4.500 ticks | $2.959m | MeaningfulLong8, CurrentBXMovement |


The first rounds separate Stretch and Portfolio behavior, combine them, broaden horizons and compare last-execution versus executable-midpoint centers. Midpoint designs often flatten movement. Later rounds isolate withdrawn Reserve supply, mixed/all-fader institutions, twenty/fifteen/ten Maker lanes, a requested-width cap, closer lanes and a bridge at only the nearest neighboring lane. Multi-horizon Portfolio clocks retain a 41-minute current-BX leg and are rejected. Patient Stretch passes the numerical gates in one configuration but produces an unacceptable quiet plateau. The last rounds compare finite versus rolling allocations, patient versus ordinary Stretch, original Maker depth, execution-cost limits and visible-touch participation. No favorable metric from one arm is combined with another arm's funding or charts to declare a pass.

The final cost-aware arm admits discretionary allocation risk only when spread plus allowed slippage is at most 25% of its existing stop distance. It produces three strict current-BX pullbacks and .5242% current-BX minute RV. Across the complete six cases it lowers recovery to $3.239m, but long-leg occupancy is 76.11% against a fixed 74.15% maximum, and missing quotes are 0.1034% against .1000%. **It is rejected, even though both misses are smaller than earlier failures.** Adding a cap of 25% of actual best-level quantity reduces current-BX minute RV to .2574%, below the .4304% floor. Entry guards never block mandatory or voluntary risk reductions; no displayed liquidity is manufactured.

## Why numerical passes were rejected

`portfolio`, `portfolio-dense`, `inner-patient-stretch` and `inner-patient-quote-safe` pass numerical development gates. Their actual matched-order candles still fail the original requirement. The first two retain quiet platforms and largely uninterrupted current-BX waves. The patient arm has a prolonged quiet middle and a late jump: one minute accounts for 49.03% of close-return variance and five for 80.72%, versus baseline 5.83%/25.64%. 62.71% of intervals fall below the original six-tick/0.025% floor, versus 23.73% baseline. The quote-safe control retains a 24-minute current-BX leg with no strict pullback and nearly half its intervals below that floor.

These coverage statistics are descriptive support for the existing chart requirement, not new replacement gates. Some other worlds visibly improve; that does not establish the required current-world result. [Chart decisions](chart-review.json), [coverage data](movement-coverage.json), and [current-BX comparison](CurrentBX-candidate-comparison.png) make the rejections reviewable. Full paired plots preserve OHLC and identical vertical ranges within each baseline/candidate pair. No candle colors or price data were edited.

![Current saved BX comparison](C:/Users/drews/Development/Roblox Dev/Get Funded!/output/diversity-20261022/CurrentBX-candidate-comparison.png)

## Measurement audit and unchanged gates

The meaningful retracement threshold remains **max(6 ticks, .025% of extreme price, 20% of the preceding leg)**. Tiny opposite closes and dojis cannot reset the leg. Durations are confirmation-to-confirmation, include quiet minutes and are truncated at observation boundaries. The strict completed-pullback measure requires a preceding three-minute move of at least twelve ticks and recovery within eight samples, without overlapping strict events. The separate full-leg event classification distinguishes recovered pullbacks, full reversals and unresolved right-edge events; its counts do not replace the strict gate. The baseline has zero *strict* pullbacks, but eleven recovered full-leg events, 36 full reversals and fourteen unresolved events.

Eleven [measurement edge cases](measurement-audit.json) cover flat tape, tiny flickers, thresholds, scaling, full reversals and censoring. OHLC is in dollars; book prices/signals are in ticks. Minute RV is root-summed squared log returns over 59 close-to-close intervals, not annualized volatility. Range30 uses two disjoint windows. The legacy ten-close directional measure spans nine intervals; its old name remains for comparability. Midpoints require two-sided executable quotes; missing-side rates are reported alongside them.

Required aggregate changes: long-leg occupancy ≤80% of baseline, mean maximum leg ≤85%, directional-window fraction ≤80%, counters ≥130%, and at least four of six cases improving occupancy. Minute RV, mean minute range and 15-second midpoint RV each retain ≥90%; range30 retains ≥80%; strict pullbacks increase by at least one. Current BX must improve occupancy/counters, not worsen maximum leg, and retain ≥90% RV. Recovery ≤110%, four-candle alternation ≤8%, missing quotes ≤.1%, mean market p95 spread ≤150% of baseline, positive terminal equity and exact serialized replay remain mandatory. The user's .7–1.5% range30 is a soft target. Charts are an additional necessary check. See [metrics.py](metrics.py) and [experiment.json](experiment.json).

## Safety, compatibility and funding

All 192 complete candidate runs have exact local serialized replay, positive terminal equity in every account, zero net system inventory and sixty completed bars per market. Maximum absolute cash/equity audit residues are 1.13481656e-06/3.38768587e-06, consistent with floating-point accumulation; no new funds are introduced. [Source scope](source-scope-audit.json) checks all frozen hashes and unchanged original modules. Experimental checkpoint 30 isolates raw research; compatible derivatives use 31, retain old baseline-readable versions and explicitly reject experimental checkpoint 30/29. The installed checkpoint-28 reader rejects candidate state.

Current-world migration probes preserve complete Engine and Population state before the scheduler adopts strategy configuration, retain saved Whale profiles/clocks/RNG, and pass exact encoded roundtrip. There are 31 preserved probe results under `migrations/`. The two older compatibility derivatives reproduce all six parent market paths, initial/final accounting, audit and replay exactly; [evidence](integration-economic-parity.json).

Broad local regression findings are preserved, not waived:

- Raw `last-reserve-dense`: fifteen additional failures exposed hardcoded Whale aggression, absent legacy policy dependencies and stale policy/version fixtures. The separately frozen compatibility derivative fixes configuration handling and retains legacy strategy tests alongside dedicated new-behavior tests.
- `last-reserve-diverse-ready`: 242 local checks pass versus 226 baseline; no new failures. `inner-patient-stretch-ready`: 243 pass, with one additional old uniform-lane geometry assertion failure. That immutable derivative remains failed. Later frozen derivatives make the nearest-lane bridge explicit, retain the uniform-lane fixture and add a funded bridge fixture.
- `rolling-cost-aware`: 255 local checks pass versus 226 baseline; 0 additional check failures. Both retain 39 local baseline failures and 2 suite crashes. RunService support and the client UI constructor limit the offline harness; local results are **not native regression results**. Complete comparison: [local suite evidence](local-suites-rolling-cost-aware-comparison.json).

Rolling tests also exposed a pre-existing one-sided Whale quote bug: Lua's `and/or` selection could fall through to the wrong quote when the intended quote was nil, including a nil-arithmetic crash. The installed baseline fails three of four isolated cases. Explicit conditional selection preserves nil and passes all four in the robust derivatives. The same protection is applied to the new Diversity execution/profit-touch paths. [Baseline reproduction](one-sided-whale-baseline-reproduction.json) and `focused-*/` preserve both failure and repair. This fix is **only in the isolated candidate files**, not installed.

Four aborted versions remain under `variants/`: `rolling-portfolio` and `rolling-patient` could overwrite inherited reducing phases; their `*-safe` successors exposed the one-sided quote failure. Each has a rejection record and retained partial artifacts. They are excluded from complete-batch averages, not silently discarded. Later robust versions fix these issues before running their full batches.

Finite recovery-disabled endurance runs cover Seed71 and CurrentBX for baseline, Portfolio, dense Reserve mix, inner-lane mix, patient integration and final cost-aware allocation. Only the existing recovery/rebalance routine is disabled; risk exits/stops/cooldowns stay active. Over 20 minutes adaptation plus 90 minutes measurement, the retained results show zero transfers/recoveries, positive terminal equity, actual volume in all three half-hour blocks in every market, and exact replay. These are finite checks, not indefinite sustainability. The final cost-aware current-world Makers lose $1.614m versus $0.477m baseline, despite surviving the interval. Losses, risk-floor depletion and eligibility are retained by group in [endurance-summary.json](endurance-summary.json); positive equity alone does not mean profitable market making.

No final candidate passes development and chart review, so **native release regression, complete native/Lune runtime parity, transition certification and separate validation were not executed for a selected release**. Earlier native baseline drift-fixture parity must not be mistaken for those requirements. Nothing is ready to install based on these results.

## Reproduce and inspect

Run from `C:\Users\drews\Development\Roblox Dev\Get Funded!` with Python and the retained Lune runtime. These commands operate on the isolated lab and do not connect to or modify Studio:

```powershell
python -X utf8 output/diversity-20261022/audit_sources.py
python -X utf8 output/diversity-20261022/measurement_audit.py
python -X utf8 output/diversity-20261022/run_batch.py development rolling-cost-aware --tag=rerun
python -X utf8 output/diversity-20261022/metrics.py development-rerun-rolling-cost-aware
python -X utf8 output/diversity-20261022/plot_comparison.py development-rerun-rolling-cost-aware
python -X utf8 output/diversity-20261022/run_local_suites.py rolling-cost-aware
python -X utf8 output/diversity-20261022/compare_suites.py local-suites-rolling-cost-aware
python -X utf8 output/diversity-20261022/run_endurance.py rolling-cost-aware
python -X utf8 output/diversity-20261022/endurance_summary.py
```

The tag creates separate measured results; omit no source-freeze checks. Existing endurance outputs are cached, and the harness modes in [LocalLab.luau](LocalLab.luau) allow explicitly named new output directories. All raw measured paths, per-market metrics, execution traces, migrations, suite logs and immutable sources remain available. [Final Studio readback](final-studio-readback.json) is the evidence for the exact rejection decision: **leave the installed game unchanged**.
