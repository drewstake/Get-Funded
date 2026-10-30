"""Offline regression tests. No game module is executed or cloud API called."""
from contextlib import contextmanager
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import build
import rbxl


class BuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = build.load_inputs()
        cls.manifest, cls.sources, cls.base, _ = cls.inputs
        cls.candidate = rbxl.overlay(cls.base, cls.manifest["scripts"], cls.sources)
        cls.lune = build.lune_path()

    @contextmanager
    def project(self):
        with tempfile.TemporaryDirectory(prefix="get-funded-build-test-") as temp:
            root = Path(temp)
            shutil.copytree(build.ROOT / "src", root / "src")
            (root / "build").mkdir()
            shutil.copyfile(build.ROOT / build.MANIFEST, root / build.MANIFEST)
            shutil.copyfile(build.ROOT / self.manifest["base"]["file"], root / self.manifest["base"]["file"])
            yield root

    def edit_manifest(self, root, change):
        path = root / build.MANIFEST
        manifest = json.loads(path.read_text())
        change(manifest)
        path.write_bytes(build.json_bytes(manifest))

    def rewrite_property(self, data, path, name, change):
        place = rbxl.Place(data)
        ref = place.resolve(path)
        cid = place.instances[ref]
        index = place.classes[cid][1].index(ref)
        out = bytearray(data[:32])
        for item in place.chunks:
            if item.tag == b"PROP":
                item_cid, prop, kind, offset = rbxl.property_header(item.body)
                if (item_cid, prop) == (cid, name):
                    items = rbxl.values(item.body[offset:], kind, len(place.classes[cid][1]))
                    items[index] = change(items[index])
                    out.extend(rbxl.chunk(item.tag, item.body[:offset] + rbxl.encode_values(items, kind)))
                    continue
            out.extend(item.raw)
        return bytes(out)

    def binary_check(self, data):
        build.verify_binary(rbxl.Place(data), self.manifest, self.sources, self.base)

    def test_complete_export_and_independent_reader(self):
        with self.project() as root:
            destination, report = build.build(root, root / "release", self.lune)
            self.assertEqual(report["ScriptCount"], len(self.sources))
            self.assertEqual(report["Compiled"], len(self.sources))
            self.assertEqual(report["NonScriptChunksPreserved"], len(self.base.asset_chunks()))
            self.assertEqual(build.verify(destination / build.PLACE_NAME, root, self.lune), report)
            for path in ("ReplicatedFirst.LoadingScreen", "ServerScriptService.MarketReign.TradingCharacter",
                         "ServerScriptService.MarketReign.ProtectionSafetyTests", "ServerScriptService.MarketReign.WorldStorageTests"):
                self.assertIn(path, {x["path"] for x in report["Scripts"]})

    def test_default_build_keeps_only_one_current_place(self):
        with self.project() as root:
            current = root / build.CURRENT_PLACE
            current.write_bytes(b"old local place")
            destination, report = build.build(root=root, lune=self.lune)
            self.assertEqual(destination, root)
            self.assertEqual(current.read_bytes(), self.candidate)
            self.assertEqual(json.loads((root / build.CURRENT_REPORT).read_text()), report)
            source = root / "src/server/WorldLease.luau"
            source.write_bytes(source.read_bytes() + b"\n-- newer source\n")
            _, updated = build.build(root=root, lune=self.lune)
            self.assertNotEqual(report["PlaceSha256"], updated["PlaceSha256"])
            self.assertEqual(build.verify(current, root, self.lune), updated)
            self.assertEqual(list(root.rglob("*.rbxl")), [current])
            self.assertFalse((root / "output/builds").exists())

    def test_failed_current_build_keeps_last_good_place_and_report(self):
        with self.project() as root:
            build.build(root=root, lune=self.lune)
            current = root / build.CURRENT_PLACE
            old = current.read_bytes();report = (root / build.CURRENT_REPORT).read_bytes()
            with (root / "src/server/WorldLease.luau").open("a") as stream:
                stream.write("\nlocal = invalid")
            with self.assertRaisesRegex(ValueError, "reader/compile failed"):
                build.build(root=root, lune=self.lune)
            self.assertEqual(current.read_bytes(), old)
            self.assertEqual((root / build.CURRENT_REPORT).read_bytes(), report)
            self.assertFalse(list((root / "build").glob(".place-build-*")))

    def test_changed_tested_inputs_never_replace_current_place(self):
        with self.project() as root:
            current = root / build.CURRENT_PLACE;current.write_bytes(b"keep me")
            tested = build.load_inputs(root)[3]
            source = root / "src/server/WorldLease.luau"
            source.write_bytes(source.read_bytes() + b"\n-- changed after tests\n")
            with self.assertRaisesRegex(ValueError, "Inputs changed since regression tests"):
                build.build(root=root, lune=self.lune, expected_inputs=tested)
            self.assertEqual(current.read_bytes(), b"keep me")

    def test_report_write_failure_restores_previous_current_place(self):
        with self.project() as root:
            build.build(root=root, lune=self.lune)
            current = root / build.CURRENT_PLACE;old = current.read_bytes()
            report_path = root / build.CURRENT_REPORT;old_report = report_path.read_bytes()
            source = root / "src/server/WorldLease.luau"
            source.write_bytes(source.read_bytes() + b"\n-- changed\n")
            original = Path.replace
            def fail_report(path, target):
                if target == report_path:
                    raise OSError("Injected metadata failure")
                return original(path, target)
            with patch.object(Path, "replace", fail_report):
                with self.assertRaisesRegex(OSError, "Injected metadata failure"):
                    build.build(root=root, lune=self.lune)
            self.assertEqual(current.read_bytes(), old)
            self.assertEqual(report_path.read_bytes(), old_report)

    def test_old_place_that_caused_c3_is_rejected(self):
        # The current scene is repinned after reviewed Studio edits. Keep this
        # regression anchored to the original incomplete place, not that scene.
        digest = "b4fe9b19bca05835abf17c04e3f11cb0ad2f3c5aacbd88dba62ffcb330d0bc4e"
        with zipfile.ZipFile(build.ROOT / self.manifest["base"]["file"]) as archive:
            original = archive.read("previous/" + digest + ".rbxl")
        self.assertEqual(build.sha(original), digest)
        with self.assertRaisesRegex(ValueError, "inventory count"):
            self.binary_check(original)

    def test_new_unmapped_source_fails_closed(self):
        with self.project() as root:
            (root / "src/NewModule.luau").write_text("return {}")
            with self.assertRaisesRegex(ValueError, "unmapped=.*NewModule"):
                build.load_inputs(root)

    def test_nested_source_cannot_be_silently_omitted(self):
        with self.project() as root:
            (root / "src/nested").mkdir()
            (root / "src/nested/Extra.luau").write_text("return {}")
            with self.assertRaisesRegex(ValueError, "inventory mismatch"):
                build.load_inputs(root)

    def test_deleted_source_fails_closed(self):
        with self.project() as root:
            (root / "src/server/WorldLease.luau").unlink()
            with self.assertRaises(FileNotFoundError):
                build.load_inputs(root)

    def test_duplicate_file_and_duplicate_path_rejected(self):
        for field in ("file", "path"):
            with self.subTest(field=field), self.project() as root:
                self.edit_manifest(root, lambda m: m["scripts"][1].update({field: m["scripts"][0][field]}))
                with self.assertRaisesRegex(ValueError, "Duplicate manifest"):
                    build.load_inputs(root)

    def test_wrong_script_class_rejected(self):
        with self.project() as root:
            self.edit_manifest(root, lambda m: next(x for x in m["scripts"] if x["file"] == "src/server/MarketServer.server.luau").update({"class": "ModuleScript"}))
            with self.assertRaisesRegex(ValueError, "class/name mismatch"):
                build.load_inputs(root)

    def test_misplaced_module_breaks_dependency_validation(self):
        with self.project() as root:
            self.edit_manifest(root, lambda m: next(x for x in m["scripts"] if x["file"] == "src/server/WorldLease.luau").update({"path": "ReplicatedStorage.MarketReign.WorldLease"}))
            with self.assertRaisesRegex(ValueError, "Missing module dependency"):
                build.load_inputs(root)

    def test_missing_required_module_rejected(self):
        with self.project() as root:
            with (root / "src/server/MarketServer.server.luau").open("a") as stream:
                stream.write("\nrequire(script.Parent.NonexistentModule)\n")
            with self.assertRaisesRegex(ValueError, "Missing module dependency"):
                build.load_inputs(root)

    def test_changed_base_must_be_reviewed(self):
        with self.project() as root:
            with (root / self.manifest["base"]["file"]).open("ab") as stream:
                stream.write(b"changed")
            with self.assertRaisesRegex(ValueError, "Base place hash changed"):
                build.load_inputs(root)

    def test_stale_script_in_export_rejected(self):
        changed = self.rewrite_property(self.candidate, "ServerScriptService.MarketReign.WorldCheckpoint", "Source", lambda _: b"return {Version=8}")
        with self.assertRaisesRegex(ValueError, "Stale source.*WorldCheckpoint"):
            self.binary_check(changed)

    def test_duplicate_embedded_script_path_rejected(self):
        changed = self.rewrite_property(self.candidate, "ServerScriptService.MarketReign.WorldCheckpoint", "Name", lambda _: b"WorldLease")
        with self.assertRaisesRegex(ValueError, "Missing or ambiguous instance"):
            self.binary_check(changed)

    def test_disabled_or_wrong_context_entry_point_rejected(self):
        for name, value, error in (("Disabled", b"\1", "Disabled entry"), ("RunContext", (2).to_bytes(4, "big"), "Unexpected RunContext")):
            with self.subTest(property=name):
                changed = self.rewrite_property(self.candidate, "ServerScriptService.MarketReign.MarketServer", name, lambda _, value=value: value)
                with self.assertRaisesRegex(ValueError, error):
                    self.binary_check(changed)

    def test_unknown_script_is_not_carried_forward(self):
        changed = self.rewrite_property(self.base.data, "ServerScriptService.MarketReign.WorldTests", "Name", lambda _: b"UnexpectedTestRunner")
        with self.assertRaisesRegex(ValueError, "Unexpected or duplicate script"):
            rbxl.overlay(rbxl.Place(changed), self.manifest["scripts"], self.sources)

    def test_extra_script_in_artifact_rejected(self):
        entries = self.manifest["scripts"] + [{"file": "src/Extra.luau", "path": "ServerScriptService.MarketReign.Extra", "class": "ModuleScript"}]
        changed = rbxl.overlay(self.base, entries, {**self.sources, "src/Extra.luau": b"return {}"})
        with self.assertRaisesRegex(ValueError, "inventory count"):
            self.binary_check(changed)

    def test_unsupported_terrain_data_preserved_and_tampering_detected(self):
        place = rbxl.Place(self.candidate)
        opaque = next(x for x in place.chunks if x.tag == b"PROP" and rbxl.property_header(x.body)[1] == "VoxelGridAssetContentMap")
        self.assertIn(opaque.raw, self.base.asset_chunks())
        damaged = self.candidate.replace(opaque.raw, rbxl.chunk(opaque.tag, opaque.body[:-1] + bytes([opaque.body[-1] ^ 1])), 1)
        with self.assertRaisesRegex(ValueError, "asset/configuration chunks changed"):
            self.binary_check(damaged)

    def test_existing_references_and_script_metadata_preserved(self):
        self.binary_check(self.candidate)  # Includes all original referents, parents and script metadata.

    def test_repeated_builds_are_byte_identical(self):
        self.assertEqual(self.candidate, rbxl.overlay(self.base, self.manifest["scripts"], self.sources))

    def test_new_mapped_module_is_added_and_compiles(self):
        with self.project() as root:
            (root / "src/BuildRegressionProbe.luau").write_text("return {Ready=true}")
            self.edit_manifest(root, lambda m: m["scripts"].append({"file": "src/BuildRegressionProbe.luau", "path": "ServerScriptService.MarketReign.BuildRegressionProbe", "class": "ModuleScript"}))
            destination, report = build.build(root, root / "release", self.lune)
            self.assertEqual(report["Compiled"], len(self.sources) + 1)
            place = rbxl.Place((destination / build.PLACE_NAME).read_bytes())
            probe = place.resolve("ServerScriptService.MarketReign.BuildRegressionProbe")
            self.assertEqual(place.property(probe, "SerializedOverrides"), b"")

    def test_unicode_bom_crlf_and_source_update_round_trip(self):
        with self.project() as root:
            path = root / "src/shared/MarketConfig.luau"
            text = "-- updated source: \u2603 caf\u00e9\n" + path.read_text(encoding="utf-8-sig")
            path.write_bytes(b"\xef\xbb\xbf" + text.replace("\n", "\r\n").encode())
            destination, _ = build.build(root, root / "release", self.lune)
            place = rbxl.Place((destination / build.PLACE_NAME).read_bytes())
            self.assertEqual(place.property(place.resolve("ReplicatedStorage.MarketReign.MarketConfig"), "Source"), text.encode())

    def test_invalid_luau_does_not_expose_partial_export(self):
        with self.project() as root:
            previous, _ = build.build(root, root / "previous", self.lune)
            old_bytes = (previous / build.PLACE_NAME).read_bytes()
            with (root / "src/shared/MarketConfig.luau").open("a") as stream:
                stream.write("\nthis is not valid luau !!!")
            with self.assertRaisesRegex(ValueError, "reader/compile failed"):
                build.build(root, root / "failed", self.lune)
            self.assertFalse((root / "failed").exists())
            self.assertFalse(list(root.glob(".place-build-*")))
            self.assertEqual(old_bytes, (previous / build.PLACE_NAME).read_bytes())

    def test_existing_output_is_never_overwritten(self):
        with self.project() as root:
            existing = root / "existing"
            existing.mkdir()
            (existing / "marker").write_text("keep me")
            with self.assertRaisesRegex(ValueError, "Output already exists"):
                build.build(root, existing, self.lune)
            self.assertEqual((existing / "marker").read_text(), "keep me")

    def test_source_edit_after_export_makes_verify_fail(self):
        with self.project() as root:
            destination, _ = build.build(root, root / "release", self.lune)
            with (root / "src/server/WorldLease.luau").open("a") as stream:
                stream.write("\n-- changed after export\n")
            with self.assertRaisesRegex(ValueError, "Stale source"):
                build.verify(destination / build.PLACE_NAME, root, self.lune)

    def test_source_change_during_verification_aborts_build(self):
        with self.project() as root:
            real_run = subprocess.run

            def run_then_edit(command, **kwargs):
                result = real_run(command, **kwargs)
                if "run" in command:
                    with (root / "src/server/WorldLease.luau").open("a") as stream:
                        stream.write("\n-- changed during build\n")
                return result
            with patch.object(build.subprocess, "run", side_effect=run_then_edit):
                with self.assertRaisesRegex(ValueError, "Inputs changed during verification"):
                    build.build(root, root / "failed", self.lune)
            self.assertFalse((root / "failed").exists())

    def test_truncated_place_and_missing_end_rejected(self):
        for data in (self.candidate[:20], self.candidate[:-10], self.candidate + b"trailer"):
            with self.subTest(size=len(data)), self.assertRaises(ValueError):
                rbxl.Place(data)

    def test_lz4_and_uncompressed_asset_chunks_are_retained(self):
        import lz4.block
        opaque = next(x for x in self.base.chunks if x.tag == b"PROP" and rbxl.property_header(x.body)[1] == "VoxelGridAssetContentMap")
        for compressed in (False, True):
            with self.subTest(compressed=compressed):
                raw = lz4.block.compress(opaque.body, store_size=False) if compressed else opaque.body
                replacement = opaque.tag + struct.pack("<III", len(raw) if compressed else 0, len(opaque.body), 0) + raw
                base = rbxl.Place(self.base.data.replace(opaque.raw, replacement, 1))
                candidate = rbxl.Place(rbxl.overlay(base, self.manifest["scripts"], self.sources))
                self.assertEqual(base.asset_chunks(), candidate.asset_chunks())


if __name__ == "__main__":
    unittest.main(verbosity=2)
