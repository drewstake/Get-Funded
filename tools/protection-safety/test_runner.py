"""Offline regression tests for reporting failures and blocking incomplete runs."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_release import validate_report
import check_release


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.report = {'Suites': {'ProbeTests': [{'Name': 'Example', 'Passed': True}]},
                       'Compiled': 1, 'Total': 1, 'Failures': 0}

    def validate(self, report):
        return validate_report(report, ['ProbeTests'], 1)

    def test_complete_success(self):
        self.assertEqual(self.validate(self.report), 1)

    def test_rejects_missing_extra_or_empty_suites(self):
        for suites in ({}, {'UnknownTests': []}, {'ProbeTests': []}, {'ProbeTests': {}},
                       {**self.report['Suites'], 'ExtraTests': []}):
            with self.subTest(suites=suites), self.assertRaises(ValueError):
                self.validate({**self.report, 'Suites': suites})

    def test_rejects_ambiguous_pass_flags_and_counts(self):
        for row in ({'Name': 'x'}, {'Name': 'x', 'Passed': 1}, {'Name': '', 'Passed': True},
                    {'Name': 'x', 'Passed': 'true'}, {'Name': 'x', 'Passed': True, 'Count': 0},
                    {'Name': 'x', 'Passed': True, 'Count': 1.5}):
            with self.subTest(row=row), self.assertRaises(ValueError):
                self.validate({**self.report, 'Suites': {'ProbeTests': [row]}})

    def test_failure_and_forged_summary_block_export(self):
        failed = copy.deepcopy(self.report);failed['Suites']['ProbeTests'][0]['Passed'] = False
        for count in (0, 1):
            failed['Failures'] = count
            with self.subTest(count=count), self.assertRaises(ValueError):
                self.validate(failed)

    def test_inventory_and_totals_must_agree(self):
        for key in ('Compiled', 'Total', 'Failures'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate({**self.report, key: 9})

    def test_no_discovery_is_not_a_pass(self):
        with self.assertRaises(ValueError):
            validate_report({'Suites': {}, 'Compiled': 0, 'Total': 0, 'Failures': 0}, [], 0)


class RunnerTests(unittest.TestCase):
    def run_fixture(self, body, expected, compile_source=None, empty=False):
        with tempfile.TemporaryDirectory(prefix='get-funded-test-runner-') as temp:
            out = Path(temp)
            (out / 'candidate').mkdir();(out / 'original').mkdir()
            if not empty:
                (out / 'candidate/ProbeTests.luau').write_text(body, encoding='utf-8')
                (out / 'original/ProbeTests.luau').write_text(compile_source or body, encoding='utf-8')
            shutil.copyfile(ROOT / 'tools/protection-safety/report.luau', out / 'report.luau')
            runner = (ROOT / 'tools/protection-safety/run.luau').read_text().replace('output/c1-protection-fix-20261026', out.as_posix())
            (out / 'run.luau').write_text(runner, encoding='utf-8')
            result = subprocess.run([str(ROOT / 'tools/runtime/lune.exe'), 'run', str(out / 'run.luau'), '--all'],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)
            if (out / 'all-results.json').exists():
                report = json.loads((out / 'all-results.json').read_text())
                self.assertEqual(report['Failures'], 0 if expected else 1)

    def test_valid_array_and_assertion_summary(self):
        for value in ("{{Name='ok',Passed=true}}", '{Passed=true,Cases=3}',
                      "{Passed=1,Total=1,Results={{Name='ok',Passed=true}}}"):
            with self.subTest(value=value):
                self.run_fixture('return function() return ' + value + ' end', True)

    def test_malformed_suite_returns_fail_process(self):
        for value in ('nil', 'false', 'true', '{}', '{Passed=true}', '{Cases=0,Passed=true}',
                      "{{Name='missing flag'}}", "{{Name='numeric flag',Passed=1}}",
                      "{Passed=1,Total=2,Results={{Name='ok',Passed=true}}}"):
            with self.subTest(value=value):
                self.run_fixture('return function() return ' + value + ' end', False)

    def test_failed_assertion_fails_process(self):
        self.run_fixture("return function() return {{Name='bad',Passed=false}} end", False)

    def test_throwing_suite_fails_process(self):
        self.run_fixture("return function() error('injected failure') end", False)

    def test_compile_original_source_even_if_adapter_is_valid(self):
        self.run_fixture("return function() return {{Name='ok',Passed=true}} end", False, 'local = invalid')

    def test_empty_discovery_fails_process(self):
        self.run_fixture('', False, empty=True)


class PreparationTests(unittest.TestCase):
    def test_nested_sources_and_duplicate_names(self):
        with tempfile.TemporaryDirectory(prefix='get-funded-nested-') as temp:
            root = Path(temp)
            for relative in ('tools/protection-safety/prepare.py', 'tools/protection-safety/run.luau',
                             'tools/protection-safety/report.luau', 'tools/execution-integrity/environment.luau'):
                destination = root / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, destination)
            (root / 'src/server').mkdir(parents=True)
            (root / 'src/tests').mkdir()
            (root / 'src/server/Value.luau').write_text('return 42')
            original = 'local value=require(script.Parent.Value)\nreturn function() return {{Name="nested",Passed=value==42}} end'
            (root / 'src/tests/NestedTests.luau').write_text(original)
            command = [sys.executable, str(root / 'tools/protection-safety/prepare.py'), '--output', 'output/test']
            subprocess.run(command, cwd=root, check=True, capture_output=True)
            self.assertEqual((root / 'output/test/original/NestedTests.luau').read_text(), original)
            self.assertIn('require("./Value")', (root / 'output/test/candidate/NestedTests.luau').read_text())
            result = subprocess.run([str(check_release.build.lune_path()), 'run', 'output/test/run.luau', '--all'],
                                    cwd=root, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # A removed source must disappear from reused snapshots.
            (root / 'src/tests/NestedTests.luau').unlink()
            subprocess.run(command, cwd=root, check=True, capture_output=True)
            self.assertFalse((root / 'output/test/original/NestedTests.luau').exists())
            (root / 'src/tests/Value.luau').write_text('return 99')
            result = subprocess.run(command, cwd=root, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Duplicate source filename', result.stderr)
            self.assertEqual((root / 'output/test/original/Value.luau').read_text(), 'return 42')


class ExportGateTests(unittest.TestCase):
    def exercise(self, exit_code=0, report=None, changed=False, isolated=False):
        with tempfile.TemporaryDirectory(prefix='get-funded-export-gate-') as temp:
            root = Path(temp);(root / 'src').mkdir()
            (root / 'src/ProbeTests.luau').write_text('return {}')
            output = root / 'check'
            if report is None:
                report = {'Suites': {'ProbeTests': [{'Name': 'ok', 'Passed': True}]}, 'Compiled': 1, 'Total': 1, 'Failures': 0}

            def prepare_or_run(command, **kwargs):
                if '--output' in command:
                    prepared = output / 'harness';(prepared / 'original').mkdir(parents=True)
                    shutil.copyfile(root / 'src/ProbeTests.luau', prepared / 'original/ProbeTests.luau')
                    (prepared / 'all-results.json').write_text(json.dumps(report))
                    return subprocess.CompletedProcess(command, 0)
                return subprocess.CompletedProcess(command, exit_code)

            initial = {'source': 'before'}
            expected_success = exit_code == 0 and not changed and report['Failures'] == 0 and bool(report['Suites'])
            with patch.object(check_release, 'ROOT', root), patch.object(check_release, 'harness_hashes', return_value={'runner': 'fixed'}), \
                 patch.object(check_release.build, 'lune_path', return_value=root / 'lune'), \
                 patch.object(check_release.build, 'load_inputs', side_effect=[(None, None, None, initial), (None, None, None, {'source': 'after'} if changed else initial)]), \
                 patch.object(check_release.subprocess, 'run', side_effect=prepare_or_run), \
                 patch.object(check_release.build, 'build', return_value=(root, {'Inputs': initial, 'PlaceSha256': 'verified'})) as exporter:
                if expected_success:
                    result = check_release.check(output, isolated=isolated);self.assertTrue(result['Passed'])
                    options = {'output': output / 'place'} if isolated else {}
                    exporter.assert_called_once_with(root=root, lune=root / 'lune', expected_inputs=initial, **options)
                    self.assertEqual(result['Place'], str(root / (check_release.build.PLACE_NAME if isolated else check_release.build.CURRENT_PLACE)))
                    self.assertFalse((output / 'place').exists())
                    self.assertTrue((output / 'release-check.json').exists())
                else:
                    with self.assertRaises(ValueError):
                        check_release.check(output)
                    exporter.assert_not_called();self.assertFalse((output / 'release-check.json').exists())

    def test_failed_process_never_exports(self):
        self.exercise(exit_code=1)

    def test_failed_results_never_export_even_with_zero_exit(self):
        self.exercise(report={'Suites': {'ProbeTests': [{'Name': 'failed', 'Passed': False}]}, 'Compiled': 1, 'Total': 1, 'Failures': 1})

    def test_missing_suite_never_exports(self):
        self.exercise(report={'Suites': {}, 'Compiled': 1, 'Total': 0, 'Failures': 0})

    def test_changed_source_never_exports(self):
        self.exercise(changed=True)

    def test_complete_unchanged_source_exports_once(self):
        self.exercise()

    def test_isolated_check_exports_to_its_evidence_directory(self):
        self.exercise(isolated=True)


if __name__ == '__main__':
    unittest.main()
