from pathlib import Path
import json

p=Path(__file__).resolve().parent
s=json.loads((p/'comparison-summary.json').read_text(encoding='utf8'))
b,c=s['Aggregate']['Baseline'],s['Aggregate']['Candidate']
rows=[]
for case in ['Seed71','Seed7919','Seed104729','Current','Older','Aged']:
    records={arm:json.loads((p/'results'/f'{case}-{arm}.json').read_text(encoding='utf8')) for arm in ('Baseline','Candidate')}
    cells=[]
    for key in ('BX','BT','BG'):
        cells.append(f"{records['Baseline']['Markets'][key]['RangePercent']:.3f}% → {records['Candidate']['Markets'][key]['RangePercent']:.3f}%")
    rec=[records[a]['Final']['Recovered']-records[a]['Initial']['Recovered']for a in ('Baseline','Candidate')]
    rows.append('| '+case+' | '+' | '.join(cells)+f' | {rec[0]} → {rec[1]} |')
report=f'''# Momentum implementation and comparison — October 21, 2026

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
| Mean 30-minute high–low range / first open | {b['MeanRange']:.3f}% | {c['MeanRange']:.3f}% |
| Windows within 0.7–1.5% | {b['InTarget']}/18 | {c['InTarget']}/18 |
| Mean close-return sign-flip rate | {b['MeanFlip']*100:.1f}% | {c['MeanFlip']*100:.1f}% |
| Mean path length / high–low range | {b['MeanChop']:.3f} | {c['MeanChop']:.3f} |
| Mean per-window p95 spread, ticks | {b['MeanSpreadP95']:.3f} | {c['MeanSpreadP95']:.3f} |
| Missing two-sided quotes, sample fraction | {b['MeanMissing']*100:.4f}% | {c['MeanMissing']*100:.4f}% |
| Momentum aggressive filled contracts | {b['MomentumAggressorVolume']:,} | {c['MomentumAggressorVolume']:,} |
| Recovery events | {b['Recoveries']} | {c['Recoveries']} |
| Conserved recovery transfers | ${b['Transfers']:,.2f} | ${c['Transfers']:,.2f} |

Recovery transfers decreased {(1-c['Transfers']/b['Transfers'])*100:.1f}%; recovery events decreased {(1-c['Recoveries']/b['Recoveries'])*100:.1f}%. Momentum turnover roughly halved. More close-return sign changes do not establish a reduction in barcode behavior; their increase accompanies a lower path/range ratio and may reflect more pullbacks. No claim of statistical significance is made.

Momentum aggregate realized P&L changed by ${b['MomentumRealizedChange']:,.2f} on baseline versus ${c['MomentumRealizedChange']:,.2f} on the candidate. Equity change excluding net recovery transfers was ${b['MomentumEquityChangeExTransfers']:,.2f} versus ${c['MomentumEquityChangeExTransfers']:,.2f}. The candidate's lower profit extraction is a trade-off, alongside lower redistribution and turnover, rather than an unqualified profitability improvement.

| Starting state | BX range, baseline → candidate | BT range | BG range | Recovery events |
|---|---:|---:|---:|---:|
{chr(10).join(rows)}

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
'''
(p/'RESULTS.md').write_text(report,encoding='utf8')
print('Wrote',p/'RESULTS.md')
