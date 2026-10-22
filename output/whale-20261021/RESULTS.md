# Patient Whale execution — October 21, 2026

Applied to Get Funded! in Studio after the comparisons and checks below. A fresh server and its persisted checkpoint were verified. This does not publish the experience or save a new local RBXL file.

## Result and tradeoff

The selected policy produces patient buying and selling, adds genuinely funded resting liquidity, and substantially reduces turnover and redistribution. It is quieter than the updated Momentum baseline: mean 30-minute range falls from 0.882% to 0.602%, with 7/18 windows inside 0.7–1.5% versus 11/18. The observed reductions in churn and redistribution are **not achievement of the preferred range**. No forced-range mechanism was added. BT remains below the preferred range in every selected-policy and baseline window.

The mean close path / high–low ratio falls 45.2%; close-return sign flips decline from 15.5% to 11.3%. Midpoint sign flips also decline (14.8% → 11.7%). These are descriptive proxies for back-and-forth movement, not proof that all barcode behavior is gone or that engagement has improved for players.

## What changed

- `BotWhale` replaces the current Whale branch of `BotOrderFlow`; the old executor remains available for configurations without the new policy. No new trader population is added. Momentum code and policy are unchanged.
- Per-bot deterministic portfolio mandates choose independent sides. Profiles vary build duration (5–15 minutes), subsequent hold duration (3–10 minutes), and planned distribution duration (2–6 minutes). A new opposite position requires a completed, matched close and a 1–3 minute cooldown. Stops use the existing longer cooldown.
- The target remains 45–85% of funded capacity, with an additional 2.5%-of-equity stop-distance sizing cap. The cap sizes a position; it does not guarantee maximum realized loss through gaps or thin liquidity. Existing account/agent limits, half-margin policy, exposure checks, drawdown thresholds, protective stops and zero-sum recovery remain authoritative.
- Each Whale keeps at most one live child. Passive children join the best same-side quote, keep FIFO priority, and expire after a profile-specific 25–60 seconds. Only a sufficiently displaced quote after at least 15 seconds may be cancelled early. Filled, cancelled or expired children wait another 8–20 seconds before replacement.
- The probability of a capped aggressive child rises from 10% to 35% with mandate age. Aggressive children are ordinary matched limits, at most three ticks through the current touch, with the residual cancelled immediately. Entry price tolerance is 0.5–1.5 original stop distances from the arrival print. Favorable prices remain acceptable; a mandate cannot chase beyond its tolerance.
- Both elapsed-time pacing and a 4–10% per-bot share of external matched volume limit voluntary fills. External volume excludes that account's own fills. A separate allowance of one contract initially plus one per 30 simulated seconds permits bounded execution in quiet markets. Other Whales count as external counterparties; this is not an aggregate sector participation cap.
- Outstanding children reserve ordinary funded exposure. Persisted cumulative buy/sell counters reconcile asynchronous fills even after an order leaves the book or the world is restored. Only real fills consume the parent quantity. An incomplete build expires into holding, without a catch-up burst. Voluntary distribution remains reduce-only and can take longer than its planned duration if genuine liquidity is missing.
- Existing risk repair and participation recovery run before the strategy. Risk reductions can bypass the voluntary volume budget. Locked, liquidating, retiring and triggered positions cannot submit fresh entries. Recovery or external position closure invalidates the old mandate.
- Checkpoint v27 saves the Whale profile, private RNG, phase, deadlines, child identity and counter baselines. Restoring an older checkpoint migrates policy without changing orders, inventory, balances or the tape; adoption occurs at the next ordinary decision. Older readers fail closed on v27.
- No changes to `MarketEngine`, `Participants`, `BotMomentum`, margin accounting, player execution, protections, `BotParticipation`, Maker or Reserve behavior. News stays at zero. Prices still move only through the existing matched-order engine.

## Paired experiment

Baseline: the actual Studio export containing Momentum v1 and checkpoint v26. Fresh seeds 71, 7919 and 104729 received 30 minutes of baseline warmup. Three real persisted worlds were also used: Current (v26, step 10202083), Older (v24, step 9886330), and Aged (v19, step 9807944). Existing baseline migrations, including Momentum, were applied equally before branching. Saved worlds retained their saved RNG state.

Each arm received at least 20 minutes of adaptation followed by 30 complete one-minute candles. Population, starting funding and unrelated policy settings were identical. Normal zero-sum recovery stayed enabled and was measured. The six cases yield 18 market windows per arm; the windows and historical saved states are not statistically independent.

Bulk tests ran the exported Luau in Lune using an isolated Roblox-service adapter. A 400-step candidate continuation produced an exactly equal full checkpoint in native Studio (trade hash 923746307), after normalizing only equivalent empty JSON table representations. The adapter is lab code and is not installed in the game.

Each measured run ended with encode/decode/restore, 80 paired continuation steps, recursive full-state equality, and exchange audits. All 12 selected-policy/baseline runs and all 12 additional tuning runs passed. Native Studio safeguard suites were run on detached copies before any installation.

| Metric, 18 windows per arm | Momentum baseline | Selected Whale policy |
|---|---:|---:|
| Mean 30-minute range | 0.882% | 0.602% |
| Windows in 0.7–1.5% | 11/18 | 7/18 |
| Mean close-return sign flips | 15.5% | 11.3% |
| Mean close path / high–low range | 2.413 | 1.323 |
| Mean per-window p95 spread, ticks | 4.833 | 3.333 |
| Missing two-sided quotes | 0.0093% | 0.0031% |
| Whale aggressive filled contracts | 259,004 | 17,203 |
| Whale passive filled contracts | 0 | 15,761 |
| Whole-exchange matched volume | 475,557 | 142,999 |
| Recovery events, all bots | 143 | 38 |
| Conserved transfers, all bots | $26,520,352.83 | $5,699,762.58 |

Whale recovery events were zero in both arms. Whole-exchange transfers fell 78.5%. Aggregate Whale equity change excluding net capital transfers was $29,477,010.00 versus $-1,042,565.00; lower turnover is not an unqualified profitability improvement. Terminal eligible participants total 6,191/7,020 versus 6,528/7,020 across the six cases; this eligibility measure includes Holding and Waiting, not only active trading. Lower spread and volatility also reduce trading opportunities and may make some markets too quiet.

| Starting state | BX range, baseline → Whale | BT | BG |
|---|---:|---:|---:|
| Seed71 | 1.088% → 0.680% | 0.438% → 0.255% | 0.837% → 0.719% |
| Seed7919 | 0.981% → 0.771% | 0.636% → 0.232% | 0.780% → 0.529% |
| Seed104729 | 0.914% → 0.832% | 0.486% → 0.469% | 0.881% → 0.623% |
| Current | 1.365% → 1.277% | 0.513% → 0.305% | 2.207% → 0.629% |
| Older | 0.796% → 0.497% | 0.431% → 0.255% | 1.200% → 0.793% |
| Aged | 0.829% → 0.716% | 0.512% → 0.266% | 0.991% → 0.991% |

## Tuning comparison

Two additional settings used the same six initial snapshots and measurement windows. Neither was installed. They changed only the new Whale settings, not the existing safeguards or Momentum code.

| Setting | Equity sizing cap | Aggressive probability | Slice fraction | Mean range | In band | Path/range |
|---|---:|---:|---:|---:|---:|---:|
| Selected patient | 2.5% | 10–35% | 15–35% | 0.602% | 7/18 | 1.323 |
| More active | 5% | 20–50% | 15–35% | 0.572% | 5/18 | 1.355 |
| Most active | 10% | 35–65% | 25–55% | 0.643% | 4/18 | 1.484 |

The selected policy has the most in-band windows and lowest path/range ratio among these candidates. More aggression did not reliably increase useful range. These are small exploratory tuning comparisons, not a held-out statistical evaluation.

## Recycling-disabled endurance

Seed71 and Current each run for 20 minutes of adaptation plus 90 measured minutes, in both arms, with participation recovery disabled equally. No initial funding or positions are reset. All other market and protection rules remain active. The table reports end-of-run solvency and real matched activity; it does not prove indefinite sustainability.

| Case / arm | Whale equity change | Whales above 65% budget floor, start → end | Positive Whale equity | Matched volume in successive 30-minute blocks | Recovery transfers |
|---|---:|---:|---:|---|---:|
| Seed71 / Baseline | $13,288,685.00 | 36 → 36 / 36 | 36/36 | 74,161, 71,109, 73,540 | $0.00 |
| Seed71 / Candidate | $332,535.00 | 36 → 36 / 36 | 36/36 | 24,636, 21,617, 21,753 | $0.00 |
| Current / Baseline | $12,954,710.00 | 36 → 34 / 36 | 36/36 | 75,654, 81,418, 73,533 | $0.00 |
| Current / Candidate | $276,410.00 | 36 → 36 / 36 | 36/36 | 26,529, 23,888, 25,644 | $0.00 |

Completed endurance runs: 4/4. Replay passed for every completed run. See `endurance-summary.json` for Whale aggressive/passive volume and recovery counts.

## Verification and limitations

- 19 focused Whale tests pass locally and in detached Studio, covering both directions, staggered profiles, external/own volume separation, quiet allowance, FIFO, duplicate reservations, asynchronous partial/full fills, refill delays, price tolerance, empty books, expiry/holding/reduction, stops/recovery, inherited protections, risk exits, migration/downgrade refusal, an unobserved passive fill across a checkpoint, and all lifecycle phases.
- Broad native Studio comparison: baseline 221 passed / 38 failed; candidate 240 passed / 38 failed. No new failures or suite crashes. The same 37 legacy TradeLimitsTests and SecurityTests S1 fail in both arms; those fixtures predate current execution limits. No engine safeguards were relaxed to make them pass. Legacy BotOrderFlow fixtures explicitly select the old policy; the new behavior is tested separately.
- Range is below the preferred band on average. This change reduces churn and recovery dependence but does not alone deliver the desired volatility across all contracts. Player engagement needs observation in play.
- Stops and margin liquidation can still be lumpy; no policy manufactures liquidity to guarantee an exit. The volume cap is per Whale and permits interaction between Whales. Finite tests cannot establish multi-day sustainability or performance under untested player flow.
- Checkpoint v27 is a deliberate compatibility boundary. Reverting source alone to a v26-only reader is not a safe rollback after a v27 world has been saved; a forward-compatible fix or a separately planned checkpoint recovery is required.

## Artifacts

`candidate/` contains the nine installed/staged sources; `original/` is the read-only Studio export; `pre-apply/` holds Edit-source backups when installed. `whale.patch` and `candidate-manifest.json` identify the change. Raw evidence is in `results/`, `results-balanced/`, `results-participating/`, `endurance/`, `suites/`, `runtime-parity.json`, and the saved snapshot metadata. Lab files and runners are local only.

## Installed verification

Fresh-server checks: 111 passed across 8 suites, zero failures. Live status: SHARED · SAVED; the exchange audit passed. The normal persisted world contains checkpoint v27, Whale v1, Momentum v1, NewsFrequency=0, and 36 Whale profiles at step 10271913. Source readback was verified during installation.
