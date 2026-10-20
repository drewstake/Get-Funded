# Get Funded! advertisement

20-second vertical advertisement, 1080 × 1920, 30 fps. Main composition: `GetFunded-Ad`.

Open the live preview at http://localhost:3000/GetFunded-Ad while Studio is running. Press Space to play. Each scene also has its own connected composition under Scenes; headlines can be edited in the Inspector.

| Time | Scene |
| --- | --- |
| 0–4.1 s | Buy or sell? Your call. |
| 4.1–8.2 s | Start with $10,000 in virtual funds. |
| 8.2–12.3 s | A staged BX trade dips, rallies, then closes for +$1,500. |
| 12.3–16.4 s | Market Rookie → Market Pro → Trading Legend. |
| 16.4–20 s | Get Funded! / Play on Roblox. |

## Local commands

```powershell
npm ci
npm run dev -- --no-open
npm run lint
```

To export an MP4 when ready:

```powershell
npm run export:mp4
```

The delivered version is an editable Studio preview. QA frames and a cover are under `out/`. No video export or social publishing was performed.

## Assets and accuracy

- Artwork: existing game thumbnail, game icon and rank atlas copied into `public/assets/`.
- Font: the game's Fredoka font, bundled locally for reproducible preview and rendering.
- Starting balance and rank names: `../src/ProgressionConfig.luau` as inspected on October 14, 2026.
- BX tick size and multiplier: `../src/MarketConfig.luau`. One contract at 5,825 closes at 5,855 for +$1,500 virtual profit; the displayed balance becomes $11,500. The counter uses the same tick-rounded price as the chart.
- The chart is a staged animated demonstration, not a recording of live gameplay. The ad identifies virtual currency and labels the example.
- Soundtrack: “worry (Slowed)” by LONOWN and riserayss, from the user-selected [YouTube release](https://www.youtube.com/watch?v=f3DoKx_R1_s). Source excerpt: 00:35.455–00:55.455 at its original speed and pitch. The heavier section arrives around 8.2 seconds; scene changes follow the beat at 4.1-second intervals.
- The excerpt is saved as `public/audio/worry-slowed-20s.wav`: 48 kHz stereo PCM, 20 seconds, volume reduced 8.6 dB, 20 ms opening fade and 450 ms ending fade. Source credit: ℗ ARCADIA, release October 10, 2025. This project does not include a commercial music license.
- The original synthesized soundtrack and its generator remain available as an alternative (`npm run audio` regenerates that alternative only).
- Game source, player balances and Roblox publishing were not changed.

Remotion dependencies are pinned in `package-lock.json`. License: https://www.remotion.dev/license
