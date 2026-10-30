MicroProfiler investigation, October 27, 2026

Evidence lives in output/microprofiler-20261027. Production changes are limited to
WorldLease, WorldCheckpoint, WorldService and their persistence/latency tests.
The canonical verified place is the repository-root Get Funded!.rbxl.

bridge.py is a loopback-only file transport on port 8820. It does not access a
DataStore. capture.luau/analyze.luau/export.luau run through Studio's MCP context
using @rbx/LibMP. Analyze immutable snapshots, warm the iterator one frame early,
clamp scope parts to frame boundaries, and dispose native sessions/iterators.
assemble.py reconstructs native .gprx files from compressed evidence pieces.

Native test scripts use unique generated scopes in MarketReign_ProfilerScratch_v1.
They remove only keys they created. checkpoint-test and native-candidate read the
exchange checkpoint without cache and write only detached scratch copies. They
must never be pointed at the real exchange's write scope.

Capture caveat: snapshots made immediately after the UpdateAsync callback can be
too early to include the completed long frame. Conversely delayed continuations
can miss the window. Accept a callback sample only when its marker is in the saved
MicroProfiler frame window. The validated trigger schedules a snapshot 60 ms after
the Heartbeat observes the callback's MPProbe attribute, pauses only profiling
during the buffer copy, then resumes profiling. It never pauses game execution.
read-*, size-*, update-in-* and update-out-late/paused captures were exploratory;
their absent callback markers make them insufficient evidence of no hitch.
Use native-candidate-analysis.json and its nine native-candidate-*.gprx captures
for the paired full-record versus external-archive comparison.

A temporary callback-marker probe initially lacked its local Http binding. Save
protection correctly paused the exchange and retained the committed checkpoint.
The probe was corrected, normal saving resumed, and that window was excluded.
probe-recovery-excluded contains the transitional captures; live-after.json is
the excluded mixed observation. live-steady-after.json is the clean measurement.
Temporary runtime probes are removed after final verification.

All regression suites: tools/check_release.py --output <new path>
All six saved-copy stress scenarios: tools/experiments/microprofiler/validate_saved.py candidate --label <new label>
Saved continuity and persistence restart checks: tools/experiments/microprofiler/continuity.luau
The latter two scripts reference this run's explicit immutable input/harness paths.
They are offline and never write Roblox storage or refresh bots.
