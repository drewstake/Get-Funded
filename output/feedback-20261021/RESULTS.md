# Directional feedback investigation — 21 October 2026

**No candidate qualifies for separate validation or installation. The smooth-leg problem remains unresolved. Studio remains unchanged; nothing was published or saved as an RBXL.**

Read `output/streaks-20261021/RESULTS.md` and `output/counterflow-20261021/RESULTS.md` before this experiment. This report does not reinterpret those aggregate improvements as a chart-shape fix, and does not repeat their rejected profit-taking/patient-build policies.

## Verified current baseline and saved world

Exported all **105 actual Studio runtime ModuleScripts** and compared their complete source with the installed baseline. All match. Checkpoint **28**, Momentum **2**, Maker quote policy **8**, Whale **1**, news frequency **0**. A read-only Studio-scope DataStore capture yielded saved step **10,799,234**, simulation time **2,699,808.5 seconds**, save sequence **9,952**. No DataStore writes were issued by this investigation. Final source hashes again match all 105 exports.

The supplied Bot Stats snapshot is earlier, at step 10,795,161. It reports about $408.34m cumulative recycled capital, including roughly $229.39m net to Makers and $68.48m to Value, alongside net transfers out of Momentum and Whale. Those are historical figures, not this experiment's funding cost. The very large legacy capital-adjustment ledger is not treated as new capital or modified. Forward comparisons use measured transfer deltas and exchange accounting audits.

The current saved world's last 180 completed BX candles are visibly smooth waves: **97.2%** of candles lie in meaningful legs lasting at least eight minutes; the longest is **23 minutes**. Dojis and small opposite candles do not reset this measure. [Actual saved BX candles](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/current-BX.png>).

## Entries, exits, inventory and quote replacement

The code still forms a feedback loop. `BotMomentum.Signal` enters from a continuing trend/breakout; `Step` spends a finite build budget toward inventory and allows another entry after cooldown. Time exits oppose that entry flow, but their clocks follow the earlier entries, while other traders can keep building. Different private horizons do not by themselves produce independent trading directions. The known v2 impossible-confirmation profiles are preserved; no correction is bundled into this experiment.

`Participants:_observe` gives Value a 6–18-second belief half-life, so its estimate quickly follows prices. Its signal and inventory penalty can oppose movement, but the estimate is not a persistent independent valuation anchor. `BotSignals.Reversal` requires an actual recent turn before Reversion can open, leaving it largely unable to initiate the turn during a smooth move. Ordinary exits and risk stops can then return that inventory to the book. Whale uses independent portfolio mandates and can supply either side; it is not the dominant aligned-price source in these traces.

In the **current-world BX hour**, Momentum opening/building trades execute **2,423 contracts** and contribute **+1,987** signed candle-direction-aligned tick changes. Its ordinary time exits execute **2,106 contracts**, contributing **−1,188** aligned ticks. Value openings contribute **−658** ticks over **923 contracts**, versus Reversion openings' **−7** ticks over **92 contracts**. Momentum thesis exits contribute **+82** ticks over 140 contracts: an exit can follow the new price direction. Stops are separately classified from stale strategy phase/exit labels in the final trace. For example, Value stops close 597 contracts and contribute +23 aligned ticks; Liquidity stops close 404 and contribute +8. Stops are real contributors, but these observations do not justify calling them the dominant source.

There are **256 observed Momentum position openings**, with 220 having an earlier observed opening for the same trader; **121 repeat the previous direction**, at a median interval of **448.4 seconds** across all repeat observations. These counts cover incoming matched entries, not every passive or inherited position. The seed-71 BX trace independently contains 110 same-direction repeats out of 208 repeat observations. Re-entry exists, but the failed re-entry ablation below shows that blocking it alone is insufficient.

Minute-start net Momentum inventory ranges from **−272 to +273 contracts** in current BX; Maker inventory ranges **−261 to +202**, Value **−279 to +129**. The flow chart shows the inventory cycles and ongoing opposing executions inside long legs. It is inaccurate to say the market has no counterflow; its size, timing and available price levels do not consistently produce substantial counter-moves.

`OrderFlowMarket.Reference` returns the last matched price. Makers center quotes on it with inventory skew; Reserves do the same. Liquidity traders use the executable midpoint and prioritize a passive exit after acquiring their small inventory. In the traced BX hour there are **25,617 actual same-slot Maker replacements** and **75,651 Reserve replacements**. Mean time between placements in a slot is approximately **50.6s** and **8.6s** respectively, including resting time and replacement gaps; these are not refill-delay estimates. Maker cancellation mean age is 28.5s; Reserve cancellation mean age is 8.6s. Replacement price changes generally follow the ongoing candle direction. Current Maker delayed refills remain active; Reserve repricing can still cancel and replace in the same decision (a pre-existing behavior, not added here).

Quote shifts are not executions and must not be added to trade movement. Counts are aggregated across agents and quote depths; a replacement reserves funded capacity but is not a cash injection. This observational trace does not establish the isolated causal effect of each quoting policy. The earlier Momentum-entry suppression experiment remains separate causal evidence. [Matched candles, aggressive flow, inventory and same-slot replacement shifts](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/CurrentBX-order-flow.png>).

Instrumentation was checked against an uninstrumented replay of the same current checkpoint: the **entire terminal checkpoint matches exactly**, including accounts, orders, inventory, random state and trade history. This is stronger than matching only price or an aggregate audit. Raw minute-level records, cycle events, passive counterparties and terminal states are in `diagnostics/`; summaries are `trace-CurrentBX-summary.json` and `trace-Seed71-summary.json`.

## Frozen targeted experiments

Three arms were frozen before their development comparisons, with SHA256 manifests of canonical UTF-8/LF production source retained (Windows file line endings are normalized when checking these manifests). No parameter was retuned after results arrived.

1. **Momentum re-entry gate**: after an entry episode, another same-direction episode requires an individually observed retracement of at least max(6 ticks, 35% of that trader's stop distance). No shared timer or reversal order is added. Existing builds, opposite signals and all exits retain their prior machinery. Existing v2 profiles and shared RNG consumption are unchanged.
2. **Longer Value memory**: multiply the existing, individual Value belief half-life by ten (60–180 seconds), preserving observation timing/noise, inventory penalty, order size, capital, margin and stops.
3. **Combined**: both changes together.

Only isolated lab files were changed. Experimental checkpoint version 29 prevents the installed v28 reader accepting an experimental snapshot. These are research variants, not release-ready migrations; none was saved into the world. No new bot kind, artificial price writer, synchronized reversal, funding entitlement, instant replenishment or enlarged margin allowance was introduced.

Development cases: seeds **71, 7919, 104729**, plus **CurrentBX, Older, Aged** saved worlds. Each arm forks the same checkpoint, adapts for 20 simulated minutes, then measures 60 minutes in BX/BT/BG: **18 market-hours per arm, 72 total across 24 unique benchmark runs**. The archived seed and Older/Aged snapshots are v27/Momentum1 states restored under verified installed v28/Momentum2 code, with ordinary scheduled adoption during adaptation. They are not represented as newly warmed worlds under v2. CurrentBX already contains the installed policy. Older/Aged share saved-world lineage and are not independent random seeds.

Separate validation was reserved for seeds **42017, 88069** and **CurrentBXLater, AgedLater**; it is conditional on a development pass. No arm passed. Those holdouts were not used, extended or retuned against. Full native regression, native parity and no-recovery endurance promotion stages were consequently not run. No unseen-validation or indefinite funding success is claimed.

## Measurements and full development results

The principal leg detector reverses only after close retracement of **max(6 ticks, 0.025% of the extreme price, 20% of the preceding leg)**. Dojis and tiny flickers cannot end a leg. Quiet minutes inside an established leg count toward its duration. Boundary legs are truncated by the observation window; these durations are descriptive, not survival estimates. A meaningful counter-move can become a full reversal; it is not automatically a completed pullback.

Strict completed pullbacks separately require a preceding three-minute move of at least 12 ticks, the same minimum 6-tick/0.025%/20% retracement, then recovery within eight minutes without overlapping events. This descriptive metric was added during analysis and did not change selection gates. The legacy two-tick/15% pullback count is also reported, clearly labeled. Four-candle alternation is a barcode diagnostic, not a success score. Volatility is square-root summed squared log returns over the measured hour; it is not annualized. Range uses two disjoint windows of 30 completed one-minute candles. **0.7–1.5% remains a soft target, not an installation cutoff.**

| Measure | Installed baseline | Momentum re-entry gate | Longer Value memory | Combined |
|---|---:|---:|---:|---:|
| Candles in meaningful legs of 8+ minutes (%) | 90.9 | 92.4 | 71.8 | 74.3 |
| Mean longest meaningful leg (minutes) | 21.83 | 33.44 | 26.22 | 24.33 |
| Meaningful counter-moves (total) | 67 | 47 | 105 | 87 |
| Strict completed pullbacks (total) | 2 | 1 | 7 | 4 |
| Legacy completed pullbacks (total) | 18 | 31 | 66 | 51 |
| Mean longest candle-color streak | 12.50 | 11.06 | 6.06 | 5.89 |
| One-minute realized volatility (%) | 0.257 | 0.193 | 0.137 | 0.110 |
| 15-second midpoint volatility (%) | 0.171 | 0.132 | 0.100 | 0.085 |
| One-second realized volatility (%) | 0.373 | 0.328 | 0.324 | 0.299 |
| Mean minute high-low range (%) | 0.036 | 0.027 | 0.022 | 0.019 |
| Mean 30-minute range (%) | 0.430 | 0.320 | 0.147 | 0.121 |
| Target 30-minute windows (of 36) | 2 | 0 | 0 | 0 |
| Mean p95 spread (ticks) | 4.06 | 3.78 | 3.94 | 4.00 |
| Missing-side sample fraction (%) | 0.0000 | 0.0031 | 0.0000 | 0.0015 |
| Four-candle alternation fraction (%) | 0.78 | 1.46 | 3.02 | 3.61 |
| Matched contracts (total) | 280,606 | 205,654 | 205,821 | 167,196 |
| Recovery transfers ($) | 2,518,165.01 | 1,087,042.49 | 601,552.50 | 22,510.00 |


| Measure: CurrentBX / BX | Installed baseline | Momentum re-entry gate | Longer Value memory | Combined |
|---|---:|---:|---:|---:|
| Long-leg occupancy (%) | 91.667 | 100.000 | 53.333 | 76.667 |
| Longest meaningful leg (minutes) | 28.000 | 25.000 | 14.000 | 20.000 |
| Meaningful counter-moves | 3.000 | 3.000 | 8.000 | 7.000 |
| Strict completed pullbacks | 0.000 | 0.000 | 0.000 | 0.000 |
| Minute volatility (%) | 0.399 | 0.225 | 0.177 | 0.127 |
| Mean 30-minute range (%) | 0.817 | 0.345 | 0.194 | 0.169 |


The frozen development gates reject all three arms:

- **episode**: failed MeaningfulLong8, MeaningfulMaxLeg, Directional10WindowFraction, MeaningfulCounters, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV, CaseWins, CurrentBX.
- **value-memory**: failed MeaningfulMaxLeg, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV.
- **combined**: failed MeaningfulLong8, MeaningfulMaxLeg, MeaningfulCounters, OneMinuteRV, MeanMinuteRangePercent, FifteenSecondMidpointRV.

The re-entry gate reduces trading and recovery transfers but leaves longer, quieter directional legs. Longer Value memory improves many color and reversal counts, including current BX, but suppresses minute-level movement and 30-minute range sharply. Combining the changes does not restore that lost movement. Lower recovery funding is useful, but it does not establish the requested candle shape at a useful scale. Longest meaningful legs can persist through the smaller oscillations that make color statistics look better.

All paired charts use actual matching-engine OHLC and shared vertical scales within each baseline/candidate pair. Inspection of the current BX and seed charts confirms the tradeoff: the gate-only arm retains smooth ramps; Value-memory arms produce much smaller excursions, with remaining flat stretches and occasional smooth ramps. This is not a validated replacement for the original behavior. [Current BX: all four arms on one scale](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/CurrentBX-four-arms.png>).

- episode: [BX](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-episode-BX.png>), [BT](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-episode-BT.png>), [BG](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-episode-BG.png>)
- value-memory: [BX](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-value-memory-BX.png>), [BT](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-value-memory-BT.png>), [BG](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-value-memory-BG.png>)
- combined: [BX](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-combined-BX.png>), [BT](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-combined-BT.png>), [BG](<C:/Users/drews/Development/Roblox Dev/Get Funded!/output/feedback-20261021/development-combined-BG.png>)

## Safety, limits and reproducibility

Every completed benchmark passes exchange accounting/zero-net-inventory audits and a serialized full-state checkpoint branch continued for another **80 steps**. Every recorded terminal bot has positive equity. These funded runs retain ordinary recovery; reduced transfer totals do not prove operation without recovery. Transfer totals above exclude the adaptation interval. No altered safeguard is used to obtain the results. The Momentum gate and combined arm each pass **17 focused local tests**, including symmetric re-entry blocking, substantial-retracement rearming and time-exit priority, plus the existing matching/risk/continuation fixtures. Native Studio tests were not run for rejected candidates.

This study does not isolate every interacting source of directional feedback, prove future safety outside the measured interval, or justify reducing safeguards. Reserve quoting remains a plausible contributing mechanism requiring a separate causal test; slot observations alone are not enough to select a new policy. There is no demonstrated strategy change ready for Studio.

Evidence: `baseline-verification.json`, `final-studio-readback.json`, `experiment.json`, frozen `variants/*/manifest.json`, `development-*-metrics.json`, raw `development-*/` results, `instrumentation-parity.json`, `decision.json` and the charts above. Actual exported source is in `original/server/` and `original/shared/`.

From the workspace root, rerun `python -X utf8 output/feedback-20261021/run_batch.py development` (cached completed results are retained; use a copied lab with result files removed to force fresh runs). Run `run_traces.py` for the baseline traces/control and `finalize.py` to recompute metrics, verify source manifests/parity and render comparisons. Do not rerun `setup.py` over an existing completed lab: it is initial scaffolding and copies the earlier harness. The local Lune harness executes actual exported Luau orders and accounting; it does not synthesize price paths.
