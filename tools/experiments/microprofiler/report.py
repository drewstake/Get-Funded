from pathlib import Path
import json, statistics, hashlib
root=Path(__file__).resolve().parents[3];out=root/'output/microprofiler-20261027'
def read(name):return json.loads((out/name).read_text())
paired=read('native-candidate-analysis.json');test=read('native-candidate-test.json')
before=paired[:4];after=paired[5:]
def stats(values):return {'Count':len(values),'Mean':statistics.mean(values),'Median':statistics.median(values),'Max':max(values),'Min':min(values)}
frame={'Before':stats([x['FrameMs'] for x in before]),'After':stats([x['FrameMs'] for x in after])}
native={key:stats([max(s['Ms'] for s in x['Spans'] if s['Timer']=='Write Marshalled') for x in rows]) for key,rows in [('Before',before),('After',after)]}
slots={key:stats([r['Bytes'] for r in test['Rows'] if r['Variant']==variant and r['Kind']=='slot']) for key,variant in [('Before','Baseline'),('After','Candidate')]}
roundtrip={key:stats([r['ElapsedMs'] for r in test['Rows'] if r['Variant']==variant and r['Kind']=='slot']) for key,variant in [('Before','Baseline'),('After','Candidate')]}
live=read('live-steady-after.json');release=read('release/release-check.json');continuity=read('continuity-restart.json');stress=read('stress-candidate/stress-results.json')
historical=json.loads((root/'output/latency-20261027/live-server-final.json').read_text())
summary={'Scope':'Studio MicroProfiler and native DataStore operations on detached saved copies. Payload sizes are serialized application bytes, not wire traffic.',
 'PairedFrameMs':frame,'PairedNativeWriteMarshalledMs':native,'SlotBytes':slots,'SlotRoundTripMs':roundtrip,
 'LiveSteady':live,'EarlierLiveBaseline':historical,'Release':release,'Continuity':continuity,
 'Stress':[{'Scenario':s['Mode'],'MaxPlayer':s['MaxPlayerContracts'],'MaxReserve':s['MaxReserveContracts'],'Depleted':s['MaxReserveDepleted'],'Remaining':s['RemainingAfterClose']} for s in stress['Scenarios']],
 'World':read('final-world.json'),'RestartGate':read('restart-gate.json'),
 'Excluded':'Exploratory snapshots lacking callback markers and the temporary probe-error/recovery window. See tools/experiments/microprofiler/README.txt.'}
(out/'summary.json').write_text(json.dumps(summary,indent=2))
lines=[
'MicroProfiler investigation and verified fix — October 27, 2026',
'',
'Confirmed cause: the native Write Marshalled job processing the large return value from DataStore UpdateAsync dominated the recurring save hitch. Callback markers place the checkpoint-slot transform inside the long frame. Matching and rendering were much smaller; these captures do not support blaming GC for the recurring ~88 ms hitch. The profiler does not expose the internal C++ split between validation, serialization and copying.',
'',
'The checkpoint repeatedly included an unchanged 1.58 MB encoded retirement archive. The V3 ownership format stages that immutable archive once, confirms it, then stores the mutable core plus a checksum-bound archive reference in each rotating slot. Publication remains atomic and fenced. A failed archive, slot or publication operation retains the previous committed checkpoint. Reads are uncached and full decode checks both checksums, the core/archive binding and the original combined raw-size limit. The original complete stored-size budget still includes the archive. Old V1/V2 manifests and inline checkpoints remain readable; old ownership writers reject V3.',
'',
'BX remains the only active market, with 1,170 participants and 54 reserves. The 72-step rate, 8 ms simulation budget, 0.1-second broadcast interval, 200-contract cap, finite funding, reserve protections, price bands, exposure limits, FIFO and execution safeguards are unchanged.',
'',
'Restart verifies and reuses the exact archive encoding. This prevents JSON key order from producing additional immutable archive records. No account, bot balance, position, order, market history, or retired-market data was discarded. No bot refresh, funding reset, polling increase or broadcast increase was performed.',
'',
'Paired native comparison on the same detached saved checkpoint (four slot writes per version, including restart):',
f"  Frame time: mean {frame['Before']['Mean']:.2f} -> {frame['After']['Mean']:.2f} ms; range {frame['Before']['Min']:.2f}–{frame['Before']['Max']:.2f} -> {frame['After']['Min']:.2f}–{frame['After']['Max']:.2f} ms.",
f"  Native Write Marshalled: mean {native['Before']['Mean']:.2f} -> {native['After']['Mean']:.2f} ms; maximum {native['Before']['Max']:.2f} -> {native['After']['Max']:.2f} ms.",
f"  Slot payload: {slots['Before']['Mean']:.0f} -> {slots['After']['Mean']:.0f} bytes ({100*(1-slots['After']['Mean']/slots['Before']['Mean']):.1f}% reduction). These are JSON-serialized bytes, not measured wire bytes.",
f"  Slot RPC elapsed: mean {roundtrip['Before']['Mean']:.1f} -> {roundtrip['After']['Mean']:.1f} ms. Network waits yield and are distinct from frame-blocking CPU time.",
'  One-time archive staging: 51.26 ms native work / 62.40 ms frame in the detached experiment. Initial real-world migration occurs before trading readiness; subsequent saves and tested restart do not rewrite the archive.',
'  Buffer conversion alone did not improve the size-dependent callback cost, so it was rejected.',
'',
f"Clean live observation: {live['Seconds']:.2f} seconds, {live['Stats']['Frames']['Count']} heartbeats, {live['StepsPerRealSecond']:.4f} steps per real second.",
f"  Frame median/p99/max: {live['Stats']['Frames']['P50']:.2f} / {live['Stats']['Frames']['P99']:.2f} / {live['Stats']['Frames']['Max']:.2f} ms. Earlier 60-second observation: 4.00 / 7.00 / 87.74 ms.",
f"  Market heartbeat work mean/p99/max: {live['Stats']['Work']['Mean']:.3f} / {live['Stats']['Work']['P99']:.2f} / {live['Stats']['Work']['Max']:.2f} ms. Earlier observation: 0.971 / 5.08 / 22.07 ms.",
f"  Simulation backlog mean/max: {live['Stats']['Backlog']['Mean']:.4f} / {live['Stats']['Backlog']['Max']:.4f} simulated seconds. Earlier observation: 0.1247 / 0.9688. No growing backlog or skipped simulation steps was observed in the clean window.",
f"  Native MicroProfiler timeline maximum across the post-change captures: {max(r['FrameMs'] for r in read('after-analysis.json')):.2f} ms (frame boundaries differ from Heartbeat dt).",
'  The live windows are different market moments and durations, so the paired saved-copy test is the stronger attribution evidence. Client packet formats and the 0.1-second broadcast cadence did not change; no new client-network reduction is claimed.',
'',
f"Validation: {release['Suites']} suites, {release['Results']} checks, {release['Compiled']} sources compiled, zero failures. All six independently restored saved-market stress scenarios passed: buy, sell, cycle, passive, multi-owner, rich. Maximum player exposure stayed <=200; zero reserves depleted; every tested exit cleared. The regression suite also covers bursts, partial fills, amendments, cancellations, protective exits, quote depletion and persistence failures.",
'  Saved input remained unchanged. Full engine/population comparison preserved all accounts, orders, positions and history. Two encode/decode restarts and 1,200 deterministic steps passed; baseline and candidate matched through 1,200 steps. Two WorldService opens/restarts used exactly one archive write. Native scratch-store save/read/restart also retained identical core and archive payloads. All scratch keys were removed.',
'',
'Deployment: every account was checked flat with zero working orders immediately before stopping Play. The final shutdown checkpoint retained the same world ID. All 131 installed Studio sources matched the verified manifest before restarting. The active account balance remained 243037.50000001715. The 5-minute BX chart, 72 bars, follow mode, price bounds and ticket presentation were restored. Studio remains running; nothing was published.',
f"Canonical place: {root/'Get Funded!.rbxl'}",
f"SHA-256: {release['PlaceSha256']}",
'',
'Measurement incident: a temporary runtime profiling hook initially omitted its local Http binding. Save protection paused trading and retained the last committed checkpoint. The hook was corrected, normal saving resumed, and that mixed/recovery window was excluded. The clean observation began only after recovery. The verified production source did not contain the hook. Temporary probes were removed after final verification.',
'',
'Remaining bottlenecks: about 23–25 ms of native processing for the mutable slot, and roughly 20 ms to capture/serialize a coherent mutable snapshot. Smaller recurring frame spikes remain. Splitting the core over more keys would add writes, failure states and coordination; this change leaves that as a separate measured tradeoff. The exact native C++ implementation is not visible. This does not establish a new cause for empty-book episodes; no liquidity/strategy delay was changed.',
'',
'Evidence: native-candidate-analysis.json + native-candidate-1..9.gprx; baseline-analysis.json + before-1..3.gprx; after-analysis.json + after-*.gprx; live-steady-after.json; release/release-check.json; stress-candidate/stress-results.json; continuity-restart.json; final-world.json; changes.patch.',
'Representative frame IDs (local / absolute): baseline 380649 / 1700759, 381825 / 1701935; candidate 383281 / 1703391, 383792 / 1703902. In candidate capture 9 the callback begins in 384943 / 1705053 and overlaps frame 384944 / 1705054. See the saved timelines for per-thread spans; inclusive parent/child and sleeping-thread times must not be added together.'
]
(out/'report.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Report and summary written')
