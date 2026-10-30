# Dark Focus — Get Funded! Stats UI Kit

Quiet surfaces and clear numbers. A larger P&L card anchors a compact, focused dashboard.

Open index.html locally. This kit works offline and has no build step or external dependency.

## Included
- 01-desktop.png, 02-mobile.png, 03-components.png: rendered previews of this editable kit.
- source-concept.png: original generated direction from the previous request.
- index.html, kit.css, kit.js, fixture.js: responsive interactive components and fixture-driven preview.
- design-tokens.json: colors, typography, spacing, breakpoints, motion, and component sizes.
- assets/svg/: 16 original editable icons and 9 text-free background components.
- assets/png/: matching transparent exports. Icons are 256 × 256; surfaces are exported at 2×.
- assets/icons-atlas.png and assets/icons-atlas.json: 1024 × 1024 image with exact icon rectangles.
- roblox/StatsKit.luau: a self-contained native component module with this theme.
- roblox/StatsKit.rbxmx: importable Folder containing the ModuleScript and a disabled Example LocalScript.
- roblox/Example.client.luau: same explicitly labeled sample entrypoint.
- validation-results.json: export, layout, data-state, interaction and contrast checks.

## Preview interactions
Account size and scope filter a synthetic set of closing fills. The initial All + Lifetime aggregate matches the supplied screenshot: -$56,808.75 net, 12 wins / 41 trades, 0.45 win/loss ratio and 0.18 profit factor. The individual fills, date groups and tier allocations are invented fixtures, not exported account history.
Dated history recomputes ALL six metrics using only dated fixture rows. Current includes only usable fixture accounts.
Scenario examples cover profitable days, no losing trades, break-even trades, partial history, loading, empty and error. Reset restores the original aggregate.
Help works by pointer and keyboard, Escape closes dialogs, and reduced motion respects the OS preference.
Other navigation buttons demonstrate the component; they do not include other game screens.

## Use in Roblox Studio
1. Import roblox/StatsKit.rbxmx as a local model into StarterPlayer > StarterPlayerScripts. This creates the "Dark Focus Stats Kit" Folder with a StatsKit ModuleScript and disabled Example LocalScript.
2. For a preview, enable Example and run Play. It creates a separate ScreenGui using sample totals. Remove or disable Example when done.
3. For integration, require the StatsKit module and call Kit.Mount(player.PlayerGui, aggregate, options).
4. Keep the returned controller and call controller:Update(newAggregate, nextOptions) when server stats or scope change. Call controller:Destroy() on unmount.
5. Reuse Kit.Panel, Kit.Label, Kit.Button, Kit.Progress and Kit.Metric separately if replacing only the Stats page.
No existing source or place was changed by this kit. The native library was validated with temporary unparented instances; production screen integration remains a separate step.

## Native options
- Scope: "All", "5K", "10K", or "25K"; Period: "Life", "Current", or "Dated".
- AccountLabel: displayed funded-account name.
- OnFilter(scopeKey, period): return the matching server aggregate to commit the change. Without this callback, native filters are disabled, so old numbers are never shown with a new scope label.
- OnNavigate(name), OnSettings(), OnRetry(): connect these to the existing game handlers.
- State: "Ready", "Loading", "Empty", or "Error".
The native period button cycles the three scopes. The browser preview uses a select menu. Native phone layout uses a compact title instead of the full sidebar.

## Data contract
Kit.FromAggregate accepts the fields already read by src/shared/StatsView.luau:
Net, Gains, Loss (positive magnitude), Wins, Losses, Even, Trades, AvgWin, AvgLoss (positive magnitude), WinRate, WinLossRatio, ProfitFactor, NoLosses, DailyComplete, DayWinRate, WinningDays, DayCount, BestDayShare, Partial, CountUnknown, Attempts, Blown.
Ratios and percentages arrive from the exchange. Rates are fractions (0.2927), not whole percentages (29.27).
Partial or CountUnknown suppresses trade ratios while retaining total net P&L. Missing dates suppresses daily metrics. Best-day share requires positive net profit and can exceed 100%. Zero gross loss is infinity only when positive gross wins exist; no activity is unavailable.
The progress bar for gross P&L shows gain / (gain + absolute loss), whereas profit factor is gain / absolute loss. They are deliberately distinct.

## Assets and typography
Use SVGs for editing and PNGs for Roblox upload. Text-free surfaces may be sliced; use the asset manifest's recommended slice center in source PNG pixels.
For the icon atlas, upload the PNG and apply ImageRectOffset / ImageRectSize from icons-atlas.json. No asset uploads were performed.
The preview uses Segoe UI / Arial system fonts. Roblox uses GothamBold for headings and Gotham for body text. These are intentional available-font equivalents rather than identical font files. Lilita One retains its SIL Open Font License in assets/fonts/OFL.txt.
The original vector icons and component assets may be reused and modified in this project.

## Layout and motion
Desktop: larger P&L card and compact secondary stats.
At tablet widths, cards form two columns; phone width uses a single scrollable column. Targets are at least 44 px high. Browser button feedback is 80–140 ms with 1 px press travel; reduced motion removes transitions.
Native components use immediate selection feedback and keyboard/gamepad selectable controls. Panel objects remain editable Roblox GUI instances, not flattened screenshots.

## Regenerate
From the project root: python tools/asset-build/stats-kit/build.py, then node tools/asset-build/stats-kit/export.cjs, then python tools/asset-build/stats-kit/package.py.
Export uses the locally installed Chrome and bundled Sharp / Playwright paths recorded in the helper. The final ZIP runs without those development tools.
