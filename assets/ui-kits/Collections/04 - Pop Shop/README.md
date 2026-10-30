# Pop Shop — Simulator UI Kit

A visual kit inspired by the supplied shop reference: navy outlines, a red shop header, bright checkerboard cards, yellow prices, and colorful cartoon icons. The artwork is newly drawn vector art, not cropped from the screenshot.

## Open the kit

Open `index.html` in a browser. Everything needed for the preview, including the display font, is bundled locally. No build step or internet connection is needed.

- `00-kit-board.png`: full desktop design board.
- `01-shop-preview.png`: shop and sidebar preview.
- `02-mobile-preview.png`: complete phone layout.
- `03-mobile-shop.png`: phone shop close-up.
- `assets/svg/`: 27 editable vector assets.
- `assets/png/`: matching transparent PNG exports.
- `assets/icons-atlas.png`: 2048 × 2048 transparent sheet containing the 16 icons.
- `assets/icons-atlas.json`: pixel rectangles for each atlas icon.
- `icons.json`: icon manifest with SVG and PNG paths.
- `design-tokens.json`: colors, typography, strokes, radii, and spacing.
- `kit.css`, `kit.js`: reusable visual styles and preview interactions.
- `validation-results.json`: automated export and interaction checks.

## Included assets

**Icons:** shop basket, potion, prize wheel, pet, codes, settings, rebirth, gift, upgrade, boost, cash, speed, time, luck, gem, and coin. Every icon has a 240 × 240 SVG viewBox and a transparent 512 × 512 PNG.

**Components:** five checkerboard card backgrounds; primary, success, danger, and disabled button backgrounds; a white rounded panel; and a currency chip. Component PNGs are exported at twice their SVG dimensions. Background assets intentionally omit text so labels can remain editable in your UI.

**Specimens:** default, pressed, selected, and disabled buttons; currency counters; badges; success and error notices; a progress bar; an animation toggle; palette and typography.

## Preview behavior

The shop opens and closes, all five upgrade cards scroll, and price buttons open a purchase-state demonstration. Confirming changes the selected card to Owned. Cancel or Escape dismisses the dialog. Reset restores the initial state. Sidebar buttons demonstrate selection and identify their intended menu. The daily reward bar cycles from 0 to 5, and the animation switch disables transitions. Reduced-motion preferences are respected.

This is a visual prototype. Prices, balances, and the 15:00 timer are sample values; there is no payment, inventory, persistent progression, or live game integration.

## Reuse

Use the SVGs in a vector editor, or import the PNGs into your UI tool. Maintain aspect ratio and keep the dark outline intact. For checkerboard cards, preserve square checks instead of stretching one background to very different proportions.

For Roblox, upload the individual PNGs through Asset Manager and assign their image asset IDs to your ImageLabels or ImageButtons. Alternatively upload the atlas and use the rectangles from `icons-atlas.json` as ImageRectOffset and ImageRectSize. Build panels, labels, scrolling, hit targets, and purchase behavior as native GUI objects. No Roblox place or game source was changed by this kit.

The preview uses the bundled **Lilita One** typeface for display text, with Trebuchet MS / Arial for body copy. Lilita One is licensed under the SIL Open Font License; see `assets/fonts/OFL.txt`. Its browser appearance is not a guarantee of a matching Roblox built-in font.

The original icon and component artwork may be reused and modified in your projects. The bundled font retains its own license.

## Regenerate

From the project root, `python tools/experiments/build_pop_shop_kit.py` recreates the vector assets and manifests. `node tools/experiments/export_pop_shop_kit.cjs` exports PNGs and screenshots and verifies preview interactions. The export helper uses this workspace's bundled Sharp and Playwright dependencies and installed Chrome; update those paths to regenerate on another machine.
