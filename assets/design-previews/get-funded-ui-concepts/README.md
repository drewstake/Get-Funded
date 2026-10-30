# Get Funded! — Six UI concepts

Design previews only. Existing Roblox place files and game source were not edited.

Every board includes a desktop trading dashboard, portrait mobile dashboard, palette and type specimens, and a matching component library. The library covers BUY / SELL / CLOSE buttons; navigation; account cards; instrument selection; quantity controls; position rows; SL / TP fields; notifications; confirmation and error dialogs; and default, pressed, selected, disabled and error examples.

## Concepts

### 01 / TOY BOX

Tactile, confident, and playful. Rounded chunky panels with pronounced sculpted plastic edges and soft contact shadows, bold cobalt headers, lemon-yellow selected navigation, cream-white cards on pale sky. Buttons feel pressable like molded toy pieces with thick bottom lips; pressed state removes the bottom lip. Original toy block mark and little rounded shield/target icons. Dashboard text deep ink. Friendly bold rounded typography, but mature and tidy, no baby styling. BUY dark emerald and SELL berry with readable white labels. Chart pure off-white without decoration. Tiny dimensional blocks only around the title or empty outer board margins.

- Palette: #F2F7FC, #FFFFFF, #2455E7, #FFC83D, #11664F, #B72C49
- Typography direction: Fredoka heading; Nunito Sans body and tabular numbers
- Board: [01-toy-box.png](01-toy-box.png)

### 02 / NEON ARCADE

Fast, electric, and focused. Dark arcade cabinet styling: firm 10px corner panels, electric blue edges, violet raised keys, thin luminous perimeter accents, subtle pixel notches in navigation and an original joystick/candle emblem. Strong tall futuristic letterforms with generous spacing. Crisp opaque midnight chart with subdued grid, NO glow on candles or text inside chart. BUY mint and SELL rose with midnight labels. Active navigation shows a bright cyan left rail and tiny chevron. Pressed buttons appear sunken, selected has bright underline, disabled is dim with a lock icon, errors use an exclamation border. Decorative neon is restricted to panel perimeter, title, and challenge card; polished teen arcade energy not cyberpunk clutter.

- Palette: #0C1023, #171D38, #67D8FF, #AA8CFF, #62EDBC, #FF91AE
- Typography direction: Rajdhani bold heading; Inter body and tabular numbers
- Board: [02-neon-arcade.png](02-neon-arcade.png)

### 03 / CANDY POP

Bright, breezy, and friendly. Airy candy-pastel interface with superellipse cards, fully pill-shaped controls, soft lavender ambient shadows, blush backgrounds, cream white plotting area and dark plum text. Friendly original little cloud and star illustrations in title and challenge card only. Lavender and peach details, cheerful but polished for teens, not nursery aesthetic. Solid dark emerald BUY and dark raspberry SELL for accessibility against pastels. Selection uses a small stitched-looking inner ring and checkmark. Pressed pill indents, disabled pill dotted with minus, error clearly outlined with text. Rounded soft icon strokes; lively baseline on brand letters only; numerical text perfectly aligned. Distinct squishy gel/pastel softness, not Toy Box plastic bevels.

- Palette: #FFF5FA, #FFFFFF, #7250C8, #F4BEE0, #176953, #B43868
- Typography direction: Baloo 2 bold heading; Nunito Sans body and tabular numbers
- Board: [03-candy-pop.png](03-candy-pop.png)

### 04 / SPACE TRADER

Curious, precise, and ready for orbit. A friendly spacecraft bridge: deep navy flat instrument wells, chamfered corners, segmented cyan perimeter lines and small screw details outside data areas, holographic edge tabs, restrained lavender indicator lights. Original tiny rocket, planet-ring and mission-patch icons in chrome only. Modular dashboard panels feel engineered, not arcade neon. Numeric labels aligned like cockpit instrumentation, readable normal-language controls. BUY mint and SELL soft coral with dark navy text. Active tab is a lit cyan segment with a diamond marker. Pressed buttons recess into frame, selected has double corner brackets/check, disabled crosshatch, error amber/coral marker. Chart opaque flat navy, no stars or space dust inside plot. Space flourish confined to title and challenge card.

- Palette: #071828, #102C42, #77E5F3, #C1A1FF, #76E8B7, #FFAD99
- Typography direction: Exo 2 bold heading; IBM Plex Sans body and tabular numbers
- Board: [04-space-trader.png](04-space-trader.png)

### 05 / COZY TYCOON

Warm, steady, and full of possibility. Warm paper-and-desk business-building aesthetic: parchment backdrop, cream cards with softly rolled 14px corners and understated ink outlines, forest green navigation, apricot highlight tabs, carefully spaced warm brown labels. Original hand-drawn line-art shopfront/leaf/notebook icons; subtle paper texture ONLY outside chart. Use sturdy friendly slab-serif headlines and clean rounded sans body, NOT cartoon scribble. Button shapes like tidy rubber stamps with gentle offset shadow; pressed shadow disappears. Selection gets dark forest fill and check, disabled muted and dashed outline, error stamp-style exclamation with explanatory text. BUY forest and SELL burgundy. Chart pale ivory, neutral thin grid. Tiny cozy storefront drawing and potted sprout confined to title/challenge card; no coffee clutter across UI.

- Palette: #F4EDDF, #FFFDF7, #355D4B, #D69A55, #28684A, #AC414A
- Typography direction: Bree Serif heading; Nunito Sans body and tabular numbers
- Board: [05-cozy-tycoon.png](05-cozy-tycoon.png)

### 06 / COMPETITIVE CLUB

Bold, sharp, and team-ready. Modern youth sports club interface: bold condensed uppercase headlines, white flat stat cards, navy framing, punchy acid-lime selected state, strong asymmetric corner cuts and compact angular tabs. Graphic vertical stripes and original shield/ribbon insignia restricted to title and challenge panel. Clean editorial athletic typography, confident high contrast, no e-sports clutter or tiny compressed body. Panels rectangular 6px corners; consistent ample internal padding. BUY dark emerald and SELL crimson with white text; primary challenge action lime/navy. Navigation selection is lime strip plus black check, pressed keys compress downward with shadow removed, disabled outline and lock, error has bold exclamation strip. Plain white chart. Challenge card gets broad diagonal sporting stripe, no leaderboards or real-money competition invented.

- Palette: #EDF0F5, #FFFFFF, #182945, #DAFF4D, #176953, #B52F4F
- Typography direction: Barlow Condensed extra-bold heading; Barlow body and tabular numbers
- Board: [06-competitive-club.png](06-competitive-club.png)


## Shared content

- Persistent notice: **Simulated market · Virtual funds**
- Navigation: Trade, Positions, Challenges, Learn
- Virtual balance: $10,000
- Account value: $10,075
- Open result: ↑ Gain +$75
- Instrument: BLOX 100
- Last price: 1,250.00; change: ↑ +12.50 (+1.01%)
- Timeframes: 1m / 5m selected / 15m / 1h
- Quantity: 1
- SL · Stop loss: 1,230.00
- TP · Take profit: 1,280.00
- Position 1: BLOX 100 / BUY / Qty 2 / Entry 1,200.00 / ↑ Gain +$100
- Position 2: TECH 50 / BUY / Qty 1 / Entry 2,525.00 / ↓ Loss −$25
- Challenge: Use a stop loss / 2 of 3 complete

Desktop hierarchy: navigation → account cards → chart and order entry → open positions.
Mobile hierarchy: header and notice → account summary → instrument and chart → quantity and SL/TP → BUY/SELL → positions with CLOSE → navigation.

## Interaction and accessibility targets

These are visual concepts, not production UI or tested touch-target measurements.

- In implementation, phone buttons and input hit regions should be at least 48 × 48 logical pixels, with 8px separation where possible. Use at least 16px for primary controls and editable values. A compact visible CLOSE label still needs a full-height 48px hit region.
- Keep the simulated-market notice visible when the mobile content scrolls.
- Use a filled up candle and hollow down candle, plus a labeled legend. Never rely on red and green alone.
- Results pair direction arrows and the words Gain / Loss with signed values.
- Keep illustration, texture, lighting effects, and glow outside the chart plot.
- BUY and SELL have equal prominence and plain labels. CLOSE appears on every open position.
- Default: raised or resting button. Pressed: depressed/inset appearance. Selected: persistent marker, check, or underline. Disabled: inactive styling and no activation. Error: icon, outlined field, and actionable text.
- Quantity error copy: “Enter at least 1.” Keep submitted values so the player can correct the field.
- Closing a position opens “Close this position?” with instrument, side, quantity, current result, Keep open and CLOSE controls.
- Raster specimens describe font direction; actual Roblox font availability and exact metrics should be verified when a direction is chosen.

## Files

- Six PNG boards, named 01 through 06.
- `generation-prompts.json`: exact prompt set, style directions, palettes, and shared example content.
- `index.html`: local all-six gallery with links to full-resolution boards.

Generated using the built-in image_gen tool. Original generated artwork and icon treatments; no third-party icon packs or reference designs supplied.

