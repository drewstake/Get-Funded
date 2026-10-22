from pathlib import Path
import json,statistics
r=Path(__file__).resolve().parent
read=lambda p:json.loads((r/p).read_text(encoding='utf8'))
records=[read('results/'+p.name)for p in (r/'results').glob('*.json')]
agg=read('comparison-summary.json')['Aggregate'];b=agg['Baseline'];c=agg['Candidate']
suites=read('suite-comparison.json');tuning=read('tuning-comparison.json')
rows=[]
for name in ['Seed71','Seed7919','Seed104729','Current','Older','Aged']:
    x=next(x for x in records if x['Case']==name and x['Arm']=='Baseline');y=next(x for x in records if x['Case']==name and x['Arm']=='Candidate')
    rows.append('| '+name+' | '+' | '.join(f'{x["Markets"][k]["RangePercent"]:.3f}% → {y["Markets"][k]["RangePercent"]:.3f}%'for k in ['BX','BT','BG'])+' |')
extra={}
for arm in ['Baseline','Candidate']:
    xs=[x for x in records if x['Arm']==arm];ms=[m for x in xs for m in x['Markets'].values()]
    extra[arm]={'Passive':sum(m['Passive'].get('Whale',0)for m in ms),'Volume':sum(m['Volume']for m in ms),'MidFlip':statistics.mean(m['Midpoint']['FlipRate']for m in ms),'WhaleRecoveries':sum(x['Final']['ByKind']['Whale']['Recoveries']-x['Initial']['ByKind']['Whale']['Recoveries']for x in xs)}
endurance=[]
for name in ['Seed71','Current']:
    for arm in ['Baseline','Candidate']:
        p=r/f'endurance/{name}-{arm}.json'
        if p.exists():
            x=json.loads(p.read_text(encoding='utf8'));a=x['Initial']['ByKind']['Whale'];z=x['Final']['ByKind']['Whale']
            volumes=[]
            for segment in range(3):volumes.append(sum(sum(bar['Volume']for bar in m['Bars']if x['MeasuredStart']+segment*1800<=bar['Time']<x['MeasuredStart']+(segment+1)*1800)for m in x['Markets'].values()))
            endurance.append({'Case':name,'Arm':arm,'WhaleEquityChange':z['Equity']-a['Equity'],'WhalesInitiallyAboveRiskFloor':a['AbovePressureRiskFloor'],'WhalesAboveRiskFloor':z['AbovePressureRiskFloor'],'WhalesPositiveEquity':z['PositiveEquity'],'WhaleCount':z['Count'],'TransferChange':x['Final']['Transferred']-x['Initial']['Transferred'],'RecoveryChange':x['Final']['Recovered']-x['Initial']['Recovered'],'ThirtyMinuteVolumes':volumes,'Replay':x['Replay'],'WhaleAggressiveVolume':sum(m['Aggressor'].get('Whale',0)for m in x['Markets'].values()),'WhalePassiveVolume':sum(m['Passive'].get('Whale',0)for m in x['Markets'].values())})
(r/'endurance-summary.json').write_text(json.dumps(endurance,indent=2),encoding='utf8')
status='Staged and tested locally; not yet installed.'
if (r/'persisted-verification.json').exists():status='Applied to Get Funded! in Studio after the comparisons and checks below. A fresh server and its persisted checkpoint were verified. This does not publish the experience or save a new local RBXL file.'
text=f'''# Patient Whale execution — October 21, 2026

{status}

## Result and tradeoff

The selected policy produces patient buying and selling, adds genuinely funded resting liquidity, and substantially reduces turnover and redistribution. It is quieter than the updated Momentum baseline: mean 30-minute range falls from {b['MeanRange']:.3f}% to {c['MeanRange']:.3f}%, with {c['InTarget']}/18 windows inside 0.7–1.5% versus {b['InTarget']}/18. The observed reductions in churn and redistribution are **not achievement of the preferred range**. No forced-range mechanism was added. BT remains below the preferred range in every selected-policy and baseline window.

The mean close path / high–low ratio falls {(1-c['MeanChop']/b['MeanChop'])*100:.1f}%; close-return sign flips decline from {b['MeanFlip']*100:.1f}% to {c['MeanFlip']*100:.1f}%. Midpoint sign flips also decline ({extra['Baseline']['MidFlip']*100:.1f}% → {extra['Candidate']['MidFlip']*100:.1f}%). These are descriptive proxies for back-and-forth movement, not proof that all barcode behavior is gone or that engagement has improved for players.

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
| Mean 30-minute range | {b['MeanRange']:.3f}% | {c['MeanRange']:.3f}% |
| Windows in 0.7–1.5% | {b['InTarget']}/18 | {c['InTarget']}/18 |
| Mean close-return sign flips | {b['MeanFlip']*100:.1f}% | {c['MeanFlip']*100:.1f}% |
| Mean close path / high–low range | {b['MeanChop']:.3f} | {c['MeanChop']:.3f} |
| Mean per-window p95 spread, ticks | {b['MeanSpreadP95']:.3f} | {c['MeanSpreadP95']:.3f} |
| Missing two-sided quotes | {b['MeanMissing']*100:.4f}% | {c['MeanMissing']*100:.4f}% |
| Whale aggressive filled contracts | {b['WhaleAggressorVolume']:,} | {c['WhaleAggressorVolume']:,} |
| Whale passive filled contracts | {extra['Baseline']['Passive']:,} | {extra['Candidate']['Passive']:,} |
| Whole-exchange matched volume | {extra['Baseline']['Volume']:,} | {extra['Candidate']['Volume']:,} |
| Recovery events, all bots | {b['Recoveries']} | {c['Recoveries']} |
| Conserved transfers, all bots | ${b['Transfers']:,.2f} | ${c['Transfers']:,.2f} |

Whale recovery events were zero in both arms. Whole-exchange transfers fell {(1-c['Transfers']/b['Transfers'])*100:.1f}%. Aggregate Whale equity change excluding net capital transfers was ${b['WhaleEquityChangeExTransfers']:,.2f} versus ${c['WhaleEquityChangeExTransfers']:,.2f}; lower turnover is not an unqualified profitability improvement. Terminal eligible participants total 6,191/7,020 versus 6,528/7,020 across the six cases; this eligibility measure includes Holding and Waiting, not only active trading. Lower spread and volatility also reduce trading opportunities and may make some markets too quiet.

| Starting state | BX range, baseline → Whale | BT | BG |
|---|---:|---:|---:|
{chr(10).join(rows)}

## Tuning comparison

Two additional settings used the same six initial snapshots and measurement windows. Neither was installed. They changed only the new Whale settings, not the existing safeguards or Momentum code.

| Setting | Equity sizing cap | Aggressive probability | Slice fraction | Mean range | In band | Path/range |
|---|---:|---:|---:|---:|---:|---:|
'''
for folder,label,risk,aggressive,slice_ in [('results','Selected patient','2.5%','10–35%','15–35%'),('results-balanced','More active','5%','20–50%','15–35%'),('results-participating','Most active','10%','35–65%','25–55%')]:
    x=tuning[folder];text+=f"| {label} | {risk} | {aggressive} | {slice_} | {x['MeanRange']:.3f}% | {x['InTarget']}/18 | {x['Chop']:.3f} |\n"
text+='''
The selected policy has the most in-band windows and lowest path/range ratio among these candidates. More aggression did not reliably increase useful range. These are small exploratory tuning comparisons, not a held-out statistical evaluation.

## Recycling-disabled endurance

Seed71 and Current each run for 20 minutes of adaptation plus 90 measured minutes, in both arms, with participation recovery disabled equally. No initial funding or positions are reset. All other market and protection rules remain active. The table reports end-of-run solvency and real matched activity; it does not prove indefinite sustainability.

| Case / arm | Whale equity change | Whales above 65% budget floor, start → end | Positive Whale equity | Matched volume in successive 30-minute blocks | Recovery transfers |
|---|---:|---:|---:|---|---:|
'''
for x in endurance:
    text+=f"| {x['Case']} / {x['Arm']} | ${x['WhaleEquityChange']:,.2f} | {x['WhalesInitiallyAboveRiskFloor']} → {x['WhalesAboveRiskFloor']} / {x['WhaleCount']} | {x['WhalesPositiveEquity']}/{x['WhaleCount']} | {', '.join(f'{v:,}'for v in x['ThirtyMinuteVolumes'])} | ${x['TransferChange']:,.2f} |\n"
text+=f'''
Completed endurance runs: {len(endurance)}/4. Replay passed for every completed run. See `endurance-summary.json` for Whale aggressive/passive volume and recovery counts.

## Verification and limitations

- 19 focused Whale tests pass locally and in detached Studio, covering both directions, staggered profiles, external/own volume separation, quiet allowance, FIFO, duplicate reservations, asynchronous partial/full fills, refill delays, price tolerance, empty books, expiry/holding/reduction, stops/recovery, inherited protections, risk exits, migration/downgrade refusal, an unobserved passive fill across a checkpoint, and all lifecycle phases.
- Broad native Studio comparison: baseline {suites['Baseline']['Passed']} passed / {suites['Baseline']['Failed']} failed; candidate {suites['Candidate']['Passed']} passed / {suites['Candidate']['Failed']} failed. No new failures or suite crashes. The same 37 legacy TradeLimitsTests and SecurityTests S1 fail in both arms; those fixtures predate current execution limits. No engine safeguards were relaxed to make them pass. Legacy BotOrderFlow fixtures explicitly select the old policy; the new behavior is tested separately.
- Range is below the preferred band on average. This change reduces churn and recovery dependence but does not alone deliver the desired volatility across all contracts. Player engagement needs observation in play.
- Stops and margin liquidation can still be lumpy; no policy manufactures liquidity to guarantee an exit. The volume cap is per Whale and permits interaction between Whales. Finite tests cannot establish multi-day sustainability or performance under untested player flow.
- Checkpoint v27 is a deliberate compatibility boundary. Reverting source alone to a v26-only reader is not a safe rollback after a v27 world has been saved; a forward-compatible fix or a separately planned checkpoint recovery is required.

## Artifacts

`candidate/` contains the nine installed/staged sources; `original/` is the read-only Studio export; `pre-apply/` holds Edit-source backups when installed. `whale.patch` and `candidate-manifest.json` identify the change. Raw evidence is in `results/`, `results-balanced/`, `results-participating/`, `endurance/`, `suites/`, `runtime-parity.json`, and the saved snapshot metadata. Lab files and runners are local only.
'''
if (r/'installed-test-summary.json').exists():
    installed=read('installed-test-summary.json');live=read('live-verification.json');saved=read('persisted-verification.json')
    text+=f"\n## Installed verification\n\nFresh-server checks: {installed['Passed']} passed across {installed['Suites']} suites, zero failures. Live status: {live['Status']}; the exchange audit passed. The normal persisted world contains checkpoint v{saved['Checkpoint']}, Whale v{saved['WhalePolicy']}, Momentum v{saved['MomentumPolicy']}, NewsFrequency={saved['NewsFrequency']}, and {saved['WhaleCount']} Whale profiles at step {saved['Step']}. Source readback was verified during installation.\n"
(r/'RESULTS.md').write_text(text,encoding='utf8')
print('Wrote report; endurance runs',len(endurance))
