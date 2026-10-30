# Get Funded!

**Open `Get Funded!.rbxl` in the repository root. It is the current place.**
Runtime scripts come from `src/`; builds take scene assets from the pinned
`build/scene-input.zip`, not from unsaved Studio changes.

## Repository map

- `src/server/`, `src/shared/`, `src/client/`: runtime source, grouped by responsibility.
- `src/tests/`: regression suites and test helpers.
- `build/`: source-to-instance manifest and pinned scene input.
- `tools/place-build/`: canonical offline builder and structural verification.
- `tools/protection-safety/`: detached gameplay harness and runner tests.
- `tools/market-safety/`: reusable attack simulations and optional saved-position replay.
- `tools/studio/`: manual Studio previews and diagnostic fixtures; review each script's context before use.
- `tools/experiments/`: historical installers, source patches, benchmarks and dated investigations. These are not release entry points; many require local captures in `output/` or `backups/` and target older behavior.
- `tools/asset-build/`, `tools/asset-exports/`: asset generators/export helpers; some need the original external artwork or local rendering dependencies.
- `tools/runtime/`: the bundled Windows Lune executable.
- `assets/`: icons, thumbnails, UI kits, design references, advertising source and video assets.
- `docs/`: [runtime architecture](docs/architecture.md) and [saved-data compatibility](docs/saved-data.md).

`output/`, `tmp/`, and `backups/` are ignored local working/recovery directories.
They are not required for a fresh build. Do not delete a saved-world capture or
recovery file merely because it lives there. Generated test reports belong under
`output/`; routine change summaries belong in chat, not new Markdown reports.

## Setup

Use Python 3.12+ and Lune 0.10.5. Windows includes `tools/runtime/lune.exe`;
the builder also accepts `--lune PATH` or Lune on PATH. From the repository root:

```powershell
python -m venv .venv-build
& .venv-build/Scripts/python.exe -m pip install -r tools/place-build/requirements.txt
```

## Test and build without replacing the current place

```powershell
& .venv-build/Scripts/python.exe -m unittest discover -s tools/place-build -p "test_*.py" -v
& .venv-build/Scripts/python.exe -m unittest discover -s tools/protection-safety -p "test_*.py" -v
& .venv-build/Scripts/python.exe tools/check_release.py --isolated
```

The release check runs every `*Tests.luau` suite recursively discovered in `src/`,
compiles every original source, rejects incomplete/malformed results, and builds
against the exact tested inputs. It writes a fresh `output/checks/<run-id>/`
containing logs, results, a source snapshot, `release-check.json`, and an isolated
`place/Get Funded - Source Build.rbxl`. The current place and its verification
report remain untouched. These commands use offline service substitutes; they do
not publish or access production services.

For a structural build without gameplay tests, choose a new output directory:

```powershell
& .venv-build/Scripts/python.exe tools/place-build/build.py build --output output/builds/local-check
& .venv-build/Scripts/python.exe tools/place-build/build.py verify --place "output/builds/local-check/Get Funded - Source Build.rbxl"
```

When intentionally updating the root current place, run `tools/check_release.py`
without `--isolated`. It replaces `Get Funded!.rbxl` atomically only after all
checks pass and updates `build/current-verification.json`. The structural builder
without `--output` also replaces the root place. Review and preserve scene edits
before either command: builds always use the pinned scene, not the open editor.

`verify` compares an artifact with current disk source. It checks source hashes,
script inventory, Roblox paths/classes, compilation, entry-point settings and
preserved non-script assets. Hashes normalize UTF-8 BOMs and CRLF to UTF-8/LF;
all other source content is exact. Failed builds retain the previous current
place/report. Structural checks do not replace native client/server playtesting.

## Targeted tests

```powershell
python tools/protection-safety/prepare.py --output output/test-run
& tools/runtime/lune.exe run output/test-run/run.luau TestLiquidityTests TradeLimitsTests
```

The harness copies nested sources into flat `original/` and `candidate/` snapshots
and rejects duplicate filenames before copying. Static Roblox module requires
are adapted only in `candidate/`; originals are compiled unchanged. Unsupported
services throw instead of connecting. New source filenames must be unique.

Accounting/progression fixtures use `TestLiquidity.FillAt` for full settlement
with real counterpart orders, adequate depth and a fresh execution window.
`PlaceAt` exercises the ticket; `PrintPrice` walks real trades through the collar.
Thin-book checks use exact `Offer` quantities and direct submissions so the
fixture cannot hide partial fills or queued closes.

Run the six detached market-safety scenarios:

```powershell
& .venv-build/Scripts/python.exe tools/market-safety/validate.py --output output/market-safety-check
```

The optional `--snapshot PATH --player PLAYER_KEY` replays a read-only checkpoint
export in detached modules. Supply your own local capture; none is required by
the standard suite. Each validation output directory must be new. Replay checks
migration ledgers, closure, capital conservation and deterministic restart. The
separately reported bot-refresh scenario intentionally adjusts detached bot capital.

## Updating sources and scene assets

Every source must have a `file`, Roblox `path`, and `class` entry in
`build/place-manifest.json`. Update paths, tooling and tests together when moving
files. An explicit `previousPath` is needed only for a Roblox instance relocation,
not a filesystem move. Missing/unmapped files, ambiguous paths, unexpected embedded
scripts and unresolved dependencies fail the build. New static `require` forms
need checker and harness support plus regression coverage.

The builder preserves non-script binary chunks byte for byte, including Terrain
properties unsupported by the bundled Lune reader. Existing object references and
script metadata remain stable. It changes script source, declared additions or
relocations, and executable entry-point settings only.

To change scene assets, review the edited current place, update the pinned scene
archive and its member/archive hashes in the manifest, then rerun checks. Never
rebuild over unsaved scene edits. The builder does not refresh the editor preview:
`TerminalUI` builds the current UI at runtime.

For the static preview, run `tools/studio/RefreshStudioPreview.luau` in Studio Edit
mode after syncing sources. It renders an isolated sample exchange and replaces
the preview only after successful layout, without accessing DataStores. Export
using Studio's Download a Copy, then review and repin the scene as above.

Saved-data compatibility is independent of export equality. Follow
[the compatibility requirements](docs/saved-data.md), including V28 recovery,
policy downgrade fences and read-only saved-world replay before a deployment.
Publishing, production-data access and real teleport testing are separate steps.
