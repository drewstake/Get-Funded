from pathlib import Path
import json

R = Path(__file__).resolve().parent
report = (R / 'RESULTS.md').read_text(encoding='utf8')
assert json.loads((R / 'v2-installation-gates.json').read_text(encoding='utf8'))['Passed']
rejected = json.loads((R / 'installation-gates-v3-extended.json').read_text(encoding='utf8'))
assert not rejected['Passed']
assert json.loads((R / 'source-readback-final.json').read_text(encoding='utf8'))['InstalledMomentumVersion'] == 2

section = '''## Additional profile correction: tested and not installed

After the initial validated correction was installed, an audit found that a small subset of fast Momentum profiles can have confirmation time greater than or equal to their horizon. Such profiles cannot form an entry signal. For example, seed 71's `bot:BT:Momentum:30` has a 22.6453-second horizon and 24.3008-second confirmation. This is a known participation limitation in the installed v2 policy; existing positions and all exits/protections continue to work.

A broad confirmation bound changed valid profiles and failed validation. A narrower Momentum-v3 candidate corrected only impossible windows, preserving every already-valid profile and consuming no additional shared randomness. It passed deterministic replay, native safeguards and the finite funding probes, but improved pullback counts in only two of the four original validation cases (one tied and one worsened).

One final six-case batch was fixed in advance, with the source hashes frozen: seeds 314159, 271828 and 161803, plus CurrentPlus60, OlderPlus60 and AgedLater saved-world continuations. No strategy tuning occurred during this batch. Pullbacks improved in only three of six cases, below the required four. Across all ten validation cases, five improved, below the required six. Aggregate streaks, pullbacks and volatility improved, but the consistency gate failed. **Momentum v3 was not installed.** Both attempted profile corrections remain rejected; no further tuning or sample extension followed.

These extra results evaluate v3, not the installed v2. They must not be combined with v2's reported performance. The original v2 installation decision remains supported by its six development and four separate validation cases. The failed correction and the inactive-profile limitation are retained here explicitly, rather than silently installing a behavior that missed the requested quality gate.

Evidence: `profile-fix.json`, `extension-plan.json`, `installation-gates-v3.json`, `installation-gates-v3-extended.json`, `holdout-v3/` and `extension-v3/`. The rejected version passed 253 native checks with the same 38 baseline failures; the installed version's results are 251 passes with those same 38 failures.

'''
assert '## Additional profile correction:' not in report
report = report.replace('## Installation and reproducibility\n', section + '## Installation and reproducibility\n')
report = report.replace('`runtime-parity.json`, `suite-comparison.json`, `applied.json`', '`v2-runtime-parity.json`, `v2-suite-comparison.json`, `v2-applied.json`')
report = report.replace('Temporary detached test modules were removed.', 'Temporary detached test modules were removed. Final readback matched all 105 runtime sources, including the ten installed changes, to the validated v2 files. Two live diagnostics confirmed that the shared saved world resumed and continued trading, with zero net inventory and cash/equity errors below 0.00001. The console contained expected injected-failure messages from detached tests and Roblox UI warnings; the live exchange remained active. See `source-readback-final.json`, `live-verification-final.json` and `live-verification-followup.json`.')
report = report.replace('The complete decision is recorded in `installation-gates.json`;', 'The installed decision is recorded in `installation-gates.json` and its preserved copy `v2-installation-gates.json`;')
(R / 'RESULTS.md').write_text(report, encoding='utf8')
(R / 'final-decision.json').write_text(json.dumps({
    'Installed': {'Checkpoint': 28, 'Momentum': 2, 'Whale': 1, 'Maker': 8, 'Manifest': 'candidate-manifest.json', 'Gate': 'v2-installation-gates.json'},
    'RejectedProfileCorrection': {'Momentum': 3, 'Gate': 'installation-gates-v3-extended.json', 'Reason': 'Cross-case pullback consistency failed', 'KnownInstalledLimitation': 'Some fast Momentum profiles have Confirmation >= Horizon and cannot enter'},
    'Published': False,
    'FinalReadback': 'source-readback-final.json',
    'LiveVerification': 'live-verification-followup.json'
}, indent=2), encoding='utf8')
print('Final report records installed v2 and rejected v3 separately.')
