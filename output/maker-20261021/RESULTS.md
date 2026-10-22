# Inventory-sensitive Maker: implementation and comparison

**Not installed in Studio: the best tested candidate failed the funding-benefit gate.** Implemented candidate: `variants/responsive`, mirrored into `candidate/`. Baseline is the actual Studio code with the previously installed Momentum v1 and Whale v1. News remains disabled. The target range is evaluated, never imposed by changing prices or inserting unfunded orders.

## Behavior implemented

The previous Maker (`original/server/Participants.luau`, `_maker`) skewed price and size using inventory divided by the full position limit. It had no inventory-age exit, no unwind hysteresis, and could cancel and replace a repriced quote in the same decision. Its three-second delay applied to depleted slots, not every cancellation.

`BotMaker.luau` adds a private, checkpointed profile to each existing Maker, not a new trader population. Its warehouse capacity is the lesser of funded capacity and the greater of 8Ã¢â‚¬â€œ16 normal order sizes or 25% of funded capacity. This is a stricter strategy ceiling, not additional buying power. Nonlinear inventory skew, asymmetric size, and tighter closing-side quote distances encourage position reduction. Repeated own fills temporarily reduce/widen the exposed side; that pressure decays over 30Ã¢â‚¬â€œ90 simulated seconds.

At 60Ã¢â‚¬â€œ75% of warehouse capacity, the Maker withdraws orders that add inventory and uses position-linked reduce-only closing quotes. At 80Ã¢â‚¬â€œ90%, or after 8Ã¢â‚¬â€œ20 minutes with at least 15% utilization, it enters an unwind state. It resumes ordinary quoting only after inventory falls to its individual 20Ã¢â‚¬â€œ35% threshold. Small positions retain ordinary two-sided quoting. This avoids forcing a buy/sell reversal after every one-contract fill.

Quotes remain passive: prices are clamped behind the opposing best order. FIFO survives partial fills and immaterial repricing. Repricing waits 0.75Ã¢â‚¬â€œ2.5 seconds; depleted slots use a per-agent 3Ã¢â‚¬â€œ7-second base, jitter and recent-fill pressure. Existing decision cadence can make the observed wait longer. Minimum rest varies between 18 and 24 seconds; stale or unsafe orders can be withdrawn earlier. Aggregate reduce-only quantities include inherited/manual exits and never exceed held inventory.

All order submissions use the existing engine and funding checks. No direct price, balance, margin, population, protection, stop/retry, accounting or recovery-policy changes were made. Existing risk and recovery machinery retains priority over Maker quoting. This strategy has no compulsory market-order unwind; adverse inventory can therefore remain held while passive exits wait. Existing account-level safety still applies.

## Paired comparison

Three fresh seeds (71, 7919, 104729) and three saved worlds (original checkpoint versions 27, 24, 19). Every older snapshot was first normalized through the same current Momentum + Whale baseline, then forked into both arms. Fresh seeds received 30 minutes of baseline warmup. Both arms received 20 minutes of adaptation, aligned to a minute boundary, followed by 30 measured one-minute candles in each of three markets: six paired cases, 18 market windows per arm.

| Metric | Momentum + Whale baseline | With Maker |
|---|---:|---:|
| Mean 30-minute high-low range | 0.5645% | 0.5662% |
| Windows in 0.7-1.5% band | 6 / 18 | 4 / 18 |
| Mean candle sign-flip rate | 0.1319 | 0.1232 |
| Midpoint sign-flip rate | 0.1199 | 0.1219 |
| Mean candle path / range | 1.4713 | 1.4828 |
| Mean market p95 spread | 3.39 ticks | 3.83 ticks |
| Matched volume | 145,709 contracts | 138,473 contracts |
| Maker passive matched volume | 65,859 contracts | 64,875 contracts |
| Volume-weighted Maker resting age at fill | 15.78 seconds | 14.47 seconds |
| Mean Maker inventory / funded capacity | 0.0344 | 0.0297 |
| Capital recovery transfers, all bots | 3,100,897.52 | 1,775,450.02 |
| Recovery events, all bots | 29 | 18 |
| Maker recovery events | 5 | 3 |
| Maker equity change excluding transfers | -3,795,622.50 | -4,335,005.00 |

There were no missing two-sided quote samples in either selected arm. Matched volume fell about 5%; mean inventory utilization fell about 14%. Candle reversals fell about 7%, but midpoint reversals and path/range were essentially unchanged. Average range remained about 0.57%, below the desired band. Only four candidate windows reached the band, versus six baseline windows. Maker losses increased about 14%, and p95 spreads widened about 13%. Reduced recovery transfers are not evidence of improved profitability. Results also differed by starting state: fresh-seed mean range fell from 0.534% to 0.432%, while saved-world mean range rose from 0.595% to 0.700%. Inventory unwind was observed in 0.15â€“0.46% of Maker samples across cases; ordinary quoting still dominates.

These are exploratory results used to select a version, not an independent holdout or a statistical proof of better market quality. The implementation improves inventory control and makes quote withdrawal finite; it does not establish that the range target or indefinite funding sustainability has been achieved.

The first tested version used sticky price response and reduce-only closing quotes even at tiny positions. It cut average range to 0.282% and raised candle reversals to 0.332, so it was rejected. A third variant preserved most low-inventory baseline behavior but still lowered average range to 0.459%, reached the target in only two windows, and lost more Maker equity; it was also rejected. Their source and results remain under `variants/initial`, `variants/inventory`, and `results-inventory`.

## Safeguards and determinism

The 21 native Studio candidate suites passed 256 checks. The baseline passed 240. Both had the same 38 existing fixture failures (37 in TradeLimitsTests and one SecurityTests out-of-collar fixture); there were no new failures or suite crashes. The 16 new Maker checks cover profile diversity without shared RNG draws, funded passive orders, symmetric inventory skew, soft/hard inventory gates, unwind hysteresis, age exits, FIFO partial fills, delayed refill/repricing, shrinking capacity, manual exit reservations, locked/liquidating/retiring/triggered accounts, zero buying power, thin regimes, migration and exact checkpoint replay. Legacy MakerLiquidityTests explicitly retain the legacy policy fixture; they do not substitute for the new Maker tests.

Every paired simulation completed an accounting/inventory audit and a serialized-checkpoint branch with 80 further steps compared across full state. Native Studio and the local Luau harness produced identical full checkpoint state after 400 steps (trade hash 214609565; zero differences). Only empty JSON object/array representation is normalized for cross-runtime comparison; numeric state is compared exactly. Local measured step cost averaged 4.34 ms baseline and 4.76 ms candidate under concurrent lab load; this is a comparative lab observation, not a native Studio frame-time guarantee. Maximum raw checkpoint size was 7.53 MB versus 7.43 MB, below the unchanged 32 MB raw bound.

All three saved-world migration probes retained two-sided public quotes at every quarter-second sample for the first two simulated minutes. The observed maximum spreads were 27, 3 and 28 ticks. Restoring an old checkpoint itself does not trade, transfer funds or replace positions; Makers adopt at their ordinary decisions and stagger replacement of inherited entry quotes.

Checkpoint v28 persists profiles, own fill observations, private RNG, inventory age, unwind state and quote deadlines. Older readers refuse v28. Momentum and Whale stay at policy v1. Rolling back code alone after a v28 save is unsafe: use a compatible reader or a deliberately coordinated checkpoint rollback.

## Funding endurance

The paired endurance probe disables capital recovery transfers in both arms, allows 20 minutes of adaptation, then measures 90 minutes on seed 71 and the current saved world. Only the lab transfer operation is disabled; drawdown pauses, risk exits, margin and protections remain active. No grants or external recapitalization are introduced. An earlier auxiliary probe disabled the entire participation module, including drawdown pauses, so its results are retained separately under `endurance/` and are not the installation gate. This finite probe measures depletion and continued matched volume; it cannot prove an indefinitely sustainable closed economy.


| Case | Arm | Maker equity change | Makers above floor, start → end | Matched volume in successive 30-minute blocks |
|---|---|---:|---:|---|
| Current | Baseline | -1,009,170.00 | 180 → 164 / 180 | 28,045, 23,952, 23,542 |
| Current | Candidate | -3,854,087.50 | 179 → 161 / 180 | 26,476, 27,954, 25,473 |
| Seed71 | Baseline | -2,757,757.50 | 180 → 180 / 180 | 23,454, 21,731, 20,210 |
| Seed71 | Candidate | -2,134,390.00 | 180 → 180 / 180 | 22,693, 22,554, 20,048 |

All four runs had zero transfers, 180 Makers with positive equity, nonzero matched volume throughout, passing audits and exact serialized replay. Nevertheless, the current saved world lost 3.82 times as much Maker equity with the candidate, with 19 risk-paused Makers versus 16. The fresh seed improved (22.6% smaller Maker loss), but the opposite saved-world outcome makes a general funding benefit unproven. Candidate capital recovery in the ordinary comparison fell 43%, while Maker losses rose 14%; transfer reductions alone were therefore an inadequate acceptance criterion.

**Decision:** retain the existing Momentum + Whale simulation in Studio. The Maker candidate implements the intended controls and passes its safety/determinism checks, but its financial and range tradeoffs do not justify installation. A next experiment should isolate the warehouse ceiling and inventory sizing from closing-side quote compression and age-based liquidation, then use additional held-out seeds and saved states. Keep the existing margins, funded matching and safeguards fixed. This is a diagnostic proposal, not another applied change.

## Installation

No candidate source was applied to Studio, and no v28 checkpoint was written to the live world. All 105 live ModuleScripts were read back against the original exports and matched; live checkpoint policy remains v27, Momentum v1, Whale v1, news disabled, with no BotMaker module installed. The detached test roots were removed. The normal live simulation and autosave were left running. Nothing was published.

Candidate sources, original exports, a unified `maker.patch`, per-case results, native suite output, parity evidence and reproducible runners are retained in this directory. Local `src/` was not used as the authoritative baseline. `ApplyToStudio.luau` was prepared but never executed; its pre-installation gates have not passed. The `candidate/` code is an experimental artifact, not an installed improvement.

Reproduce from the workspace root with `python output/maker-20261021/run_comparison.py` and `python output/maker-20261021/run_no_recycling.py`. The latter disables only transfer rebalancing in an isolated module environment, retaining risk and exit behavior. Native Studio parity and broad native suite evidence are saved alongside the results.
