# Shift chart tiers

The user selected a tier shift, not uniform clock compression:

| Visible choice | Existing candle series used |
| --- | --- |
| 1m (default) | 5m / 300 simulated seconds |
| 5m | 15m / 900 simulated seconds |
| 15m | 1h / 3,600 simulated seconds |
| 1h | 1D / 86,400 simulated seconds |

There are four visible choices. The old one-minute series is hidden from the selector, and there is no separate visible 1D choice. All stored series remain available internally. Existing daily quote calculations, saved candles, OHLCV, timestamps, chart drawings, server subscription keys and checkpoint schema retain their original meanings. The time axis remains the original simulation clock; this is not a claim that every new minute has a common duration across tiers.

`ChartTimeframes` centralizes the visible labels and default. `ChartView` uses those labels for icons, tooltips and controls; desktop, portrait and landscape spacing uses the four-choice count. `TerminalUI` updates the initial selection and overlay. `MarketClient` initially subscribes to the existing five-minute series. No market-maker, bot, matching, funding, simulation-speed or server code changes are included.

Frozen candidate sources and SHA256 manifest are under `candidate/` and `manifest.json`; the scoped patch is `change.patch`. Actual Studio sources supplied the candidate base. The local `src` files received the same scoped edits while preserving their unrelated differences from Studio. Original local files are under `repo-before/`.

Validation passed before installation:

- Four candidate Luau modules compile.
- 148 native integration checks pass using detached, unparented modules and GUI objects. Checks include actual selector callbacks, artwork, placement cancellation, non-overlapping bounds at desktop/portrait/landscape sizes, overlay labels and client defaults.
- Three saved histories across BX/BT/BG retain exact original OHLCV references, timestamps, spacing and daily quote baselines under each selected tier. This is functional mapping validation, not a new independent trader-policy experiment.
- Existing native chart suites pass: 39 viewport, 40 drawing-tool and 10 paint-pool cases.
- Live installed source and editor buffers were unchanged during validation. The running Play session was not interrupted.

The first native runner attempt used `.Run()` on existing test modules that return functions. That harness error is preserved in `native-validation-harness-error.json`; the runner was corrected without changing the frozen production candidate, then the complete validation passed in `native-validation.json`.

The user explicitly authorized stopping Play and installing after validation. Installation completed in Edit at **2026-10-22T16:20:08Z**. `Install.luau` rechecked original sources and editor buffers, wrote a local backup before mutation, installed four presentation modules, and verified exact source/editor readback. `installation.json` records the outcome and `studio-before-install.json` holds the original sources. A separate full readback in `final-readback.json` verifies all 106 modules: the four intended presentation modules match the frozen candidate, and all other modules remain unchanged. Nothing was published or saved as an RBXL, and no trader-policy candidate was installed. Studio is left in Edit; the updated controls load on the next Play.

`timeframe-preview.png` compares sixty completed original one-minute candles with sixty completed existing five-minute candles from the same captured BX world. They cover different time spans; all original price data is preserved. This demonstrates the requested chart aggregation and does not certify a change in underlying market dynamics.
