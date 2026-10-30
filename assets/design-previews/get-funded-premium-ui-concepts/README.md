# Get Funded! — Premium UI concepts

Eight visual directions: approximately 70% professional trading terminal and 30% premium game interaction. These are design previews. The existing game UI, source and Roblox place files were not modified.

## How to review

Open `index.html`: the numbered comparison comes first, then eight detailed kits in order. Each kit contains a desktop dashboard, portrait mobile dashboard, palette, typography, component sheet, interaction states and a numbered motion map. The gallery also includes an interactive motion sample for each direction. BUY/SELL in those samples only demonstrate local visual feedback.

## Shared trading snapshot

| Item | Shared value |
| --- | --- |
| Persistent notice | Simulated market · Virtual funds |
| Navigation | Trade, Positions, Challenges, Learn |
| Virtual balance | $10,000 |
| Account value | $10,075 |
| Open result | ↑ Gain +$75 |
| Instrument / price | BLOX 100 / 1,250.00 |
| Change | ↑ +12.50 (+1.01%) |
| Timeframes | 1m, 5m selected, 15m, 1h |
| Quantity | 1 |
| SL · Stop loss | 1,230.00 |
| TP · Take profit | 1,280.00 |
| Position 1 | BLOX 100 · BUY · 2 · Entry 1,200.00 · ↑ Gain +$100 |
| Position 2 | TECH 50 · BUY · 1 · Entry 2,525.00 · ↓ Loss −$25 |

The full position table uses six columns: Instrument, Side, Qty, Entry, Result, Action. Each row has CLOSE. Component samples cover navigation, account cards, instrument selection, quantity controls, BUY/SELL/CLOSE, SL/TP, position rows, accepted/filled/error notifications, and confirmation/error dialogs. States: default, pressed, selected, disabled and error.

## Eight directions

### 01 / MIDNIGHT PERFORMANCE

Focused power, with a crisp response.

**Layout:** A slim LEFT navigation rail with icon-plus-text labels; a single strong account-metrics ribbon spanning the content top; central chart occupies about 70% of workspace width; fixed compact RIGHT order ticket; full-width positions table below. Tight, disciplined alignment and 10px corners. Midnight navy chart and surfaces, crisp cyan only for selection/focus. Larger account-value numerals than secondary balance labels.

**Surfaces:** Flat navy panels separated by precise spacing and one-pixel low-contrast borders; subtle raised action-button lips; original thin geometric line icons. No glass, metal, carbon texture or decorative gaming frame.

**Type:** Inter Tight (Heading); Inter (Body); JetBrains Mono (Numbers)

**Palette:** #0B1423, #122238, #24374C, #52D7F1, #43CA97, #F47988

**Motion:** ① BUY compresses 1px / 80ms. ② Cyan tab marker slides / 120ms. ③ Ticket reveals 6px / 180ms. ④ Check appears once / 180ms. ⑤ Price crossfades / 120ms.

[Open full board](01-midnight-performance.png)

### 02 / CARBON CLUB

Compact, confident, and quietly energetic.

**Layout:** NO left sidebar. Compact horizontal TOP navigation segments sit under brand/status. Three account metrics in a dense horizontal strip, chart left 72% and narrow docked order ticket right, an integrated two-row positions blotter directly below. Tighter desktop spacing than all other options but mobile remains comfortable. Small square 5px corners, robust semibold headings, dense tabular data.

**Surfaces:** Graphite matte panels, subtle fine carbon weave ONLY on the outer header strip, flat plain graphite chart. Restrained lime selected bar and micro status ticks, strong typography, short travel keyboard-like action keys, almost flush panel construction. Not sporty badges, not neon, not toy buttons.

**Type:** Manrope (Heading); IBM Plex Sans (Body); IBM Plex Mono (Numbers)

**Palette:** #151917, #232925, #354039, #BAE860, #48C48D, #F07F89

**Motion:** ① Action key depresses / 70ms. ② Segment fill wipes / 100ms. ③ Ticket drawer slides 4px / 140ms. ④ Inline check settles / 140ms. ⑤ Numbers crossfade / 100ms.

[Open full board](02-carbon-club.png)

### 03 / AFTER HOURS

Layered, composed, and subtly illuminated.

**Layout:** Narrow text navigation column LEFT; three compact separated account tiles above a wide central chart; the RIGHT order ticket is a subtly elevated independent floating-looking card aligned beside, never over, the plot. Positions below chart and ticket. 14px panel radii and slightly larger internal spacing, a clear two-level surface hierarchy.

**Surfaces:** Near-black opaque plot, rich muted violet active accents, soft layered charcoal panels, only a very faint illuminated edge around the selected tab or order ticket. No neon bloom or purple gradients on data. Buttons have soft 2px contact shadow and controlled inset pressed state; precise small line icons.

**Type:** Sora (Heading); Inter (Body); Roboto Mono (Numbers)

**Palette:** #101018, #1C1B2A, #353047, #AE98F3, #4BC89A, #EF8799

**Motion:** ① Button lip settles / 90ms. ② Violet underline glides / 160ms. ③ Ticket fades + lifts 4px / 200ms. ④ Thin check-ring resolves / 180ms. ⑤ Digits crossfade / 140ms.

[Open full board](03-after-hours.png)

### 04 / FROSTED FINTECH

Fresh clarity with selective glass.

**Layout:** Horizontal TOP navigation and three clearly separated account cards; chart LEFT about two-thirds width with generous toolbar; comfortable RIGHT trade ticket with a pale translucent upper header strip and opaque form body. Wide white positions table below. 12px radii, roomy but efficient spacing, clean visual grouping.

**Surfaces:** Cool gray structural background, crisp white opaque chart and cards, selective frosted translucency ONLY on chrome, dropdown backdrop or modal outside chart. Electric blue selection and focus. Sharp dark data labels, fine cool gray dividers, no glass across numerical fields or candles, no decorative blobs. Buttons satin with a restrained edge highlight.

**Type:** Geist (Heading); Inter (Body); IBM Plex Mono (Numbers)

**Palette:** #E9EEF5, #FFFFFF, #273B53, #245FE8, #157A54, #B83F54

**Motion:** ① Satin key compresses / 80ms. ② Blue pill slides / 140ms. ③ Frosted menu fades + moves 4px / 180ms. ④ Check + toast resolves / 160ms. ⑤ Value crossfades / 120ms.

[Open full board](04-frosted-fintech.png)

### 05 / PRECISION SPORT

Measured, aligned, and quick off the mark.

**Layout:** Segmented TOP navigation. Account metrics stacked in a narrow LEFT telemetry column, dominant chart in the CENTER, right order ticket with sharply aligned fields, positions as a full-width bottom data band. This left column contains account metrics rather than navigation. Angular 4px corners, tall bold numerals, horizontal separators and disciplined baselines.

**Surfaces:** Steel-slate dashboard, restrained orange on selected segment, focus marker and section rule. No racing car, speedometer, track illustration, stripes across data or sports badges. Trade labels remain familiar, no cockpit jargon. Flat chart, crisp dense data rows, small precise square line icons, action-button travel like a precise instrument switch.

**Type:** IBM Plex Sans Condensed (Heading); IBM Plex Sans (Body); Roboto Mono (Numbers)

**Palette:** #171D25, #242E3A, #516171, #FFAA51, #49C891, #F1858D

**Motion:** ① Key travels 1px / 60ms. ② Orange marker slides / 110ms. ③ Panel seats 4px / 150ms. ④ Check ticks once / 130ms. ⑤ Numbers settle / 100ms.

[Open full board](05-precision-sport.png)

### 06 / PREMIUM GAME HUD

Chart-first focus with polished game feel.

**Layout:** Chart-first game-native HUD: compact navigation TOP LEFT, low-profile account cards TOP RIGHT, one very large CENTER/LEFT chart, compact RIGHT order ticket aligned just outside the plotting rectangle, narrow fully visible positions drawer along the BOTTOM. Eliminate bulky sidebar. Frame information tightly around chart, no elements over candles. 8px clipped structural corner details only in outer chrome; order actions are larger than secondary controls.

**Surfaces:** Opaque ink-teal instrument surfaces, economical HUD framing, polished tactile green/red action buttons with a fine raised edge, small purposeful geometric icons. No sci-fi holograms, game world backdrop, score explosion, cartoon rewards, or crosshair over plot. Feels native to a quality game while retaining real-platform controls and credibility.

**Type:** DIN-style Inter Tight (Heading); Inter (Body); JetBrains Mono (Numbers)

**Palette:** #0E1D29, #19303D, #355361, #69CDE4, #49CA9B, #EF8190

**Motion:** ① BUY presses 2px / 75ms. ② Active rail slides / 130ms. ③ Bottom drawer travels 6px / 180ms. ④ Order check pulses once / 180ms. ⑤ Digits crossfade / 110ms.

[Open full board](06-premium-game-hud.png)

### 07 / LIGHT MODE LUXE

Bright, calm, and carefully finished.

**Layout:** Narrow LEFT text-navigation column, airy horizontal account strip with big dark numerals and thin separators instead of thick cards, generously spaced CENTER chart, clean RIGHT order column with 16px comfortable padding, positions below. Plenty of breathing room with a restrained editorial rhythm. 10px corners and a strong hierarchy created by spacing rather than effects.

**Surfaces:** Pearl warm-white shell, opaque white plot, deep charcoal typography, muted mint used sparingly for selection. Quiet physical depth from soft low-opacity contact shadows, fine neutral borders; no translucency, pastel gradients, bubbly shapes or colored large-area fills. Green/red reserved for meaningful market/action states. Original elegant line icons.

**Type:** DM Sans (Heading); Inter (Body); IBM Plex Mono (Numbers)

**Palette:** #F4F5F1, #FFFFFF, #202D2A, #5DAE98, #157451, #B83B50

**Motion:** ① Button compresses / 90ms. ② Mint marker glides / 160ms. ③ Panel fades + lifts 4px / 200ms. ④ Compact check settles / 160ms. ⑤ Value crossfades / 130ms.

[Open full board](07-light-mode-luxe.png)

### 08 / CHROME NIGHT

Technical polish, with one vivid signal.

**Layout:** Two-level horizontal header: brand/status above compact navigation and account metrics on one precision-aligned silver-edged strip. Large CENTER/LEFT chart in a recessed black well; RIGHT ticket uses slim metallic section headers and dark controls; full-width positions table below, with thin silver row rules. Rectilinear 4px corners, ultra-fine borders and a compact technical density.

**Surfaces:** Black and graphite surfaces, selective satin-silver metal ONLY on narrow title rails, button edges and divider details; no mirrored panels or chrome gradients behind prices. One orchid-magenta accent for selected/focus state, green/red only for market meaning. Fine engineered geometry and small outlined original icons, subtle 1px pressed movement. Not cyberpunk neon, not spaceship decoration.

**Type:** Space Grotesk (Heading); Inter (Body); IBM Plex Mono (Numbers)

**Palette:** #0B0D10, #1D2229, #C7CED5, #E88DDB, #4CC996, #F0838F

**Motion:** ① Metal-edged key seats / 70ms. ② Orchid indicator slides / 120ms. ③ Ticket panel moves 4px / 160ms. ④ Fine check appears / 150ms. ⑤ Numbers crossfade / 110ms.

[Open full board](08-chrome-night.png)


## Motion specification

The five numbered annotations map to ① action buttons, ② selected tabs, ③ ticket/panel edges, ④ confirmation feedback, ⑤ quote/account values.

- Buttons travel 1–2 logical pixels and lose their resting shadow for 60–90ms.
- Tab markers slide or fill over 100–160ms. Labels retain their positions.
- Panels use 4–6px translation plus opacity over 140–200ms. Chart space is reserved before opening, so chart size and axis positions remain fixed.
- Accepted/filled feedback is brief, local and non-looping: checkmark plus plain-language text, no confetti or screen shake. The gallery demonstrates acceptance followed by a fill; production timing must follow authoritative simulation events rather than a timer.
- Numbers use tabular figures in fixed-width containers and a 100–140ms crossfade. Display the exact settled value; do not use slow rolling counters or spring overshoot.
- Green/red carry market direction and P&L meaning. Theme accents mark focus/selection.
- The chart remains static during interface animations. Actual market ticks update candle geometry in place; no interface-driven pan, zoom, bounce, blur, scale or layout reflow.
- Honor reduced-motion preferences: remove translations and decorative confirmation animation, use immediate state changes, and keep all feedback understandable as text.
- Phone hit areas should be at least 48 × 48 logical pixels, with comfortable spacing and readable input text. The raster boards express design intent; production measurements and Roblox font availability must be validated after selection.
- The gallery's motion samples use system font fallbacks when named fonts are unavailable. The static boards and type specifications define the intended typography.

## Files

- `00-comparison-board.png` — eight numbered directions.
- Eight concept PNG boards.
- `index.html` — offline-capable gallery and local motion samples.
- `generation-prompts.json` — exact built-in image generation prompts and selected output paths.
- This README.

Original artwork and icons generated with built-in image_gen. No production UI integration or deployment.

