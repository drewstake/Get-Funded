# Reversion implementation and comparison

**Implemented in the isolated lab, not applied to Studio.** Four Reversion variants were compared with the current Momentum and Whale simulation. None reliably shortened long same-color candle runs or increased completed pullbacks. More active versions raised losses without fixing the smooth waves. The existing Studio game remains the safer baseline.

## What was implemented

The existing Reversion strategy uses a 30-second observed-price mean and requires an actual countertrend turn before new entries. The new `candidate/BotReversion.luau` permits a small fade while a stretched move is still continuing but losing speed. It does not require an opposite-color candle first. It changes the behavior of the existing 108 Reversion agents; it adds no bot population or capital.

Each agent has a deterministic private profile and RNG: an independent price lookback, extension threshold, slowdown window, holding time, aggression and cooldown. Signals use only public executed prices and executable best quotes. Histories are sampled on simulation time and bounded. Flat prices, accelerating moves, stale history, missing quotes, wide spreads and already-completed sharp reversals cannot create entries.

Entries use finite funded limits, either passive at the touch or immediately marketable with a two-tick slippage cap. An unfilled aggressive remainder is canceled; a passive entry expires after 4–10 seconds. The strategy caps new positions by account limits, existing margin policy, its inventory ceiling and a 0.5% equity risk budget at the configured stop distance. That budget is not a guaranteed maximum loss through gaps. It never adds to a held position or averages down. Partial passive fills cancel remaining entry quantity at the next observation.

Profit exits rest as real position-linked reduce-only orders. Holding deadlines and strategy-capacity reductions use paced, price-capped reduce-only orders. Existing manual exits share the closing inventory budget. Existing/manual stops and targets, including explicit manual stop removal, are preserved; an inherited unprotected position receives a stop. Triggered protection, account liquidation, drawdown pauses and existing exit retries retain authority. Closing a position starts a staggered cooldown rather than immediately reversing it.

The initial policy uses 45–180-second lookbacks, 6–16-tick extension thresholds, 45–150-second holding periods and the existing ordinary-trader schedule. The earlier-entry variant lowers extension/slowing requirements and shortens holds/cooldowns. The faster-review variant retains the stricter signal, reviews every approximately 3–8 seconds with individual jitter, and allows up to twice ordinary order size within the same risk budget. The final variant also uses 30–100-second lookbacks and 8–16-tick stops. It preserves existing stops; tighter stops apply to new unprotected positions. These are exploratory variants, not four installed policies.

## Experiment

Baseline: actual Studio export, checkpoint v27, Momentum v1, Whale v1, news disabled, and the rejected Maker candidate absent. All 105 exported modules matched the previous verified baseline. The local `src/` tree was not used as authoritative code.

Paired cases: seeds 71, 7919 and 104729, plus Current, Older and Aged saved worlds. Current was captured at step 10440915. Older and Aged originate from checkpoint versions 24 and 19 and were previously normalized through the same current Momentum and Whale code. Every arm forks the identical corresponding checkpoint. Fresh-seed snapshots include 30 minutes of baseline warmup.

Each run then allows 20 minutes of adaptation, aligns to a minute boundary, and measures 60 simulated minutes in BX, BT and BG. That gives 18 market-hours and 36 non-overlapping 30-minute range windows per version. The six baseline runs are reused for all four variants. All matching, stops, funding checks, accounting and checkpoint encoding are the actual exported Luau implementations.

The largest candle streak is measured within each 60-minute trace, using candle body color; dojis break a streak. A completed pullback requires a prior three-minute move of at least four ticks, a retracement of at least two ticks or 15% of that move, and recovery of the prior extreme within eight minutes. Events do not overlap. This deliberately excludes a large permanent reversal and tiny bid/ask alternation. Rendered candles supplement that specific event definition.

## Results

| Version | Mean largest streak in candles | Completed pullbacks per market-hour | Mean 30-minute range | One-second realized volatility over an hour | Reversion equity change excluding transfers | Total recovery transfers |
|---|---:|---:|---:|---:|---:|---:|
| Momentum and Whale baseline | 19.94 | 0.333 | 0.558% | 0.297% | -650,822.50 | 4,477,580.03 |
| Initial Reversion | 19.94 | 0.222 | 0.466% | 0.254% | -720,722.50 | 5,012,604.99 |
| Earlier entries | 22.00 | 0.278 | 0.498% | 0.265% | -1,370,477.50 | 3,832,667.52 |
| Faster reviews | 21.50 | 0.333 | 0.546% | 0.272% | -1,549,855.00 | 7,008,879.90 |
| Shorter horizons and tighter stops | 22.00 | 0.333 | 0.521% | 0.289% | -1,600,005.00 | 7,097,514.89 |

The initial candidate left the mean largest streak unchanged at 19.94 candles. The more active variants increased it to 21.5–22 candles. The initial version produced four completed pullbacks across the 18 market-hours versus six baseline; the later variants produced five or six. Candle sign flips sometimes increased, but that did not translate into useful pullbacks inside the longer swings.

The baseline reached the 0.7–1.5% range target in 13 of 36 windows. The initial, earlier-entry, faster-review and tighter-stop versions reached it in 6, 6, 7 and 9 windows respectively. All retained a lower mean range than baseline. The tuning target was never imposed on prices.

Four-candle alternating patterns remained uncommon. The rejection is not because the candidates created barcode candles: they generally retained the smooth-wave problem while changing its amplitude, timing or losses. The initial version lost about 11% more Reversion equity; the more active versions lost approximately 111–146% more. Recovery transfers varied across versions, so lower transfers alone would have been a misleading acceptance criterion.

The comparisons are exploratory, with four variants evaluated on the same cases. No candidate qualified for the preplanned independent holdout validation or installation. These results do not prove that every possible Reversion design fails; they do reject these implementations as a demonstrated fix for the pictured price action.

## Funding without recovery transfers

The initial candidate and baseline were also compared on seed 71 and Current with 20 minutes of adaptation followed by 90 measured minutes. Only the isolated lab's `BotParticipation.Rebalance` transfer operation was disabled. Drawdown pauses, liquidation, margin, stops, exit scheduling and all other safeguards remained active. No new money was introduced.

| Case | Arm | Reversion equity change | Reversion agents above drawdown floor at end | Matched volume in successive 30-minute blocks |
|---|---|---:|---:|---|
| Current | Baseline | -197,955.00 | 107 / 108 | 23,701, 26,150, 25,235 |
| Current | Candidate | -365,490.00 | 108 / 108 | 27,253, 26,604, 25,391 |
| Seed71 | Baseline | -164,460.00 | 108 / 108 | 23,454, 21,731, 20,210 |
| Seed71 | Candidate | -224,935.00 | 108 / 108 | 21,183, 21,115, 24,213 |

All 108 Reversion agents in each run retained positive equity. Candidate Reversion agents all remained above their drawdown floor, and genuine matched volume continued in every block with zero recovery transfers. However, candidate Reversion losses were higher in both cases. This finite test supports funded operation over the measured interval, not indefinite profitability or sustainability. The other variants failed the price-action comparison and were not promoted to this additional endurance stage.

## Safeguards and checkpoint verification

The baseline native Studio suite passed 246 checks. The initial candidate passed 261, including 15 new Reversion checks. Both retained exactly 38 existing failures: 37 obsolete TradeLimitsTests fixtures and one SecurityTests out-of-collar fixture. No new failure or suite crash was introduced. The legacy BotSignalsTests fixture explicitly selects the old Reversion path, while the new tests exercise the changed behavior.

The focused checks cover symmetric slowdown entry before reversal, rejection of flat/accelerating/stale signals, bounded sampling, independent profiles without shared RNG draws, funded risk limits, no pyramiding, delayed passive-entry replacement, unobserved partial fills, real profit and timed exits, manual protection preservation, blocked accounts, read-only migration, policy downgrade refusal, and replay of pending, partial, holding and reducing states. A specific case covers a passive entry filled and stopped between two strategy decisions. Faster-review and tighter-stop variants also passed these 15 checks locally. A final guard also verifies that adopting an explicitly removed manual stop does not recreate it. The benchmark starting positions contain no Reversion manual-stop overrides, and the simulation does not create such overrides, so this guard does not change those trajectories. Profile-diversity buckets are normalized to the configured range so shorter lookbacks are tested on the same relative spread.

Every completed comparison and endurance run passed accounting, zero-net-inventory, volume and FIFO audits. Every run also serialized its terminal state, restored it, and compared the entire checkpoint after 80 more steps. The initial candidate additionally matched native Studio and the local Luau harness exactly after 400 steps: trade hash 712108189 and zero full-state differences. Only empty JSON object/array representation is normalized in that cross-runtime comparison; numerical state is compared exactly.

The proposed checkpoint v28 stores Reversion history, profiles, RNG, position identity and execution/cooldown clocks. Restoring v27 changes policy metadata only; it does not execute trades, transfer funds, or replace positions and orders. Downgrades fail closed. No v28 Reversion checkpoint was written to the live game.

## Decision and next diagnostic

Keep the current Momentum and Whale simulation in Studio. Reversion can now initiate bounded countertrend trades in the lab, but these tests do not support installing it as a fix for the smooth price waves. The original hypothesis that this missing behavior alone would materially improve the chart was not supported.

The next useful diagnostic is a controlled interaction test of Momentum entry persistence and inventory exits against price-following liquidity, with Reversion as one factor. That is a hypothesis about the remaining cause, not an established attribution. It should preserve all safeguards and funded matching, and evaluate the same streak/pullback metrics and unseen starting states before any gameplay change.

## Artifacts and reproduction

- `candidate/` contains the initial implementation; `variants/` contains the other three designs. None is marked for installation.
- `reversion.patch` records the initial candidate against the actual Studio export. `candidate-manifest.json` and each variant's `manifest.json` record source hashes.
- `results/`, `results-earlier/`, `results-responsive/`, `results-tight-risk/` contain the paired raw results and actual candles. `no-recycling/` contains the additional funding probe.
- `analyze.py` defines the metrics. `experiment.json` records the experiment design. `suites/`, `suite-comparison.json` and `runtime-parity.json` contain the verification evidence.
- Reproduce the baseline/initial comparison from the workspace root with `python output/reversion-20261021/run_comparison.py`, then `python output/reversion-20261021/analyze.py`.
- The other comparison runners are `run_earlier.py`, `run_responsive.py` and `run_tight_risk.py`. `run_no_recycling.py` performs the initial-candidate funding comparison.

The BX candle comparisons show every seed and saved-world case, not just favorable examples. BT and BG images are saved alongside them. Each pair has the same vertical scale and is rebased to its own first measured open; these are actual simulated OHLC candles, not generated price paths.

[Initial Reversion versus baseline candles](C:/Users/drews/Development/Roblox Dev/Get Funded!/output/reversion-20261021/results-BX.png)

[Shorter-horizon tighter-stop variant versus baseline candles](C:/Users/drews/Development/Roblox Dev/Get Funded!/output/reversion-20261021/results-tight-risk-BX.png)

Final source readback confirmed all 105 live modules unchanged, checkpoint v27, Momentum v1, Whale v1 and news disabled. Reversion is absent from the live source. Temporary detached Studio test modules were removed after verification; Play was left running. No game publication or Reversion checkpoint write was performed. See `baseline-verification.json`.
