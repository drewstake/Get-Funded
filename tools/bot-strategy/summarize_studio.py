"""Summarize the verified, persisted Studio playtest without private player data."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'output/bot-strategy-studio-20261018'
read = lambda name: json.loads((OUT / name).read_text())
final = read('final-playtest-results.json')
tests = read('studio-tests.json')
migration = read('studio-saved-migration.json')
restart = read('restart-observation.json')
installed = read('final-install-verification.json')
console = read('playtest-console.json')
assert tests['Total'] == 103 and tests['Failures'] == 0
assert migration['ExactEnginePreserved'] and migration['ExactPopulationPreserved']
assert migration['ExactRoundtrip'] and migration['ExactReplay']
assert restart['Mode'] == 'Shared' and restart['StartedFromStep'] > final['InitialStep']
assert final['Step'] > restart['StartedFromStep'] and final['LeaseUntil'] == 0
assert final['Version'] == 18 and final['SignalsVersion'] == 1
assert final['CapitalPreserved'] and final['PerformanceBaselinesPreserved']
assert installed['HashesMatch'] and installed['NoTemporaryObjects'] and installed['EditMode']
assert not console['GameErrors'] and not console['GameWarnings']
assert final['Kinds']['Scalper']['BotsTraded'] == 72
summary = {
    'Status': 'Installed in the open Roblox Studio place; two Play sessions completed',
    'PlaceId': 137759823569682,
    'Scope': 'Studio',
    'Published': False,
    'LocalPlaceFileSaved': False,
    'LocalPlaceFileNote': 'Window was repeatedly minimized and computer-use detected concurrent user input; no local RBXL copy was saved.',
    'InstalledModules': installed['InstalledModules'],
    'NativeTestsPassed': tests['Total'],
    'InitialStep': final['InitialStep'],
    'RestartResumedStep': restart['StartedFromStep'],
    'FinalSavedStep': final['Step'],
    'SimulatedMinutes': (final['Time'] - final['InitialTime']) / 60,
    'MigrationPreservedAllEngineAndPopulationState': True,
    'BotCapitalAndPerformanceBaselinesPreserved': True,
    'ExactSaveReloadReplaySteps': migration['ReplaySteps'],
    'AllScalpersTraded': True,
    'ScalperClosingExecutions': final['Kinds']['Scalper']['CompletedTrades'],
    'PnlChanges': {kind: row['PnlChange'] for kind, row in final['Kinds'].items()},
    'AccountingAudit': final['Audit'],
    'GameScriptErrors': 0,
    'GameWarnings': 0,
    'CheckpointVersion': final['Version'],
    'BotSignalsVersion': final['SignalsVersion'],
    'SavedLeaseReleased': True,
    'TemporaryTestObjectsRemoved': True,
    'Backups': str(ROOT / 'backups/bot-strategy-studio-20261018'),
}
(OUT / 'summary.json').write_text(json.dumps(summary, indent=2))
manifest_path = ROOT / 'output/bot-strategy-20261018/release-manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['Status'] = summary['Status'] + '; not published or saved to a local RBXL copy'
manifest['StudioValidationReport'] = str(OUT / 'summary.json')
manifest_path.write_text(json.dumps(manifest, indent=2))
print(json.dumps({k: summary[k] for k in ['NativeTestsPassed', 'InitialStep', 'RestartResumedStep', 'FinalSavedStep', 'SimulatedMinutes', 'ScalperClosingExecutions', 'PnlChanges']}, indent=2))
