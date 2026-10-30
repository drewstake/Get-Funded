"""Run every detached regression suite, then build/verify the exact tested sources.

All service access is provided by the offline harness; no live data or publishing.
Requires the same Python dependencies and Lune version as tools/place-build.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/place-build'))
import build


def validate_report(report, suites, source_count):
    """Require complete discovery and explicit boolean results, not just exit code 0."""
    def need(ok, message):
        if not ok:
            raise ValueError(message)
    need(bool(suites) and type(report) is dict, 'No test suites/report')
    actual = report.get('Suites')
    need(type(actual) is dict and set(actual) == set(suites), 'Missing or unexpected test suites')
    need(type(report.get('Compiled')) is int and report['Compiled'] == source_count, 'Compile inventory mismatch')
    total = failures = 0
    for name, rows in actual.items():
        need(type(rows) is list and bool(rows), f'{name}: empty/malformed results')
        for row in rows:
            need(type(row) is dict and type(row.get('Name')) is str and bool(row['Name'])
                 and type(row.get('Passed')) is bool, f'{name}: invalid result row')
            if 'Count' in row:
                need(type(row['Count']) is int and row['Count'] > 0, f'{name}: invalid assertion count')
            total += 1
            failures += not row['Passed']
    need(type(report.get('Total')) is int and report['Total'] == total, 'Test count mismatch')
    need(type(report.get('Failures')) is int and report['Failures'] == failures, 'Failure count mismatch')
    need(failures == 0, f'{failures} regression results failed; export blocked')
    return total


def harness_hashes():
    paths = ['tools/check_release.py', 'tools/protection-safety/prepare.py',
             'tools/protection-safety/run.luau', 'tools/protection-safety/report.luau',
             'tools/execution-integrity/environment.luau']
    return {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in paths}


def check(output, lune=None, isolated=False):
    output = output.resolve()
    build.need(output.is_relative_to(ROOT), 'Check output must be inside this repository')
    build.need(not output.exists(), 'Check output already exists; choose a new directory')
    inputs = build.load_inputs()[3]
    harness = harness_hashes()
    sources = sorted((ROOT / 'src').rglob('*.luau'))
    suites = sorted(path.stem for path in sources if path.name.endswith('Tests.luau'))
    runtime = build.lune_path(explicit=lune)
    output.mkdir(parents=True)
    prepared = output / 'harness'
    subprocess.run([sys.executable, str(ROOT / 'tools/protection-safety/prepare.py'),
                    '--output', str(prepared.relative_to(ROOT))], cwd=ROOT, check=True)
    # Compile, discovery and execution all use this detached copy. Compare it with
    # the initial input hashes before trusting the report or generating a place.
    for source in sources:
        saved = prepared / 'original' / source.name
        build.need(saved.read_bytes() == source.read_bytes(), 'Source changed during snapshot')
    with (output / 'regression-tests.log').open('w', encoding='utf-8') as log:
        result = subprocess.run([str(runtime), 'run', str(prepared / 'run.luau'), '--all'],
                                cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    build.need(result.returncode == 0, f'Regressions failed; see {output / "regression-tests.log"}')
    report = json.loads((prepared / 'all-results.json').read_text(encoding='utf-8'))
    count = validate_report(report, suites, len(sources))
    build.need(build.load_inputs()[3] == inputs and harness_hashes() == harness,
               'Source, build inputs or harness changed during tests; run again')
    build_options = {'output': output / 'place'} if isolated else {}
    destination, verified = build.build(root=ROOT, lune=runtime, expected_inputs=inputs, **build_options)
    build.need(verified['Inputs'] == inputs and harness_hashes() == harness,
               'Inputs changed after regression verification; run again')
    summary = {'Passed': True, 'Suites': len(suites), 'Results': count, 'Failures': 0,
               'Compiled': len(sources), 'Place': str(destination / (build.PLACE_NAME if isolated else build.CURRENT_PLACE)),
               'PlaceSha256': verified['PlaceSha256'], 'Inputs': inputs, 'HarnessHashes': harness,
               'NoProductionData': True, 'Published': False,
               'Limitations': ['Detached Luau regression execution; no native client/server playtest.',
                               'Scene assets come from the pinned base place.']}
    (output / 'release-check.json').write_bytes(build.json_bytes(summary))
    print(f'PASS: {len(suites)} suites, {count} results, {len(sources)} sources compiled')
    print(summary['Place'])
    print('Place matches tested source: ' + verified['PlaceSha256'])
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='New evidence directory inside the repository')
    parser.add_argument('--lune', type=Path)
    parser.add_argument('--isolated', action='store_true', help='Build under the check directory; preserve the current place and its report')
    args = parser.parse_args()
    output = args.output or Path('output/checks') / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    try:
        check(output if output.is_absolute() else ROOT / output, args.lune, args.isolated)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'RELEASE CHECK FAILED: {error}\n')
