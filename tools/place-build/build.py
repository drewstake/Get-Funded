"""Canonical offline build and verification entry point. See --help.

No Roblox service access, Studio mutation, or publishing. Paths are resolved
relative to the repository, so invoking this command from another cwd is safe.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from rbxl import Place, need, overlay

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MANIFEST = Path("build/place-manifest.json")
PLACE_NAME = "Get Funded - Source Build.rbxl"
CURRENT_PLACE = "Get Funded!.rbxl"
CURRENT_REPORT = Path("build/current-verification.json")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def normalize(data):
    return data.decode("utf-8-sig").replace("\r\n", "\n").encode("utf-8")


def under(root, relative):
    path = (root / relative).resolve()
    need(path.is_relative_to(root.resolve()) and not Path(relative).is_absolute(), f"Path escapes repository: {relative}")
    return path


def load_inputs(root=ROOT):
    manifest_bytes = (root / MANIFEST).read_bytes()
    manifest = json.loads(manifest_bytes)
    need(manifest["version"] == 1, "Unsupported manifest version")
    sources, paths = {}, set()
    for item in manifest["scripts"]:
        file, path, cls = item["file"], item["path"], item["class"]
        need(file.startswith("src/") and file.endswith(".luau"), f"Invalid source file: {file}")
        need(file not in sources and path not in paths, f"Duplicate manifest entry: {file} / {path}")
        stem = Path(file).name[:-5]
        expected = "Script" if stem.endswith(".server") else "LocalScript" if stem.endswith(".client") else "ModuleScript"
        name = stem.removesuffix(".server").removesuffix(".client")
        need(cls == expected and path.rsplit(".", 1)[-1] == name, f"File/class/name mismatch: {file}")
        parent = path.rsplit(".", 1)[0]
        need(parent in manifest["containers"], f"Undeclared parent: {path}")
        if cls == "Script":
            need(parent.startswith("ServerScriptService."), f"Server script exposed to clients: {path}")
        if cls == "LocalScript":
            need(parent in ("ReplicatedFirst", "StarterGui.MarketReign", "StarterPlayer.StarterPlayerScripts"), f"Invalid client entry point: {path}")
        sources[file] = normalize(under(root, file).read_bytes())
        paths.add(path)
    disk_sources = {p.relative_to(root).as_posix() for p in (root / "src").rglob("*") if p.suffix in (".luau", ".lua")}
    need(set(sources) == disk_sources, f"Source inventory mismatch; unmapped={sorted(disk_sources-set(sources))}, missing={sorted(set(sources)-disk_sources)}")
    base_path = under(root, manifest["base"]["file"])
    base_bytes = base_path.read_bytes()
    if "member" in manifest["base"]:
        need(sha(base_bytes) == manifest["base"]["archiveSha256"], "Base place hash changed; scene archive must be reviewed")
        # Read the pinned member in memory; never extract another editable place.
        with zipfile.ZipFile(base_path) as archive:
            need(archive.namelist().count(manifest["base"]["member"]) == 1, "Missing or duplicate scene archive member")
            base_bytes = archive.read(manifest["base"]["member"])
    need(sha(base_bytes) == manifest["base"]["sha256"], "Base place hash changed; review the new scene/configuration before updating the manifest")
    base = Place(base_bytes)
    for path, cls in manifest["containers"].items():
        need(base.class_name(base.resolve(path)) == cls, f"Wrong container class: {path}")
    previous_paths = set()
    for item in manifest["scripts"]:
        previous = item.get("previousPath")
        if previous is not None:
            need(previous not in paths and previous not in previous_paths, f"Ambiguous script relocation: {previous}")
            previous_paths.add(previous)
            ref = base.resolve(previous)
            need(base.class_name(ref) == item["class"], f"Relocation class mismatch: {previous}")
            need(base.names[ref] == item["path"].rsplit(".", 1)[-1], f"Relocation must preserve script name: {previous}")
    validate_dependencies(manifest["scripts"], sources)
    snapshot = {"ManifestSha256": sha(manifest_bytes), "BaseSha256": sha(base_bytes),
                "Sources": {file: sha(data) for file, data in sorted(sources.items())},
                "Builder": {name: sha(normalize((HERE / name).read_bytes()))
                            for name in ("build.py", "rbxl.py", "inspect.luau", "requirements.txt")}}
    return manifest, sources, base, snapshot


def validate_dependencies(entries, sources):
    # Covers the project's current static require forms. An unfamiliar form
    # fails closed and must be reviewed; this is deliberately not a Luau parser.
    targets = {item["path"]: item for item in entries}
    for item in entries:
        text = sources[item["file"]].decode()
        text = re.sub(r'game:GetService\(["\'](\w+)["\']\)', r'game.\1', text)
        text = re.sub(r':WaitForChild\(["\'](\w+)["\']\)', r'.\1', text)
        text = re.sub(r'--[^\n]*', '', text)
        for expression in re.findall(r'\brequire\s*\(([^)]*)\)', text):
            expression = expression.strip()
            if expression.startswith("script.Parent."):
                target = item["path"].rsplit(".", 1)[0] + expression[len("script.Parent"):]
            elif expression.startswith("game."):
                target = expression[5:]
            elif expression.startswith("root."):
                assignment = re.search(r'local\s+root\s*=\s*([\w.]+)', text)
                need(assignment is not None, f"Unresolved require alias: {item['file']}")
                prefix = assignment[1]
                if prefix == "script.Parent":
                    prefix = item["path"].rsplit(".", 1)[0]
                else:
                    if not prefix.startswith("game."):
                        alias = prefix.split(".")[0]
                        binding = re.search(r'local\s+' + re.escape(alias) + r'\s*=\s*(game\.\w+)', text)
                        need(binding is not None, f"Unresolved service alias: {item['file']}")
                        prefix = binding[1] + prefix[len(alias):]
                    need(prefix.startswith("game."), f"Unresolved require alias: {item['file']}")
                    prefix = prefix[5:]
                target = prefix + expression[4:]
            else:
                raise ValueError(f"Unreviewed require form in {item['file']}: {expression}")
            need(target in targets and targets[target]["class"] == "ModuleScript", f"Missing module dependency: {item['path']} -> {target}")
            if item["path"].startswith(("ReplicatedStorage.", "ReplicatedFirst.", "StarterGui.", "StarterPlayer.")):
                need(not target.startswith(("ServerScriptService.", "ServerStorage.")), f"Client requires server-only module: {target}")


def verify_binary(place, manifest, sources, base):
    entries = {item["path"]: item for item in manifest["scripts"]}
    scripts = place.scripts()
    need(len(scripts) == len(entries), "Script inventory count mismatch")
    for path, item in entries.items():
        ref = place.resolve(path)
        need(place.class_name(ref) == item["class"], f"Script class mismatch: {path}")
        need(place.property(ref, "Source") == sources[item["file"]], f"Stale source: {path}")
        need(place.property(ref, "LinkedSource") == b"", f"LinkedSource can override local code: {path}")
        if item["class"] != "ModuleScript":
            need(place.property(ref, "Disabled") == b"\0", f"Disabled entry point: {path}")
            need(place.property(ref, "RunContext") == bytes(4), f"Unexpected RunContext: {path}")
    need(place.asset_chunks() == base.asset_chunks(), "Non-script asset/configuration chunks changed")
    relocated = {base.resolve(item["previousPath"]): base.resolve(item["path"].rsplit(".", 1)[0])
                 for item in manifest["scripts"] if "previousPath" in item}
    for ref in base.instances:
        need(ref in place.instances and place.class_name(ref) == base.class_name(ref), "Existing reference changed")
        need(place.names[ref] == base.names[ref] and place.parents[ref] == relocated.get(ref, base.parents[ref]), "Existing hierarchy changed")
        if base.class_name(ref) in ("Script", "ModuleScript", "LocalScript"):
            for cid, prop in base.properties:
                if cid == base.instances[ref] and prop not in ("Source", "Disabled", "RunContext"):
                    need(base.property(ref, prop) == place.property(ref, prop), f"Existing script metadata changed: {base.path(ref)}.{prop}")


def lune_path(root=ROOT, explicit=None):
    candidate = explicit or shutil.which("lune") or root / "tools/runtime/lune.exe"
    path = Path(candidate).resolve()
    need(path.is_file(), "Lune 0.10.5 is required; install it or pass --lune PATH")
    version = subprocess.run([str(path), "--version"], capture_output=True, text=True, check=True).stdout.strip()
    need(version == "lune 0.10.5", f"Untested Lune version: {version}; expected lune 0.10.5")
    return path


def verify(place_path, root=ROOT, lune=None, inputs=None):
    manifest, sources, base, snapshot = inputs or load_inputs(root)
    data = place_path.read_bytes()
    verify_binary(Place(data), manifest, sources, base)
    with tempfile.TemporaryDirectory(prefix="get-funded-inspect-") as temp:
        inspection_path = Path(temp) / "inspection.json"
        result = subprocess.run([str(lune_path(root, lune)), "run", str(HERE / "inspect.luau"),
                                 str(place_path.resolve()), str(inspection_path)], capture_output=True, text=True)
        need(result.returncode == 0, "Independent place reader/compile failed:\n" + result.stdout + result.stderr)
        inspected = json.loads(inspection_path.read_text(encoding="utf-8"))
    need(len(inspected["Scripts"]) == len(manifest["scripts"]), "Independent reader inventory mismatch")
    seen = set()
    by_path = {item["path"]: item for item in manifest["scripts"]}
    for actual in inspected["Scripts"]:
        path = actual["Path"]
        need(path in by_path and path not in seen, f"Independent reader found unexpected/duplicate script: {path}")
        seen.add(path)
        expected = by_path[path]
        need(actual["Class"] == expected["class"] and actual["Source"].encode() == sources[expected["file"]], f"Independent reader source mismatch: {path}")
        if expected["class"] != "ModuleScript":
            need(actual["Disabled"] is False and actual["RunContext"] == "Enum.RunContext.Legacy", f"Independent reader entry point mismatch: {path}")
    need(inspected["Containers"] == manifest["containers"], "Independent reader container mismatch")
    need(inspected["Gui"] == {"Enabled": True, "ResetOnSpawn": False, "ScreenInsets": "Enum.ScreenInsets.CoreUISafeInsets"}, "ScreenGui configuration mismatch")
    need(load_inputs(root)[3] == snapshot, "Inputs changed during verification; rebuild from the new source")
    return {"Verified": True, "PlaceSha256": sha(data), "ScriptCount": len(seen), "Compiled": len(seen),
            "Instances": inspected["Instances"], "NonScriptChunksPreserved": len(base.asset_chunks()),
            "Inputs": snapshot, "Scripts": [{**item, "sha256": sha(sources[item["file"]])} for item in manifest["scripts"]],
            "Limitations": ["Offline structural/source verification; no gameplay execution or cloud services.",
                            "Non-code scene/configuration comes from the pinned base place, not unsaved Studio edits.",
                            "Lune cannot interpret Terrain.VoxelGridAssetContentMap; the binary verifier checks its original bytes are preserved."]}


def build(root=ROOT, output=None, lune=None, expected_inputs=None):
    inputs = load_inputs(root)
    manifest, sources, base, snapshot = inputs
    need(expected_inputs is None or snapshot == expected_inputs, "Inputs changed since regression tests; current place was not replaced")
    if output is None:
        current = under(root, CURRENT_PLACE)
        need(current != under(root, manifest["base"]["file"]), "Keep the pinned scene input separate from the current place")
        report_path = under(root, CURRENT_REPORT)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".place-build-", dir=report_path.parent) as temp:
            stage = Path(temp)
            artifact = stage / CURRENT_PLACE
            artifact.write_bytes(overlay(base, manifest["scripts"], sources))
            report = verify(artifact, root, lune, inputs)
            staged_report = stage / "verification.json"
            staged_report.write_bytes(json_bytes(report))
            previous = current.read_bytes() if current.exists() else None
            artifact.replace(current)  # Atomic replacement only after verification/compilation.
            try:
                staged_report.replace(report_path)
            except OSError:
                # A failed metadata write must not strand an unreported replacement.
                if previous is None:
                    current.unlink()
                else:
                    artifact.write_bytes(previous);artifact.replace(current)
                raise
        return root.resolve(), report
    destination = output.resolve()
    # Immutable bundles avoid a new place being paired with an old success report.
    need(not destination.exists(), f"Output already exists: {destination}; verify it or choose a fresh --output directory")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".place-build-", dir=destination.parent) as temp:
        stage = Path(temp) / "bundle"
        stage.mkdir()
        artifact = stage / PLACE_NAME
        artifact.write_bytes(overlay(base, manifest["scripts"], sources))
        report = verify(artifact, root, lune, inputs)
        (stage / "verification.json").write_bytes(json_bytes(report))
        # One directory rename after every check; a failed build exposes no bundle.
        stage.rename(destination)
    return destination, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "verify"))
    parser.add_argument("--output", type=Path, help="Optional explicit extra bundle; default replaces the single current Get Funded!.rbxl")
    parser.add_argument("--place", type=Path, help="Place file to verify against CURRENT source (verify only)")
    parser.add_argument("--lune", type=Path, help="Path to Lune 0.10.5")
    args = parser.parse_args()
    try:
        if args.command == "build":
            need(args.place is None, "--place is only valid for verify")
            output = under(ROOT, str(args.output)) if args.output and not args.output.is_absolute() else args.output
            destination, report = build(output=output, lune=args.lune)
            print(destination / (PLACE_NAME if output else CURRENT_PLACE))
        else:
            need(args.place is not None and args.output is None, "verify requires --place and does not accept --output")
            path = args.place if args.place.is_absolute() else ROOT / args.place
            report = verify(path, lune=args.lune)
        print(f"VERIFIED {report['ScriptCount']} scripts, {report['Compiled']} compiled; {report['NonScriptChunksPreserved']} non-script chunks preserved; SHA-256 {report['PlaceSha256']}")
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"BUILD/VERIFY FAILED: {error}\n")


if __name__ == "__main__":
    main()
