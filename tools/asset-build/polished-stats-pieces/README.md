# Polished Stats — Implementation Pieces

This pack follows the supplied Summary Banner layout: a full-width purple Total P&L banner, three blue stat cards, a shared daily-stat strip, and separate funded-account and scope dropdowns.

Open index.html for the assembled example and the downloadable component catalog. Everything works offline.

## Fastest route in Roblox

1. Insert roblox/PolishedStatsPieces.rbxmx as a local model. It contains:
   - Components: actual editable Frames, TextLabels, TextButtons, UIGradients, UIStrokes, UICorners and ImageLabels.
   - StatsPieces: the reusable ModuleScript.
   - Example: a disabled LocalScript.
2. Copy individual objects from Components into your existing ScreenGui. Choose HeroCard, TradeCard, AverageCard, FactorCard, DailyStats, FundedDropdown, ScopeDropdown, or FundedMenuOpen.
3. For a running demo, put the whole imported folder under StarterPlayer > StarterPlayerScripts, enable Example, and press Play. This creates a separate preview ScreenGui. Its dropdowns use explicitly synthetic fixtures.
4. To edit the entire assembled arrangement directly in Explorer, import roblox/AssembledPreview.rbxmx into StarterGui and enable the ScreenGui. This is a static hierarchy at the 1672 × 941 reference size; use the module when you need scaling and interactions.

Native navigation reuses the icon asset IDs already present in src/shared/TerminalUI.luau. No upload is required for those existing icons. Panels, borders, gradients, labels, progress bars, utility icons and dropdowns are native GUI objects.

## Files

- 01-assembled.png: rendered implementation preview.
- 02-components.png: visual map of the reusable pieces.
- 03-dropdown-open.png: open funded-account dropdown example.
- 04-artwork.png: transparent asset catalog.
- reference.png: the exact selected design reference.
- assets/svg and assets/png: text-free surfaces and reconstructed navigation/utility icons.
- assets.json: filenames, dimensions, native template names, existing icon IDs and recommended 9-slice rectangles.
- assets/icons-atlas.png and assets/icons-atlas.json: packed transparent icon sheet and pixel offsets.
- design-tokens.json: colors, fonts, corners, stroke and spacing.
- roblox/PolishedStatsPieces.rbxmx: editable native pieces, module and disabled example.
- roblox/AssembledPreview.rbxmx: separately importable static full screen.
- roblox/StatsPieces.luau and roblox/Example.client.luau: plain source.
- source/components.json: source scene graph for all native and browser pieces.
- source/demo-fixtures.json: synthetic aggregate snapshots for dropdown demonstrations.
- validation-results.json and roblox/validation-results.json: recorded verification.

## Reuse one component

Require the imported StatsPieces ModuleScript:

    local Kit = require(pathToImportedFolder.StatsPieces)
    local card = Kit.Create("TradeCard", yourFrame)
    card.Position = UDim2.fromOffset(24, 240)
    card:FindFirstChild("TradeValue", true).Text = "62.50%"
    card:FindFirstChild("TradeCaption", true).Text = "10 wins / 16 trades"

Templates retain the reference dimensions listed in the catalog. Text-free surfaces can be resized directly. For large structural changes, reflow their child GUI objects rather than stretching the whole component. The assembled module scales the reference canvas proportionally to the available screen; it does not invent a separate phone layout.

## Mount the assembled UI

    local controller = Kit.Mount(player.PlayerGui, aggregate, {
        Scope = "All",
        Period = "Life",
        OnFilter = function(scopeKey, period)
            return yourCachedStats[scopeKey][period]
        end,
        OnNavigate = function(pageName)
            openYourPage(pageName)
        end,
        OnAccountPicker = function()
            openYourActiveAccountPicker()
        end,
    })

    controller:Update(newAggregate, {Scope = selectedKey, Period = selectedPeriod})
    controller:Destroy()

OnFilter must return the server aggregate for the requested scope and period. It may yield. Errors, nil returns and superseded requests leave the previous selection and numbers intact. All six metrics update together after a successful response. The module performs no network calls and does not compute authoritative trading results.

Supply Scopes = {{Key = actualServerKey, Label = displayLabel}, ...} when your scope keys differ from the sample All / 5K / 10K / 25K keys. Period keys match StatsView.luau: Life, Current, Dated. Funded account selection and time scope are independent dropdowns. The active account picker in the sidebar remains a separate callback.

The existing src/shared/StatsView.luau selects aggregates from data.Scopes. For Dated it uses scope.Life.Dated; for other periods it uses scope[period]. An integration adapter should look up the chosen scope and return exactly that aggregate. Do not return Lifetime values for a different selection.

## API

- Kit.Create(templateName, parent): creates one editable component.
- Kit.FromAggregate(aggregate): produces six formatted metric descriptors.
- Kit.ApplyAggregate(root, aggregate): updates the assembled native screen.
- Kit.BindDropdown(root, trigger, items, selectedKey, onChoose): binds a component to a native popup. Items contain Key and Label; return false from onChoose to reject a selection.
- Kit.ShowHelp(root, title, body): opens a dismissible native help panel.
- Kit.Mount(parent, aggregate, options): creates the assembled UI and returns Root, Host, ScreenGui, Dropdowns, Filter, Update and Destroy.
- Dropdown controller methods: Open, Close, IsOpen, Get, Set, Choose, Destroy.

BindDropdown's root is the reference-coordinate canvas. Dropdowns use outside-click dismissal, Escape, selectable options and gamepad B dismissal. Controllers own their event connections; always call Destroy when unmounting.

## Stats fields

The aggregate adapter accepts the same values already used by src/shared/StatsView.luau:
Net, Gains, Loss, Wins, Losses, Even, Trades, AvgWin, AvgLoss, WinRate, WinLossRatio, ProfitFactor, NoLosses, DailyComplete, DayWinRate, WinningDays, DayCount, BestDayShare, Partial, CountUnknown, Attempts, Blown.

Loss and AvgLoss are positive magnitudes. WinRate and other percentages are fractions. Partial or unknown counts suppress unsupported ratios while keeping net P&L. Missing calendar dates suppress daily stats. Best-day share requires positive net profit and can exceed 100%. Infinity requires positive gains with zero losses.

The initial sample aggregate matches the image. Individual fills, tier allocations and date groupings in the example fixtures are synthetic. They are not exported player history.

## Artwork and 9-slicing

Every surface PNG excludes labels and values and has a transparent perimeter. Surface exports are twice the reference size. Icons are 256 × 256.

For a background PNG, upload it and configure an ImageLabel:

    image.ScaleType = Enum.ScaleType.Slice
    image.SliceCenter = Rect.new(left, top, right, bottom)
    image.SliceScale = 0.5

Use left/top/right/bottom from that asset's sliceCenter in assets.json. The 0.5 SliceScale preserves the reference corner size for a 2× source. Keep a sensible minimum size so fixed corners do not collide. Progress strips use their own thinner slice rectangle.

For an atlas icon, upload assets/icons-atlas.png, then set ImageRectOffset and ImageRectSize from assets/icons-atlas.json. Keep ScaleType.Fit on icons. The native UI already references existing game icon IDs; the included SVG/PNG navigation icons are newly reconstructed vector alternatives, not copies downloaded from Roblox. Their appearance is close but not pixel-identical. Utility icons and card shapes are editable primitives.

## Fonts and source

Native display text uses FredokaOne; supporting copy uses Gotham. The browser preview uses bundled Lilita One as an approximate rounded display equivalent and Segoe UI / Arial for body text. Font appearance varies slightly from the generated reference. The SIL Open Font License is bundled in assets/fonts/OFL.txt.

The original vector reconstructions and GUI component source may be reused and modified in this project. The existing Roblox icon assets retain their original ownership and permissions.

Development sources are in tools/asset-build/polished-stats-pieces. Run build.py, export.cjs and package.py from the project root to regenerate. The exporter uses local Chrome and bundled Sharp / Playwright. The delivered pack requires no development runtime.

No game source was replaced by creating this pack. Connect the module to live stats through the documented callbacks when integrating.

