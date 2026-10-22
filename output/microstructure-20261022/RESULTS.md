# Candle microstructure investigation — 22 October 2026

**The smooth-leg problem is not solved. No candidate qualifies for installation. Studio sources remain unchanged; nothing was published or saved as an RBXL.** Fifteen frozen interventions were tested over six development rounds. The work found and reproduced a specific inventory/quote feedback mechanism, but removing it or combining the tested changes did not deliver substantial pullbacks with enough useful movement. Better color counts, lower funding transfers and higher aggregate volatility are not treated as a fix.

The final decision is recorded in [decision.json](decision.json). All failed sources, results, logs and charts are preserved. The independent validation cases remain unexamined.

## Baseline, captured world and comparison design

Read the three requested prior reports before testing, plus earlier Maker and Reversion failures. Exported all 105 actual Studio runtime ModuleScripts and compared complete UTF-8/LF-normalized source with the previous verified baseline. All matched: **checkpoint 28, Momentum 2, Maker quote policy 8, Whale 1, news frequency 0**. The local `src/` directory was not assumed authoritative. Final readback also matched all 105 **Edit sources and editor buffers**. Studio changed from Play to Edit during the investigation; the agent did not stop or restart Play and left it in Edit. No DataStore writes were issued.

A read-only Studio-scope capture yielded step **10,932,654**, simulation time **2,733,163.5 seconds**, save sequence **10,065**. Its last 180 completed BX candles had **98.89% meaningful-long-leg occupancy** and a **24-minute maximum leg**. Those historical measurements differ from the forward comparison. The baseline's forward BX hour has 100% occupancy and a 36-minute maximum leg.

Every arm forks the same six snapshots: seeds **71, 7919, 104729**, plus **CurrentBX, Older, Aged** saved worlds. The archived seed and older-world snapshots carry earlier v27/Momentum-1 state and adopt the installed v28/Momentum-2 policy under the normal scheduler; they are not described as newly warmed v28 seeds. Older/Aged share saved-world ancestry. CurrentBX is the new captured world. Each run adapts for 20 simulated minutes, aligns to a minute boundary, then measures 60 completed one-minute candles in BX/BT/BG. Baseline files reused across arms are checked for complete equality.

There are **96 unique development runs, 288 measured market-hours**: six baseline runs and six runs for each of 15 variants. Development is exploratory and reused for successive hypotheses. Each variant was source-frozen before its own runs; no variant was altered after seeing its results. Separate validation was reserved for seeds **42017, 88069** and **CurrentBXLater, AgedLater**. No candidate passed development, so those snapshots were not generated or inspected. No validation result was reused for tuning or enlarged to rescue a failure.

Evidence: [baseline-verification.json](baseline-verification.json), [final-studio-readback.json](final-studio-readback.json), [run-integrity.json](run-integrity.json), [experiment.json](experiment.json), and the original round plans. [Current saved BX history](current-BX.png).

## Causal mechanism and execution evidence

`Participants:_maker` centers each new quote on the last matched price **minus a signed inventory discount**. Because the next reference is an execution of those already-discounted quotes, an unchanged inventory discount can be applied repeatedly. This is a recurrence, not merely a one-time inventory preference.

The controlled `QuoteDriftProbe.luau` uses the actual matching engine, one funded Maker and funded counterparties. The Maker starts with matched inventory; 40 cycles each execute one buy and one sell, returning Maker inventory to exactly the same quantity. The final taker side alternates across cycles, avoiding an always-last-at-bid artifact. All prices come from matched orders; there are no direct last-price edits or mid-run grants. Across long inventories of 7, 21 and 47 contracts, baseline drift is **−40, −80 and −160 ticks**; the symmetric short inventories produce **+40, +80 and +160 ticks**. Removing only the inventory center displacement gives **zero net drift in all six cases**. Applying only changes in inventory discount also removes the constant-inventory drift in this fixture.

The complete six-case baseline fixture reproduced **exactly in native Studio**, including every observation, audit value, trade hash and quantity. It used isolated in-memory exchange objects and the existing installed modules; it did not mutate game sources or the live world. This establishes a mechanism under controlled conditions, not the fraction of real-market movement attributable to it. Native parity of a small baseline fixture is not native release validation of any candidate.

The full-market intervention gives a different and essential result: removing Maker skew reduces minute volatility by about 21% and 30-minute range by about 47%, while meaningful-long-leg occupancy remains 84%. Thus some baseline movement was driven by this feedback, but eliminating it alone produces smaller waves and quiet stretches rather than the requested chart.

The current-world BX trace includes **2,656 Momentum opening contracts and 2,729 closing contracts**; closing includes **2,591 time exits, 50 thesis exits and 88 stops**. Momentum counterflow therefore already exists. Value has 1,702 opening and 2,044 closing contracts, including 1,234 stops. The final trace separately identifies recovery-risk reductions, including 198 Maker contracts, instead of calling all non-stop closes voluntary. Generic `OtherReduction` labels are not subdivided into unsupported intent claims. Full incoming and passive lifecycle events, observed inventory episodes and minute inventory totals are retained.

There are **29,861 observed same-slot Maker replacements**, with none in the same decision, and **74,946 Reserve replacements**, of which **74,884 (99.917%)** occur in the same decision. These compare a slot's successive order IDs, not adjacent depth levels. In the no-skew/Reserve-delay trace, same-decision Reserve replacements fall to **zero**, while 42,361 ordinary delayed replacements still occur. The full six-case Reserve-delay ablation increases movement but leaves long-leg occupancy near 92%; replacement timing affects liquidity response without being a sufficient shape fix.

Quote movements are not executions. Matched-side event counts include both counterparties and must not be summed as undoubled exchange volume. Minute signed flow attribution is observational and is not a monetary volatility contribution. The final instrumented baseline replay matches the entire uninstrumented terminal checkpoint exactly. Corrected executable-depth sampling also preserves complete state. Early trace versions with gross nearby pending quantity remain preserved, but their depth field is not used as executable liquidity evidence.

Evidence: [quote fixture and native parity](quote-drift-native-parity.json), [baseline fixture](quote-drift-Baseline.json), [no-skew fixture](quote-drift-maker-no-skew.json), [final trace parity](final-instrumentation-parity.json), [baseline lifecycle trace](trace-CurrentBX-final-lifecycle.json), [candidate lifecycle trace](trace-CurrentBX-no-skew-delay-lifecycle.json), [order-flow chart](CurrentBX-order-flow.png), and raw `diagnostics/`.

## Interventions and what each round tests

1. **Quote ablations:** `reserve-delay` applies the existing three-second refill wait to reprice cancellation; `reserve-rest` retains Reserve quotes until expiry; `maker-rest` suppresses ordinary repricing while retaining adverse stale-risk withdrawal; `maker-no-skew` removes only the inventory-dependent center shift, retaining inventory-sensitive quantities and caps. Sticky quotes reduce amplitude; removing Maker skew identifies the recurrence but still leaves quiet long legs.
2. **Opposing-flow mechanisms:** `time-exit-size` uses a full ordinary child size for existing Momentum time exits, retaining deadlines, cadence, slippage and risk exits. `value-exit-gate` lets the existing Value signal reduce inventory without a new-entry valuation-edge hurdle; new risk still needs the original edge. `reserve-cost-quote` keeps the nearest quote on the reducing side nearer the inventory entry cost, with the existing passive guard. That remains an ordinary quote and can trade beyond flat within existing limits; it is not a guaranteed reduce-only exit. None produces the required shape.
3. **Mechanism follow-up:** `inventory-delta` applies changes in the rounded private inventory discount instead of its full level repeatedly. `no-skew-reserve-delay` combines the independently measured no-skew and delayed-refill effects. This combination preserves aggregate minute and midpoint movement but not adequate range or long-leg duration. It is not promoted merely for much lower recovery transfers.
4. **Displayed depth:** `sparse-touch` spreads the same 60 Makers over 20 lanes instead of 10, leaving spacing, capital, size rules and all other limits unchanged. `no-skew-sparse-touch` crosses that with the no-skew ablation. The isolated depth intervention retains range/volatility, but the combination still misses long-leg and range gates. Roblox configuration guidance was consulted; frozen local config was retained for exact replay. No live ConfigService overrides or player experiments were used.
5. **Conditional counterpressure:** `whale-urgency` independently retests the prior 0.30–0.65 aggression range without resetting Whale profiles, mandates or private RNG. `no-skew-sparse-whale` crosses it with the frozen no-skew/sparse book, and `no-skew-sparse-time` crosses the already-tested time-exit concentration with that book. This revisits a prior failed policy only because the new causal fixture identified an interaction absent from that earlier comparison. It does not assume stronger Whales fix the original baseline.

6. **Final depth follow-up:** `no-skew-sparse30-whale` changes only the previous no-skew/sparse/Whale arm from 20 to 30 Maker lanes. The 20-lane arm produced 102 counter events and 12 strict pullbacks versus 61 and zero baseline, while preserving minute volatility; it still failed occupancy, relative range and CurrentBX movement. This source-frozen follow-up tests whether further reducing touch depth restores the missing movement. Gates and holdouts remain unchanged.

All variants are isolated under `variants/`, with SHA256 manifests and `change.patch`. Experimental checkpoint 29 prevents the installed reader from accepting their snapshots. These are research variants, not released policy migrations. Round 3 was chosen from the completed initial four no-skew development cases and the completed six-case Reserve-delay result; all six cases were subsequently completed for every arm. No independent-validation cases entered that choice.

## Measurements and gates

The previous meaningful-retracement measure is retained unchanged: **max(6 ticks, 0.025% of the extreme price, 20% of the preceding leg)**. Dojis and smaller flickers do not reset a leg. Durations are confirmation-to-confirmation, include quiet minutes and are truncated at observation boundaries. Long-leg occupancy is the share of 60 candles in detected legs lasting at least eight minutes; it is not a survival estimate.

The separate strict completed-pullback measure requires a preceding three-minute move of at least 12 ticks, the same 6-tick/0.025%/20% threshold, and recovery within eight samples, with no overlapping strict events. Legacy two-tick/15% pullbacks are retained in raw metric files. Additional descriptive classification labels a counter event as recovery to its pre-retracement extreme, a full reversal across its preceding anchor, or unresolved at the right edge. These directional events can overlap and use the remaining horizon; they are not substituted for non-overlapping strict pullback counts or gates.

Eleven synthetic measurement tests cover thresholds, scale invariance, flat paths, tiny opposite closes, full reversals, completed pullbacks and censoring. Candle OHLC is in dollars; book/trace price movement is in ticks. RV is square-root summed squared log returns over the measured hour, not annualized. One-minute RV uses 59 close-to-close returns for 60 bars. The legacy ten-close directional window spans nine intervals; its old label is retained for comparison. Range uses two disjoint 30-minute OHLC windows. Midpoint sampling uses executable two-sided quotes, with missing-side fractions reported separately.

Frozen gates require occupancy <=80% of baseline, longest meaningful leg <=85%, ten-close directional fraction <=80%, counters >=130%, and at least two-thirds of cases improving occupancy. Minute RV, mean minute range and 15-second midpoint RV must each retain >=90%; mean 30-minute range must retain >=80%. Strict completed pullbacks must increase by at least one in total. CurrentBX/BX must improve occupancy and counter count, not worsen maximum leg, and retain >=90% minute RV. Recovery <=110%, four-candle alternation <=8%, missing-side fraction <=0.1%, p95 spread <=150%, positive equity and exact replay are also required. The user's **0.7–1.5% 30-minute range remains a soft target**. The relative range floor prevents accepting a substantially flattened tape; it was fixed before results, not added to reject an otherwise passing arm.

No failed gate was weakened. Charts are an additional necessary check, not replaced by metrics. [Measurement audit](measurement-audit.json), [metric implementation](metrics.py), [event classification](measurement_audit.py).

## Complete development results

Metrics below average 18 market-hours per arm, except counter/pullback totals and recovery sums. Volume below is actual matched contracts, not both-side event counts.

| Arm | Long legs % | Max leg min | Counters | Strict PB | Minute RV % | Midpoint 15s RV % | 30m range % | Recovery $m |
|---|---|---|---|---|---|---|---|---|
| baseline | 92.7 | 23.17 | 61 | 0 | 0.257 | 0.169 | 0.465 | 5.628 |
| reserve-delay | 92.1 | 23.50 | 64 | 6 | 0.361 | 0.283 | 0.543 | 4.327 |
| reserve-rest | 76.7 | 19.44 | 97 | 6 | 0.146 | 0.098 | 0.202 | 1.193 |
| maker-rest | 93.0 | 32.28 | 45 | 2 | 0.174 | 0.121 | 0.262 | 1.540 |
| maker-no-skew | 84.0 | 22.11 | 84 | 5 | 0.202 | 0.147 | 0.246 | 1.735 |
| time-exit-size | 91.5 | 22.28 | 65 | 2 | 0.280 | 0.185 | 0.422 | 4.558 |
| value-exit-gate | 93.7 | 28.50 | 55 | 2 | 0.253 | 0.168 | 0.430 | 4.544 |
| reserve-cost-quote | 87.3 | 21.94 | 69 | 7 | 0.219 | 0.148 | 0.349 | 2.959 |
| inventory-delta | 80.8 | 24.17 | 85 | 8 | 0.212 | 0.146 | 0.258 | 0.744 |
| no-skew-reserve-delay | 79.1 | 25.33 | 84 | 7 | 0.237 | 0.183 | 0.275 | 0.768 |
| sparse-touch | 89.2 | 19.56 | 74 | 4 | 0.294 | 0.196 | 0.469 | 3.828 |
| no-skew-sparse-touch | 84.5 | 23.28 | 80 | 5 | 0.240 | 0.169 | 0.300 | 1.891 |
| whale-urgency | 90.6 | 23.33 | 67 | 3 | 0.275 | 0.178 | 0.475 | 5.694 |
| no-skew-sparse-whale | 75.6 | 17.33 | 102 | 12 | 0.264 | 0.182 | 0.343 | 2.336 |
| no-skew-sparse-time | 83.9 | 21.61 | 85 | 6 | 0.255 | 0.177 | 0.342 | 1.305 |
| no-skew-sparse30-whale | 79.4 | 20.28 | 99 | 8 | 0.293 | 0.203 | 0.367 | 0.943 |

The descriptive counter-event outcomes below separate full reversals from recovery to the preceding extreme. These can overlap, have no eight-sample deadline and are **not** the strict completed-pullback counts above. Unresolved events remain censored at the observation boundary.

| Arm | Recovered to preceding extreme | Full reversal | Unresolved |
|---|---|---|---|
| baseline | 11 | 36 | 14 |
| reserve-delay | 15 | 34 | 15 |
| reserve-rest | 23 | 48 | 26 |
| maker-rest | 7 | 26 | 12 |
| maker-no-skew | 16 | 43 | 25 |
| time-exit-size | 13 | 36 | 16 |
| value-exit-gate | 6 | 29 | 20 |
| reserve-cost-quote | 14 | 41 | 14 |
| inventory-delta | 20 | 47 | 18 |
| no-skew-reserve-delay | 18 | 47 | 19 |
| sparse-touch | 13 | 38 | 23 |
| no-skew-sparse-touch | 18 | 43 | 19 |
| whale-urgency | 14 | 39 | 14 |
| no-skew-sparse-whale | 27 | 56 | 19 |
| no-skew-sparse-time | 15 | 50 | 20 |
| no-skew-sparse30-whale | 22 | 59 | 18 |

| Arm | p95 spread ticks | Missing-side % | 4-candle alternation % | Matched contracts | Target windows /36 | Maker P&L ex transfers $m |
|---|---|---|---|---|---|---|
| baseline | 4.00 | 0.0015 | 0.68 | 283424 | 1 | -6.245 |
| reserve-delay | 4.00 | 0.0216 | 1.27 | 292378 | 8 | -6.845 |
| reserve-rest | 3.83 | 0.0031 | 2.24 | 238152 | 0 | -1.240 |
| maker-rest | 4.06 | 0.0046 | 2.83 | 214247 | 0 | -3.338 |
| maker-no-skew | 3.89 | 0.0015 | 2.44 | 222502 | 0 | 0.117 |
| time-exit-size | 3.94 | 0.0015 | 2.83 | 293123 | 4 | -5.955 |
| value-exit-gate | 3.94 | 0.0031 | 1.95 | 286235 | 7 | -4.360 |
| reserve-cost-quote | 3.89 | 0.0000 | 1.66 | 252532 | 0 | -2.421 |
| inventory-delta | 3.89 | 0.0000 | 3.02 | 227091 | 0 | 0.214 |
| no-skew-reserve-delay | 3.89 | 0.0093 | 4.09 | 223693 | 0 | -1.548 |
| sparse-touch | 4.28 | 0.0046 | 1.85 | 280282 | 5 | -2.617 |
| no-skew-sparse-touch | 4.28 | 0.0077 | 3.61 | 241395 | 0 | -0.106 |
| whale-urgency | 3.94 | 0.0015 | 1.36 | 317619 | 6 | -7.279 |
| no-skew-sparse-whale | 4.22 | 0.0093 | 1.36 | 284537 | 0 | 0.012 |
| no-skew-sparse-time | 4.22 | 0.0077 | 1.85 | 264382 | 0 | -1.025 |
| no-skew-sparse30-whale | 5.17 | 0.0031 | 2.63 | 281208 | 1 | 0.117 |

The complete per-case and per-market results, all funding recipients/donors, body-color statistics, minute high-low ranges and event records are in [all-development-metrics.json](all-development-metrics.json), [funding-by-kind.json](funding-by-kind.json) and each raw `development-*/` folder. Lower transfers are not equivalent to better profitability; mark-to-market P&L excluding transfers is reported separately. Historical capital adjustments in old saves were preserved and are not counted as new experiment funding.

The strongest shape result, `no-skew-sparse-whale`, reduces mean maximum leg from 23.17 to 17.33 minutes and increases strict pullbacks from zero to 12. It still has 75.65% long-leg occupancy against a 74.15% gate, mean 30-minute range of 0.343% against a 0.372% floor, and CurrentBX/BX minute RV of 0.394% against a 0.430% floor. The final 30-lane variant raises aggregate RV but worsens occupancy to 79.44% and maximum leg to 20.28 minutes; CurrentBX/BX still has zero strict pullbacks. This is why neither better aggregate counters nor more volatility warrants promotion.

### Newly captured CurrentBX / BX, all arms

| Arm | Long legs % | Max leg min | Counters | Strict PB | Minute RV % | 30m range % |
|---|---|---|---|---|---|---|
| baseline | 100.0 | 36 | 1 | 0 | 0.478 | 1.331 |
| reserve-delay | 81.7 | 35 | 3 | 0 | 0.401 | 0.985 |
| reserve-rest | 73.3 | 15 | 6 | 0 | 0.185 | 0.308 |
| maker-rest | 75.0 | 31 | 4 | 1 | 0.255 | 0.339 |
| maker-no-skew | 100.0 | 24 | 3 | 0 | 0.245 | 0.353 |
| time-exit-size | 100.0 | 19 | 3 | 0 | 0.425 | 0.713 |
| value-exit-gate | 100.0 | 23 | 3 | 0 | 0.445 | 0.754 |
| reserve-cost-quote | 91.7 | 21 | 3 | 0 | 0.376 | 0.521 |
| inventory-delta | 100.0 | 17 | 3 | 1 | 0.305 | 0.341 |
| no-skew-reserve-delay | 78.3 | 11 | 7 | 0 | 0.206 | 0.276 |
| sparse-touch | 96.7 | 17 | 4 | 0 | 0.475 | 0.873 |
| no-skew-sparse-touch | 75.0 | 19 | 5 | 0 | 0.440 | 0.553 |
| whale-urgency | 98.3 | 28 | 3 | 0 | 0.454 | 1.064 |
| no-skew-sparse-whale | 81.7 | 22 | 4 | 0 | 0.394 | 0.590 |
| no-skew-sparse-time | 88.3 | 15 | 4 | 0 | 0.406 | 0.586 |
| no-skew-sparse30-whale | 88.3 | 22 | 5 | 0 | 0.408 | 0.535 |

[All current BX arms on one vertical scale](CurrentBX-all-arms.png). Each chart uses actual matched-order OHLC, rebased only for display to its first measured open. Baseline/candidate pairs also share vertical scales in the complete charts below. The no-skew variants often replace large waves with small excursions and quiet intervals; sparse-depth and flow changes retain smooth portions. None should be presented as a solved chart problem.

| Variant | Failed gates | Candle comparisons |
|---|---|---|
| reserve-delay | MeaningfulLong8, MeaningfulMaxLeg, Directional10WindowFraction, MeaningfulCounters, CaseWins, CurrentBXMovement | [BX](development-reserve-delay-BX.png) / [BT](development-reserve-delay-BT.png) / [BG](development-reserve-delay-BG.png) |
| reserve-rest | MeaningfulLong8, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, RangeRetention, CurrentBXMovement | [BX](development-reserve-rest-BX.png) / [BT](development-reserve-rest-BT.png) / [BG](development-reserve-rest-BG.png) |
| maker-rest | MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, CaseWins, RangeRetention, CurrentBXMovement | [BX](development-maker-rest-BX.png) / [BT](development-maker-rest-BT.png) / [BG](development-maker-rest-BG.png) |
| maker-no-skew | MeaningfulLong8, MeaningfulMaxLeg, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, RangeRetention, CurrentBX, CurrentBXMovement | [BX](development-maker-no-skew-BX.png) / [BT](development-maker-no-skew-BT.png) / [BG](development-maker-no-skew-BG.png) |
| time-exit-size | MeaningfulLong8, MeaningfulMaxLeg, Directional10WindowFraction, MeaningfulCounters, CurrentBX, CurrentBXMovement | [BX](development-time-exit-size-BX.png) / [BT](development-time-exit-size-BT.png) / [BG](development-time-exit-size-BG.png) |
| value-exit-gate | MeaningfulLong8, MeaningfulMaxLeg, Directional10WindowFraction, MeaningfulCounters, CaseWins, CurrentBX | [BX](development-value-exit-gate-BX.png) / [BT](development-value-exit-gate-BT.png) / [BG](development-value-exit-gate-BG.png) |
| reserve-cost-quote | MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, RangeRetention, CurrentBXMovement | [BX](development-reserve-cost-quote-BX.png) / [BT](development-reserve-cost-quote-BT.png) / [BG](development-reserve-cost-quote-BG.png) |
| inventory-delta | MeaningfulLong8, MeaningfulMaxLeg, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, RangeRetention, CurrentBX, CurrentBXMovement | [BX](development-inventory-delta-BX.png) / [BT](development-inventory-delta-BT.png) / [BG](development-inventory-delta-BG.png) |
| no-skew-reserve-delay | MeaningfulLong8, MeaningfulMaxLeg, MeanMinuteRangePercent, RangeRetention, CurrentBXMovement | [BX](development-no-skew-reserve-delay-BX.png) / [BT](development-no-skew-reserve-delay-BT.png) / [BG](development-no-skew-reserve-delay-BG.png) |
| sparse-touch | MeaningfulLong8, MeaningfulCounters | [BX](development-sparse-touch-BX.png) / [BT](development-sparse-touch-BT.png) / [BG](development-sparse-touch-BG.png) |
| no-skew-sparse-touch | MeaningfulLong8, MeaningfulMaxLeg, RangeRetention | [BX](development-no-skew-sparse-touch-BX.png) / [BT](development-no-skew-sparse-touch-BT.png) / [BG](development-no-skew-sparse-touch-BG.png) |
| whale-urgency | MeaningfulLong8, MeaningfulMaxLeg, Directional10WindowFraction, MeaningfulCounters | [BX](development-whale-urgency-BX.png) / [BT](development-whale-urgency-BT.png) / [BG](development-whale-urgency-BG.png) |
| no-skew-sparse-whale | MeaningfulLong8, RangeRetention, CurrentBXMovement | [BX](development-no-skew-sparse-whale-BX.png) / [BT](development-no-skew-sparse-whale-BT.png) / [BG](development-no-skew-sparse-whale-BG.png) |
| no-skew-sparse-time | MeaningfulLong8, MeaningfulMaxLeg, RangeRetention, CurrentBXMovement | [BX](development-no-skew-sparse-time-BX.png) / [BT](development-no-skew-sparse-time-BT.png) / [BG](development-no-skew-sparse-time-BG.png) |
| no-skew-sparse30-whale | MeaningfulLong8, MeaningfulMaxLeg, RangeRetention, CurrentBXMovement | [BX](development-no-skew-sparse30-whale-BX.png) / [BT](development-no-skew-sparse30-whale-BT.png) / [BG](development-no-skew-sparse30-whale-BG.png) |

## Finite endurance, safety and promotion decision

The no-skew/Reserve-delay and both no-skew/sparse/Whale combinations received a separate **20-minute adaptation plus 90-minute measurement** on Seed71 and CurrentBX with only `BotParticipation.Rebalance` disabled. Risk pauses, recovery-exit scheduling, margin checks, stops, account liquidation, manual protections, execution collars and matching remained active. Recovery was disabled during adaptation too. This is a development endurance probe, not unseen validation and not a rescue of its failed shape gates.

| Arm | Case | Recovery transfers | Maker P&L | Makers above floor /180 | BX 30m volumes | BT 30m volumes | BG 30m volumes |
|---|---|---|---|---|---|---|---|
| baseline | CurrentBX | 0.0 | $-477,140.00 | 172 | 9341, 8861, 7213 | 7146, 7731, 6701 | 9257, 9816, 9200 |
| baseline | Seed71 | 0 | $-1,267,575.00 | 180 | 5441, 7391, 6879 | 8516, 8673, 7417 | 7205, 6781, 6673 |
| no-skew-reserve-delay | CurrentBX | 0.0 | $-147,080.00 | 176 | 7440, 6006, 8114 | 5238, 6628, 6877 | 8109, 8034, 8400 |
| no-skew-reserve-delay | Seed71 | 0 | $-310,297.50 | 180 | 4571, 4780, 3819 | 7426, 8699, 3659 | 6647, 7900, 6350 |
| no-skew-sparse-whale | CurrentBX | 0.0 | $37,570.00 | 178 | 8502, 7251, 8769 | 8296, 7663, 8082 | 9049, 9416, 8696 |
| no-skew-sparse-whale | Seed71 | 0 | $607.50 | 180 | 6166, 7793, 6967 | 7836, 9575, 8602 | 7191, 7099, 7005 |
| no-skew-sparse30-whale | CurrentBX | 0.0 | $229,007.50 | 179 | 7577, 7662, 6071 | 6464, 7905, 7960 | 8825, 8349, 7613 |
| no-skew-sparse30-whale | Seed71 | 0 | $159,822.50 | 180 | 6227, 7774, 7365 | 7699, 8708, 5407 | 8338, 6219, 7714 |

Every bot retained positive terminal equity; every market had positive matched volume in each 30-minute block; all eight runs had zero recovery transfers, passing audits and exact encoded-checkpoint continuation. This supports finite funded operation only. It does not establish indefinite sustainability or repair the failed candle shape. [Full endurance evidence](endurance-summary.json).

Every completed development and endurance benchmark passes the exchange's cash/equity, zero-net-inventory, volume, order-quantity, FIFO and uncrossed-book audits. Each branches from an encoded/decoded terminal checkpoint, runs another 80 steps, and compares complete state exactly. Only the candidate strategy/config files and experimental checkpoint version differ; accounting, margin, recovery, protection and execution modules are untouched. No bot population, capital allocation, margin allowance or recovery entitlement was increased. No new bot type, synchronized reversal, instant refill, artificial price writer, news event or candle-color logic was introduced. `reserve-delay` uses the already configured refill duration; other arms retain existing refill waits. The controlled fixture's test counterparties are funded at fixture initialization, not by benchmark/live grants.

All 15 current-world migration probes preserve the complete Engine and Population at restore, round-trip encoded state exactly, and confirm the old v28 reader refuses experimental v29 snapshots. This does not make the experimental policies release-ready: native full regression, candidate/native runtime parity and separate validation were **not run**, because no arm passed development. The native baseline causal fixture described above is expressly narrower. No native failure has been waived or represented as passing.

**Installation decision: reject all tested variants and keep the verified baseline.** There are no installed candidate sources to back up or read back. The actual baseline export, final source/editor verification, frozen candidate files and diffs are retained. No production source was mutated, no experimental checkpoint was written to the game store, and nothing was published. The work establishes the repeated inventory-discount mechanism and rejects these attempted remedies; it does not claim that every possible strategy change must fail.

Evidence: [source scope and hashes](source-scope-audit.json), `migrations/`, [instrumentation parity](final-instrumentation-parity.json), [native causal-fixture parity](quote-drift-native-parity.json), [final Studio readback](final-studio-readback.json), [decision](decision.json).

## Reproduction

Run from the workspace root with the existing bundled Lune runtime. The harness executes actual exported Luau matching, accounting and strategy code; it does not synthesize replacement price paths. Source manifests use canonical UTF-8/LF contents. Python commands use UTF-8 mode on Windows.

```powershell
python -X utf8 output/microstructure-20261022/measurement_audit.py
python -X utf8 output/microstructure-20261022/audit_sources.py
python -X utf8 output/microstructure-20261022/run_batch.py development
python -X utf8 output/microstructure-20261022/summarize_batch.py development
python -X utf8 output/microstructure-20261022/run_migrations.py
python -X utf8 output/microstructure-20261022/run_endurance.py no-skew-reserve-delay no-skew-sparse-whale no-skew-sparse30-whale
python -X utf8 output/microstructure-20261022/endurance_summary.py
python -X utf8 output/microstructure-20261022/compile_report.py
python -X utf8 output/microstructure-20261022/check_delivery.py
```

Completed benchmark files are cached. For a fresh replay without overwriting preserved results, use `run_batch.py development --tag=rerun` and then `summarize_batch.py development-rerun`; this writes separate folders. A final candidate name can select one arm. `LocalLab.luau` also exposes `diagnose`, `tracecontrol`, `driftprobe`, `migrationprobe`, `suite` and `parity` modes; raw invocations and logs are preserved. Do not rerun initial `setup.py` or variant preparation scripts over this completed investigation: they are scaffolding, not result reproduction.

The [reproducibility manifest](reproducibility-manifest.json) records byte hashes of the harness, original/candidate sources, snapshots, unique raw runs, traces, reports and charts, plus the Lune runtime. Individual candidate manifests retain their original canonical UTF-8/LF hashes. `verify_studio_readonly.luau` reproduces the final source/editor comparison using the local expected-source bundle; it does not mutate Studio sources.

The read-only source/world bridge is local tooling, not game code. All subsequent simulations operate on captured snapshots. Saved worlds continue to have shared ancestry, and selection across 15 development variants has exploratory bias. That is why the unused holdouts, unchanged gates and explicit rejection are essential.
