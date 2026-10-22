from pathlib import Path
import json,hashlib,statistics,collections
from metrics import summarize
R=Path(__file__).resolve().parent
names=['reserve-delay','reserve-rest','maker-rest','maker-no-skew','time-exit-size','value-exit-gate','reserve-cost-quote','inventory-delta','no-skew-reserve-delay','sparse-touch','no-skew-sparse-touch','whale-urgency','no-skew-sparse-whale','no-skew-sparse-time','no-skew-sparse30-whale']
results={};funding={};raws={};checks=[]
for name in names:
 d=summarize('development-'+name)
 assert len(d['Markets'])==36,name
 results[name]=d
 (R/('development-'+name+'-metrics.json')).write_text(json.dumps(d,indent=2))
for name in ['baseline']+names:
 arm='Baseline'if name=='baseline'else'Candidate'
 ds=[json.loads(p.read_text())for p in (R/('development-'+name)).glob('*-'+arm+'.json')]
 assert len(ds)==6,(name,len(ds));raws[name]=ds
 funding[name]={k:sum(d['Final']['ByKind'][k]['Equity']-d['Initial']['ByKind'][k]['Equity']-d['Final']['ByKind'][k]['RecoveryNet']+d['Initial']['ByKind'][k]['RecoveryNet']for d in ds)for k in ['Maker','Value','Momentum','Whale','Reserve']}
 for d in ds:
  assert d['Replay'] and all(v==0 for v in d['Audit']['Inventory'].values())
  assert all(k['PositiveEquity']==k['Count']for k in d['Final']['ByKind'].values())
  checks.append({'Variant':name,'Case':d['Case'],'Audit':d['Audit'],'Replay':d['Replay']})
  baseline=next(x for x in raws['baseline']if x['Case']==d['Case'])
  assert d['Start']==baseline['Start']and d['MeasuredStart']==baseline['MeasuredStart']
  assert all(len(m['Bars'])==60 for m in d['Markets'].values())
  if name!='baseline':
   copied=json.loads((R/('development-'+name)/(d['Case']+'-Baseline.json')).read_text())
   assert copied==baseline,(name,d['Case'],'baseline not identical')
passing=[n for n,d in results.items()if d['Pass']]
assert not passing,('Candidate needs separate validation; do not issue rejection report',passing)
readback=json.loads((R/'final-studio-readback.json').read_text());assert readback['AllSourceAndEditorMatch']
assert all(not(R/'snapshots'/('normalized-'+n+'.json')).exists()for n in ['Seed42017','Seed88069','CurrentBXLater','AgedLater'])
for name in names:
 migration=json.loads((R/'migrations'/('CurrentBX-'+name+'.json')).read_text())
 assert all(migration[k]for k in ['EncodedRoundtripExact','EnginePreserved','OldReaderRefused','PopulationPreserved']),name
(R/'all-development-metrics.json').write_text(json.dumps(results,indent=2))
(R/'funding-by-kind.json').write_text(json.dumps(funding,indent=2))
(R/'run-integrity.json').write_text(json.dumps({'UniqueDevelopmentRuns':len(checks),'MeasuredMarketHours':len(checks)*3,'Checks':checks},indent=2))
decision={'Qualified':False,'Installed':False,'Published':False,'StudioSourcesUnchanged':True,'FinalStudioMode':'Edit','HoldoutsUsed':False,'Variants':{n:{'Pass':d['Pass'],'Failed':[k for k,v in d['Gates'].items()if not v]}for n,d in results.items()},'Reason':'No frozen candidate meets all unchanged development shape, movement, liquidity and funding gates. Full native release regression, candidate runtime parity and separate validation were not entered.'}
(R/'decision.json').write_text(json.dumps(decision,indent=2))
base=results[names[0]]['Aggregate']['Baseline']
agg={'baseline':base,**{n:d['Aggregate']['Candidate']for n,d in results.items()}}
def table(headers,rows):return '| '+' | '.join(headers)+' |\n|'+'|'.join(['---']*len(headers))+'|\n'+'\n'.join('| '+' | '.join(str(v)for v in row)+' |'for row in rows)+'\n'
def link(name,label=None):return '['+(label or name)+']('+name+')'
text='''# Candle microstructure investigation — 22 October 2026

**The smooth-leg problem is not solved. No candidate qualifies for installation. Studio sources remain unchanged; nothing was published or saved as an RBXL.** Fourteen frozen interventions were tested over five development rounds. The work found and reproduced a specific inventory/quote feedback mechanism, but removing it or combining the tested changes did not deliver substantial pullbacks with enough useful movement. Better color counts, lower funding transfers and higher aggregate volatility are not treated as a fix.

The final decision is recorded in [decision.json](decision.json). All failed sources, results, logs and charts are preserved. The independent validation cases remain unexamined.

## Baseline, captured world and comparison design

Read the three requested prior reports before testing, plus earlier Maker and Reversion failures. Exported all 105 actual Studio runtime ModuleScripts and compared complete UTF-8/LF-normalized source with the previous verified baseline. All matched: **checkpoint 28, Momentum 2, Maker quote policy 8, Whale 1, news frequency 0**. The local `src/` directory was not assumed authoritative. Final readback also matched all 105 **Edit sources and editor buffers**. Studio changed from Play to Edit during the investigation; the agent did not stop or restart Play and left it in Edit. No DataStore writes were issued.

A read-only Studio-scope capture yielded step **10,932,654**, simulation time **2,733,163.5 seconds**, save sequence **10,065**. Its last 180 completed BX candles had **98.89% meaningful-long-leg occupancy** and a **24-minute maximum leg**. Those historical measurements differ from the forward comparison. The baseline's forward BX hour has 100% occupancy and a 36-minute maximum leg.

Every arm forks the same six snapshots: seeds **71, 7919, 104729**, plus **CurrentBX, Older, Aged** saved worlds. The archived seed and older-world snapshots carry earlier v27/Momentum-1 state and adopt the installed v28/Momentum-2 policy under the normal scheduler; they are not described as newly warmed v28 seeds. Older/Aged share saved-world ancestry. CurrentBX is the new captured world. Each run adapts for 20 simulated minutes, aligns to a minute boundary, then measures 60 completed one-minute candles in BX/BT/BG. Baseline files reused across arms are checked for complete equality.

There are **90 unique development runs, 270 measured market-hours**: six baseline runs and six runs for each of 14 variants. Development is exploratory and reused for successive hypotheses. Each variant was source-frozen before its own runs; no variant was altered after seeing its results. Separate validation was reserved for seeds **42017, 88069** and **CurrentBXLater, AgedLater**. No candidate passed development, so those snapshots were not generated or inspected. No validation result was reused for tuning or enlarged to rescue a failure.

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

All variants are isolated under `variants/`, with SHA256 manifests and `change.patch`. Experimental checkpoint 29 prevents the installed reader from accepting their snapshots. These are research variants, not released policy migrations. Round 3 was chosen from the completed initial four no-skew development cases and the completed six-case Reserve-delay result; all six cases were subsequently completed for every arm. No independent-validation cases entered that choice.

## Measurements and gates

The previous meaningful-retracement measure is retained unchanged: **max(6 ticks, 0.025% of the extreme price, 20% of the preceding leg)**. Dojis and smaller flickers do not reset a leg. Durations are confirmation-to-confirmation, include quiet minutes and are truncated at observation boundaries. Long-leg occupancy is the share of 60 candles in detected legs lasting at least eight minutes; it is not a survival estimate.

The separate strict completed-pullback measure requires a preceding three-minute move of at least 12 ticks, the same 6-tick/0.025%/20% threshold, and recovery within eight samples, with no overlapping strict events. Legacy two-tick/15% pullbacks are retained in raw metric files. Additional descriptive classification labels a counter event as recovery to its pre-retracement extreme, a full reversal across its preceding anchor, or unresolved at the right edge. These directional events can overlap and use the remaining horizon; they are not substituted for non-overlapping strict pullback counts or gates.

Eleven synthetic measurement tests cover thresholds, scale invariance, flat paths, tiny opposite closes, full reversals, completed pullbacks and censoring. Candle OHLC is in dollars; book/trace price movement is in ticks. RV is square-root summed squared log returns over the measured hour, not annualized. One-minute RV uses 59 close-to-close returns for 60 bars. The legacy ten-close directional window spans nine intervals; its old label is retained for comparison. Range uses two disjoint 30-minute OHLC windows. Midpoint sampling uses executable two-sided quotes, with missing-side fractions reported separately.

Frozen gates require occupancy <=80% of baseline, longest meaningful leg <=85%, ten-close directional fraction <=80%, counters >=130%, and at least two-thirds of cases improving occupancy. Minute RV, mean minute range and 15-second midpoint RV must each retain >=90%; mean 30-minute range must retain >=80%. Strict completed pullbacks must increase by at least one in total. CurrentBX/BX must improve occupancy and counter count, not worsen maximum leg, and retain >=90% minute RV. Recovery <=110%, four-candle alternation <=8%, missing-side fraction <=0.1%, p95 spread <=150%, positive equity and exact replay are also required. The user's **0.7–1.5% 30-minute range remains a soft target**. The relative range floor prevents accepting a substantially flattened tape; it was fixed before results, not added to reject an otherwise passing arm.

No failed gate was weakened. Charts are an additional necessary check, not replaced by metrics. [Measurement audit](measurement-audit.json), [metric implementation](metrics.py), [event classification](measurement_audit.py).

## Complete development results

Metrics below average 18 market-hours per arm, except counter/pullback totals and recovery sums. Volume below is actual matched contracts, not both-side event counts.

'''
text+=table(['Arm','Long legs %','Max leg min','Counters','Strict PB','Minute RV %','Midpoint 15s RV %','30m range %','Recovery $m'],[[n,f'{a["MeaningfulLong8"]*100:.1f}',f'{a["MeaningfulMaxLeg"]:.2f}',round(a['MeaningfulCounters']*18),round(a['MeaningfulPullbacks']*18),f'{a["OneMinuteRV"]:.3f}',f'{a["FifteenSecondMidpointRV"]:.3f}',f'{a["MeanRange30"]:.3f}',f'{a["Recovery"]/1e6:.3f}']for n,a in agg.items()])
from measurement_audit import classify
classified={}
for name,ds in raws.items():
 classified[name]=dict(collections.Counter(e['Status']for d in ds for key,m in d['Markets'].items()for e in classify(m['Bars'],.1 if key=='BG'else.25)))
(R/'counter-event-outcomes.json').write_text(json.dumps(classified,indent=2))
text+='\nThe descriptive counter-event outcomes below separate full reversals from recovery to the preceding extreme. These can overlap, have no eight-sample deadline and are **not** the strict completed-pullback counts above. Unresolved events remain censored at the observation boundary.\n\n'
text+=table(['Arm','Recovered to preceding extreme','Full reversal','Unresolved'],[[n,x.get('RecoveredPullback',0),x.get('FullReversal',0),x.get('Unresolved',0)]for n,x in classified.items()])
text+='\n'+table(['Arm','p95 spread ticks','Missing-side %','4-candle alternation %','Matched contracts','Target windows /36','Maker P&L ex transfers $m'],[[n,f'{a["SpreadP95"]:.2f}',f'{a["NoQuoteFraction"]*100:.4f}',f'{a["Alternating4Fraction"]*100:.2f}',round(a['Volume']*18),a['TargetWindows'],f'{funding[n]["Maker"]/1e6:.3f}']for n,a in agg.items()])
text+='\nThe complete per-case and per-market results, all funding recipients/donors, body-color statistics, minute high-low ranges and event records are in [all-development-metrics.json](all-development-metrics.json), [funding-by-kind.json](funding-by-kind.json) and each raw `development-*/` folder. Lower transfers are not equivalent to better profitability; mark-to-market P&L excluding transfers is reported separately. Historical capital adjustments in old saves were preserved and are not counted as new experiment funding.\n\nThe strongest shape result, `no-skew-sparse-whale`, reduces mean maximum leg from 23.17 to 17.33 minutes and increases strict pullbacks from zero to 12. It still has 75.65% long-leg occupancy against a 74.15% gate, mean 30-minute range of 0.343% against a 0.372% floor, and CurrentBX/BX minute RV of 0.394% against a 0.430% floor. The final 30-lane variant raises aggregate RV but worsens occupancy to 79.44% and maximum leg to 20.28 minutes; CurrentBX/BX still has zero strict pullbacks. This is why neither better aggregate counters nor more volatility warrants promotion.\n\n'
text+='### Newly captured CurrentBX / BX, all arms\n\n'
current={'baseline':next(x for x in results[names[0]]['Markets']if x['Arm']=='Baseline'and x['Case']=='CurrentBX'and x['Market']=='BX')}
current.update({n:next(x for x in d['Markets']if x['Arm']=='Candidate'and x['Case']=='CurrentBX'and x['Market']=='BX')for n,d in results.items()})
text+=table(['Arm','Long legs %','Max leg min','Counters','Strict PB','Minute RV %','30m range %'],[[n,f'{x["MeaningfulLong8"]*100:.1f}',x['MeaningfulMaxLeg'],x['MeaningfulCounters'],x['MeaningfulPullbacks'],f'{x["OneMinuteRV"]:.3f}',f'{x["MeanRange30"]:.3f}']for n,x in current.items()])
text+='\n[All current BX arms on one vertical scale](CurrentBX-all-arms.png). Each chart uses actual matched-order OHLC, rebased only for display to its first measured open. Baseline/candidate pairs also share vertical scales in the complete charts below. The no-skew variants often replace large waves with small excursions and quiet intervals; sparse-depth and flow changes retain smooth portions. None should be presented as a solved chart problem.\n\n'
text+=table(['Variant','Failed gates','Candle comparisons'],[[n,', '.join(k for k,v in d['Gates'].items()if not v),' / '.join(link('development-'+n+'-'+m+'.png',m)for m in ['BX','BT','BG'])]for n,d in results.items()])
text+='''
## Finite endurance, safety and promotion decision

The no-skew/Reserve-delay combination received a separate **20-minute adaptation plus 90-minute measurement** on Seed71 and CurrentBX with only `BotParticipation.Rebalance` disabled. Risk pauses, recovery-exit scheduling, margin checks, stops, account liquidation, manual protections, execution collars and matching remained active. Recovery was disabled during adaptation too. This is a development endurance probe, not unseen validation and not a rescue of its failed shape gates.

'''
endurance=json.loads((R/'endurance-summary.json').read_text())
assert len(endurance)==8
assert all(x['Replay']and x['RecoveryTransfers']==0 and x['Recoveries']==0 and all(k['PositiveEquity']==k['Count']for k in x['Kinds'].values())for x in endurance)
text+=table(['Arm','Case','Recovery transfers','Maker P&L','Makers above floor /180','BX 30m volumes','BT 30m volumes','BG 30m volumes'],[[x['Variant'],x['Case'],x['RecoveryTransfers'],f"${x['Kinds']['Maker']['EquityChangeExTransfers']:,.2f}",x['Kinds']['Maker']['AboveOwnFloorEnd'],', '.join(map(str,x['Blocks']['BX'])),', '.join(map(str,x['Blocks']['BT'])),', '.join(map(str,x['Blocks']['BG']))]for x in endurance])
text+='''
Every bot retained positive terminal equity; every market had positive matched volume in each 30-minute block; all four runs had zero recovery transfers, passing audits and exact encoded-checkpoint continuation. This supports finite funded operation only. It does not establish indefinite sustainability or repair the failed candle shape. [Full endurance evidence](endurance-summary.json).

Every completed development and endurance benchmark passes the exchange's cash/equity, zero-net-inventory, volume, order-quantity, FIFO and uncrossed-book audits. Each branches from an encoded/decoded terminal checkpoint, runs another 80 steps, and compares complete state exactly. Only the candidate strategy/config files and experimental checkpoint version differ; accounting, margin, recovery, protection and execution modules are untouched. No bot population, capital allocation, margin allowance or recovery entitlement was increased. No new bot type, synchronized reversal, instant refill, artificial price writer, news event or candle-color logic was introduced. `reserve-delay` uses the already configured refill duration; other arms retain existing refill waits. The controlled fixture's test counterparties are funded at fixture initialization, not by benchmark/live grants.

All 14 current-world migration probes preserve the complete Engine and Population at restore, round-trip encoded state exactly, and confirm the old v28 reader refuses experimental v29 snapshots. This does not make the experimental policies release-ready: native full regression, candidate/native runtime parity and separate validation were **not run**, because no arm passed development. The native baseline causal fixture described above is expressly narrower. No native failure has been waived or represented as passing.

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
python -X utf8 output/microstructure-20261022/run_endurance.py no-skew-reserve-delay
python -X utf8 output/microstructure-20261022/endurance_summary.py
python -X utf8 output/microstructure-20261022/compile_report.py
python -X utf8 output/microstructure-20261022/check_delivery.py
```

Completed benchmark files are cached. For a fresh replay without overwriting preserved results, use `run_batch.py development --tag=rerun` and then `summarize_batch.py development-rerun`; this writes separate folders. A final candidate name can select one arm. `LocalLab.luau` also exposes `diagnose`, `tracecontrol`, `driftprobe`, `migrationprobe`, `suite` and `parity` modes; raw invocations and logs are preserved. Do not rerun initial `setup.py` or variant preparation scripts over this completed investigation: they are scaffolding, not result reproduction.

The [reproducibility manifest](reproducibility-manifest.json) records byte hashes of the harness, original/candidate sources, snapshots, unique raw runs, traces, reports and charts, plus the Lune runtime. Individual candidate manifests retain their original canonical UTF-8/LF hashes. `verify_studio_readonly.luau` reproduces the final source/editor comparison using the local expected-source bundle; it does not mutate Studio sources.

The read-only source/world bridge is local tooling, not game code. All subsequent simulations operate on captured snapshots. Saved worlds continue to have shared ancestry, and selection across 14 development variants has exploratory bias. That is why the unused holdouts, unchanged gates and explicit rejection are essential.
'''
text=text.replace('Fourteen frozen interventions were tested over five development rounds.','Fifteen frozen interventions were tested over six development rounds.')
text=text.replace('90 unique development runs, 270 measured market-hours','96 unique development runs, 288 measured market-hours').replace('each of 14 variants','each of 15 variants').replace('All 14 current-world','All 15 current-world').replace('selection across 14 development variants','selection across 15 development variants')
text=text.replace('All variants are isolated under', '6. **Final depth follow-up:** `no-skew-sparse30-whale` changes only the previous no-skew/sparse/Whale arm from 20 to 30 Maker lanes. The 20-lane arm produced 102 counter events and 12 strict pullbacks versus 61 and zero baseline, while preserving minute volatility; it still failed occupancy, relative range and CurrentBX movement. This source-frozen follow-up tests whether further reducing touch depth restores the missing movement. Gates and holdouts remain unchanged.\n\nAll variants are isolated under')
text=text.replace('The no-skew/Reserve-delay combination received a separate', 'The no-skew/Reserve-delay and both no-skew/sparse/Whale combinations received a separate').replace('all four runs had zero recovery transfers','all eight runs had zero recovery transfers').replace('failed shape gates.\n\nEvery completed','failed shape gates.\n\nEvery completed')
text=text.replace('python -X utf8 output/microstructure-20261022/run_endurance.py no-skew-reserve-delay','python -X utf8 output/microstructure-20261022/run_endurance.py no-skew-reserve-delay no-skew-sparse-whale no-skew-sparse30-whale')
(R/'RESULTS.md').write_text(text,encoding='utf8')
print('Report complete:',len(names),'rejected variants;',len(checks),'unique development runs; Studio unchanged')
