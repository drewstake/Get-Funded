# Mobile "Arcade Clean" — implementation and verification (2026-10-03)

Target: `approved-mobile-design.png` (portrait without the "Position • None" card, plus landscape).
Studio place verified: **Get Funded! (placeId 137759823569682)**, Edit mode, `ReplicatedStorage.MarketReign` / `StarterGui.MarketReign`.

## Files changed
| File | Change |
|---|---|
| `src/shared/TerminalUI.luau` | Phone Trade screen rebuilt (`phoneTrade`, `accountStrip`, `phoneNav`, new `mobileDock`, `positionBar`, `riskControls`); stacked option for `tradeButtons`; More menu; Level 2 in Order settings sheet; retained-dock guard (`dockKey`); strip goal readout; thin chart rim on phones. Desktop paths untouched. |
| `src/shared/ChartView.luau` | Phone landscape "inline" header (timeframes beside selector/price, no toolbar row); compact header/toolbar on very short charts; more price-axis ticks on phones; scaled last-price label on phones. |
| `tools/studio/MobileArcadePreview.luau` | New Edit-mode multi-size fixture (private in-memory engine, no remotes/DataStores). |
| `tools/studio/AuditMobileArcadeClean.client.luau` | Adapted copy of `AuditColorfulUI` for phone usable areas and the new nav/sheets. |
| Diffs | `TerminalUI.diff`, `ChartView.diff` in this folder. Backups: `backups/mobile-arcade-clean-20261003/` (sources + pre-change local .rbxl). |

## What was implemented
**Portrait:** 44px header ("Get Funded!", exceptional status only, an Activity pill only while positions/orders exist) → one 56px account strip (live Balance, Open P&L, Next goal "n / N trades" + yellow bar) → chart that takes *all* remaining height (header with BX selector, live price/day change, chart-tools button; timeframes row; plot, candles and right axis resize with it) → Quantity −/value/+ card beside a **Risk controls** (SL / TP summary) card → equal BUY / SELL (52px) → 4-item nav (Trade, Progress, Stats, More). No empty position strip: a compact `LONG 2 BX · live P&L · Close` row appears **only** while the selected market has a position.
**Landscape:** title + inline account strip in one row; chart on the left with timeframes inline in its header; right column (Qty stepper, Risk controls, BUY/SELL stacked; side-by-side only on very short screens or while a position row is shown); compact horizontal nav.
**Preserved access:** More → Leaderboard, Shop, Positions & orders, Order type & Level 2 (Market/Limit, limit price, quantity, protection cards, Level 2 with its entitlement/loading states), Trade history, How to play, Reset Account, Settings. Chart tools/Auto/timeframes/symbol unchanged. Same order, close, cancel, pending, rejection and double-submit handlers. Values are live session data (nothing from the mockup is hard-coded).

## Sizes checked (device → usable GUI area after top bar and safe insets)
390×844 → 390×692 · 844×390 → 750×312 · 320×568 → 320×490 · 430×932 → 430×780 · 568×320 → 568×262 · desktop 1280×720 and 1920×1080.

## Checks actually run
- **Compile:** `luau-compile` on all 57 `src` files — pass. `luau-analyze`: no new unknown globals.
- **Layout fixture (Edit, real native GUI):** all phone sizes, no render/chart errors, no overflowing text, nothing outside the workspace; primary buttons ≥44px (BUY/SELL 46–52px). Portrait plot 370×296 at 390×692 (was a ~150px strip in `current-portrait.png`).
- **Client Play audit** (`AuditMobileArcadeClean`) at 10 sizes incl. all overlays/sheets: Trade, overlays and sheets clean. Only findings: Stats bar fills reported off-screen at every size including desktop 1280×720 — pre-existing, Stats interior not touched.
- **Live Play with in-memory stores** (MarketServer temporarily patched to in-memory DataStores + a QA reject hook, restored afterwards; hash re-verified): guided first trade (coach steps target the new Quantity card, BUY/SELL and the position row's Close), market BUY fill → position row + live P&L + "1 open" pill + SL/TP chart lines, close via confirm → balance/goal updated, Risk controls Save (TP off persisted server-side) and Cancel (draft discarded), server rejection (toast, no position, buttons stable; double-tap sent exactly one request per the server action log), SELL short, Limit mode (LIMIT BUY/SELL labels, caption shows limit), resting limit order → chart marker + "1 order" pill → Activity → Cancel, symbol BX→BT and 1m→5m, nav to Progress, Stats, More→Leaderboard, More→Shop (close returns), back to Trade; chart kept painting behind popups.
- **Touch/chart input:** input surface aligned with plot at 390×692, 750×312 (inline), 320×490; one-finger pan, two-finger pinch zoom, touch horizontal-line drawing, Auto, and stop-line touch drag (Protection drag) all work.
- **ValidateChartInteractions (mouse/keyboard):** desktop 203 pass / 4 fail, portrait geometry 196/11 — identical with the pre-change ChartView, so the failures are pre-existing expectations of the old script, not regressions.
- **Engine/unit suites:** TradePreferences 9, SingleAccount 21, TradeLimits 53, TradeAmendment, Security, Market 13, ChartViewport, ChartTools, ChartPaintPool — all pass.
- **Desktop regression:** 1280×720 and 1920×1080 render unchanged.
- **Studio sync:** changed modules patched by line diff with FNV-1a checks; final Studio = local for `TerminalUI` (393eb5a6) and `ChartView` (7332459f). `RefreshStudioPreview` workflow re-run (31 candles). All QA objects removed; `MarketServer` restored (24fd053d).

## Limitations
- **Place not saved:** the Studio connection has no save command, so the open place holds the synced change but no new .rbxl was written. The only local `Get Funded!.rbxl` predates the Studio place (it lacks 18 current modules), so patching it would give a misleading file. Save from Studio (File → Save to File As… → `output\Get Funded! Mobile Arcade Clean.rbxl`); do not publish.
- Phone sizes were emulated by sizing the workspace to usable areas, not on physical devices; mouse injection stood in for taps in Play.
- 568×320 (oldest small phones, landscape): chart plot is short (~90px) and the live-price tag can touch the Auto button.
- The mockup's chart grid is not added (the game removed grid lines earlier); the chart-tools button keeps the existing "···" glyph rather than a star.
- 3 unrelated modules (UIFeedback, TradeStats, WorldConfig) differ from local files only by line endings; content is identical.

## Revision 2 (same day)
- **Removed the "Get Funded!" title** from the phone Trade screen in portrait and landscape. Portrait: the account strip now sits at the top; a slim row appears above it only for the "n open / n orders" Activity pill or an exceptional status (e.g. Trading paused). Landscape: the account strip spans the header row. Portrait chart at 390×692 grew from 386 to 424px tall.
- **Auto button now matches the price-axis tag**: same width (axis column − 4), 24px tall, same type size (12 phone / 14 desktop) and 6px corners, aligned under the live-price tag. This component is shared, so desktop Auto changed the same way (1280×720: 100×24, same as the tag).
- Verified in Play (in-memory stores, restored after): 390×692 and 750×312 with no title, pill row with an open position, desktop 1280×720; no render errors. Studio = local: TerminalUI a53bedad, ChartView d113234b; MarketServer restored (24fd053d); Studio preview refreshed. Pre-revision copies: `backups/mobile-arcade-clean-20261003/before-title-auto/`. Screenshots 13–15.

## Revision 3 (same day)
- **Removed the "n open / n orders" button in portrait.** Nothing sits above the account strip in portrait any more (except an exceptional status such as Trading paused). Open positions remain visible and closable from the position row above Quantity (tapping its left side opens Activity); positions, working orders and history stay in More → Positions & orders. Landscape keeps the button in the header row.
- Verified in Play (in-memory stores, restored after) with an open long: portrait shows no button and the strip at the top; landscape still shows it. Studio = local: TerminalUI 99488477; MarketServer restored (24fd053d). Pre-revision copy: `backups/mobile-arcade-clean-20261003/before-pill-removal/`. Screenshot 16.
