# Momentum implementation and comparison — October 21, 2026

Applied to Get Funded! in Roblox Studio after the comparisons below. The restarted Studio server is Shared/Saved, and a read-only check of its persisted world confirms checkpoint v26, Momentum policy v1, NewsFrequency=0, and 108 Momentum profiles. Live cohorts contain 34/39/35 bots; styles contain 81 trend followers and 27 breakout traders. This changes Studio source; it does not publish the experience or save a new local RBXL file.

## Implementation

- New `BotMomentum` handles Momentum exclusively. Whale still executes the original `BotOrderFlow` path. No population or capital allocations change.
- Stable per-bot 1–3, 3–8, and 8–20 minute horizons; approximately 25% breakout profiles. Profiles and execution randomness use saved per-agent RNG state without drawing from the shared profile RNG.
- Public executed-price observations every five simulated seconds, bounded to 1,220 seconds. Signals require complete, fresh history and a move large enough for spread/slippage costs and observed volatility. Breakouts compare against the completed observation range preceding the confirmation interval.
- Building, Holding, Reducing and Waiting phases. Child quantities are paced over 90–240 seconds, reserve ordinary funded exposure, cap entry prices three ticks beyond the touch and cancel their residuals. Existing protective orders retain authority.
- Entry targets use 35–65% of funded capacity, additionally capped by a 2.5% equity stop-distance budget. This is sizing, not a guarantee against slippage losses.
- Hold horizons vary with profile horizon, between 3 and 30 minutes. Sustained opposite signals, failed breakouts, time limits, capacity reduction, drawdown and existing stops control exits. Favorable movement can tighten a stop; existing/manual protection is never loosened. Voluntary closes require matched reduce-only orders and a cooldown before another entry.
- Checkpoint v26 stores profile RNG, phase, timing and sampled history. V25 and earlier migrate policy without executing trades, cancelling orders or changing ledgers during restore. Legacy entry intent is cancelled only at the bot's next ordinary decision; positions and reduce-only exits survive. Older readers reject v26 rather than silently discard state.
- `MarketEngine`, margin/exposure calculations, player execution, protections, capital recovery, Maker/Reserve liquidity, and the other trader implementations are unchanged. News remains disabled; no target-price or forced-range mechanism was added.

## Experiment

Six paired cases, 12 runs: fresh seeds 71, 7919 and 104729 plus three actual persisted Studio worlds (original checkpoint versions 25, 24 and 19). Older worlds received the same existing baseline migrations before either arm branched. Saved RNG states were retained, not reseeded.

Fresh seed histories were produced with the baseline for 30 minutes. Each arm then ran for at least 20 minutes of adaptation, aligned to a minute boundary, followed by 30 measured one-minute candles. Both arms used identical starting snapshots, population, funding and unrelated settings. No owner refresh or artificial funding was used. The normal conserved recovery mechanism remained enabled and was measured.

Bulk execution used the unchanged exported Luau sources in a separate Lune process. Before accepting results, the candidate's full checkpoint after 400 steps matched a Studio execution from the same snapshot (only equivalent empty JSON arrays/objects were normalized). The local JSON adapter parses decimal tokens through Luau `tonumber` to avoid an extra ULP from the standalone JSON decoder. This adapter is test infrastructure only.

Every benchmark ended with a real encode/decode/restore followed by 80 paired steps and recursive equality of complete checkpoints, plus exchange accounting audits. All 12 passed.

| Aggregate across 18 market windows per arm | Baseline | Momentum v1 |
|---|---:|---:|
| Mean 30-minute high–low range / first open | 0.895% | 0.835% |
| Windows within 0.7–1.5% | 10/18 | 10/18 |
| Mean close-return sign-flip rate | 12.9% | 16.8% |
| Mean path length / high–low range | 2.593 | 2.393 |
| Mean per-window p95 spread, ticks | 4.889 | 4.778 |
| Missing two-sided quotes, sample fraction | 0.0185% | 0.0062% |
| Momentum aggressive filled contracts | 96,099 | 47,671 |
| Recovery events | 122 | 55 |
| Conserved recovery transfers | $27,955,140.32 | $13,704,180.93 |

Recovery transfers decreased 51.0%; recovery events decreased 54.9%. Momentum turnover roughly halved. More close-return sign changes do not establish a reduction in barcode behavior; their increase accompanies a lower path/range ratio and may reflect more pullbacks. No claim of statistical significance is made.

Momentum aggregate realized P&L changed by $6,981,610.27 on baseline versus $2,546,247.31 on the candidate. Equity change excluding net recovery transfers was $7,989,330.00 versus $2,504,255.00. The candidate's lower profit extraction is a trade-off, alongside lower redistribution and turnover, rather than an unqualified profitability improvement.

| Starting state | BX range, baseline → candidate | BT range | BG range | Recovery events |
|---|---:|---:|---:|---:|
| Seed71 | 1.074% → 0.572% | 0.420% → 0.395% | 0.992% → 1.216% | 28 → 14 |
| Seed7919 | 1.068% → 1.580% | 0.432% → 0.544% | 0.881% → 0.702% | 23 → 10 |
| Seed104729 | 1.084% → 1.082% | 0.399% → 0.475% | 0.781% → 1.009% | 18 → 8 |
| Current | 1.705% → 1.376% | 0.651% → 0.416% | 1.384% → 0.906% | 41 → 13 |
| Older | 0.693% → 0.796% | 0.517% → 0.431% | 0.984% → 1.200% | 6 → 9 |
| Aged | 1.301% → 0.829% | 0.432% → 0.512% | 1.319% → 0.991% | 6 → 1 |

The older saved case increased recovery events from 6 to 9; benefits are not uniform. BT remains below the preferred range in every measured window. Range is a tuning target, never a direction/price controller. One measured window per starting state is evidence for this first iteration, not proof of multi-day sustainability. No recovery-disabled endurance run was performed.

## Verification and known baseline failures

- 14 focused Momentum cases pass in the isolated Studio copy, standalone runner, and installed fresh server. They cover both directions, flat/stale/incomplete history, breakout range exclusion, funded/paced/partial IOC execution, empty entry and exit books, bounded price caps, thesis/time exits, stop cooldown, non-loosening trails, migration preservation, all lifecycle checkpoint phases, and bounded history.
- Existing comparative suites: baseline 206 passed / 39 failed; candidate 207 passed / 38 failed. **No new failures.** The one resolved failure was an obsolete `BotRefreshTests` expectation of checkpoint v24, updated along with the other version assertions to v26.
- The 38 shared failures comprise 37 older `TradeLimitsTests` fixtures and one `SecurityTests` fixture. Some assume historical execution/quote behavior or large test price jumps. They were reproduced on baseline and left outside this strategy change. They are not reported as passes.
- After installation and a fresh Play restart, 97 checks across Momentum, order flow, participation, order-driven pricing, core market, protective orders and execution integrity passed, with zero failures.
- An initial Edit-mode installed check used cached pre-change required modules and failed. That result is retained in `installed-tests-edit-cache.json`; the fresh-server result is `installed-tests.json`.
- Live audit passed: inventory net zero in each market and cash/equity reconciliation within the engine's existing tolerance. The persisted checkpoint contains all 108 Momentum profiles and NewsFrequency=0.

## Files

- `candidate/`: the five strategy/config/checkpoint source changes, the new test module and four checkpoint-version test updates.
- `original/` and `pre-apply/`: source backups. Editor contents were checked against backups before installation to avoid overwriting concurrent changes.
- `results/`, `comparison-summary.json`: individual runs, candle bars and aggregate metrics.
- `suite-comparison.json`, `studio-momentum-tests.json`, `installed-tests.json`: test evidence.
- `runtime-parity.json`, `live-verification.json`, `persisted-verification.json`: standalone parity and installed-world checks.
- `snapshots/`: local copies of the saved-world evidence; never installed into ReplicatedStorage or the game.
- `LocalLab.luau`, `MomentumBenchmark.luau`, `run_comparison.py`: reproducible local comparison harness. Run from the repository root with `python output/momentum-20261021/run_comparison.py`.

The new saved format deliberately fails closed on older readers. Reverting source alone after a v26 checkpoint has been saved is not a compatible rollback.
