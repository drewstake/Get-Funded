# First-join experience: loading screen and welcome guide — October 19, 2026

Joining now opens on a custom loading screen styled after the game icon. It shows real loading progress and ends with a "You're in!" reveal. First-time players then meet **Bucky**, the green bull from the "Bull or Bear?" thumbnail. He walks them through four tiny missions on the real trading controls. Returning players get a short welcome back instead.

## What the player sees

### Loading screen (`ReplicatedFirst.LoadingScreen`)
- **Scene.** The scene echoes the game icon: a blue-to-violet sky with light beams, a cloud bank, a faint bar skyline, rising green and red candles and a gold arrow swoosh. Coins, `BX` / `BT` / `BG` ticker chips and bills float in the sky, with twinkling sparkles. The chunky **GET FUNDED!** logo drops in, then breathes.
- **Real progress.** The bar and percentage add up five weighted stages. Each status line names the current stage, and a detail line shows what it's waiting on:
  1. *Unpacking the trading floor…* Roblox content download, using `ContentProvider.RequestQueueSize` (e.g. "Downloading game content · 23 left").
  2. *Setting up your trading desk…* The live terminal has mounted. The saved Edit preview is ignored because it has `EditPreview=true`.
  3. *Ringing the opening bell…* The account and portfolio have arrived. The exchange's own status label is shown in friendly words (e.g. "Restoring today's market, almost there").
  4. *Pulling live prices…* The first market snapshot has arrived (`MarketStep > 0`).
  5. *Polishing the gold coins…* The terminal's actual images and UI sounds are preloaded with a per-asset count ("Loading artwork and sounds · 12 / 31").
- **Tips.** Ten real gameplay tips rotate every 5.5 s; tap a tip to see the next one. All numbers come from the game's config: BX $12.50/tick, BG $10/tick, 1 contract per $1,000 with a minimum of 5, and Opening Bell at 25 trades for +$2,500.
- **Pop the stars.** Gold ★ stars drift up; tapping one pops it with a burst and "+1". A star counter appears, and milestone cheers show at 5, 12, 25 and 50. A hint appears after 3 s if the player hasn't tried yet.
- **Bucky** peeks over the progress card. On short landscape screens he stands beside it instead. He looks worried if loading is slow.
- **Slow loading.** After 6 s on one stage, the detail line adds a timer. After 20 s, a panel explains the delay. Once the terminal exists, the panel also offers **Enter anyway**, which hands over to the terminal's own connecting state.
- **Reveal.** When every stage is done, the reveal starts straight away with no padding:
  - the bar fills;
  - a gold **YOU'RE IN!** badge pops with confetti and a success sound;
  - the layers dolly toward the camera at different speeds (parallax) while the scene fades, uncovering the terminal.
  
  It takes about a second, and a tap skips it.
- **Comfort toggles.** *Sound* and *Motion* pills sit in the corner. Their choices carry into the game.

### Welcome guide (`ReplicatedStorage.MarketReign.WelcomeGuide`)
- **Intro (first join).** A modal in the game's popup style. Bucky waves with a speech bubble ("I'm Bucky! You've got $10,000 in play money…"). A preview lists the four missions, with **Let's go!** and **Skip guide** buttons.
- **Missions.** Each one completes only from the real action:

  | # | Mission | Completes when | Highlighted control |
  |---|---------|----------------|---------------------|
  | 1 | Pick a market | a market is chosen (`selectContract`) | ticket / chart market picker, then the BX/BT/BG options |
  | 2 | Set your safety net | stop loss / take profit settings are saved | Stop loss & Take profit cards (desktop) or Risk controls (phone), then the popup's red X |
  | 3 | Make your call | a **server-confirmed fill** arrives | BUY and SELL |
  | 4 | Lock it in | a **server-confirmed close** arrives, including a stop loss or take profit firing | Close position (ticket, phone position bar, Activity row, or the confirm dialog) |

- **Mission card.** Bucky sits in a speech bubble with a typewriter line (tap to finish it). The checklist chip reads "YOUR FIRST ADVENTURE · 1/4" with four pips. A live *Open profit* readout shows during mission 4. The card also has **Skip guide** (with a confirm step) and a minimize button.
  - The card places itself inside the chart, top or bottom, whichever keeps the highlighted control clear.
  - When a popup is open it shrinks to a one-line hint pill ("Looks good? Tap the red X to save it."). On phones it steps aside entirely.
  - Off the Trade screen it becomes "Adventure paused · tap to continue".
- **Highlight.** A pulsing gold ring follows the real control through every terminal rebuild, clipped to its scroll area. A bouncing ▲ pointer sits above, below or beside the ring, whichever spot doesn't cover the card, another button or a label.
- **Celebrations.** Each step gets a pip check pop, a confetti burst and the game's own success sound. Bucky hops and cheers with a line that fits how the trade closed: "Take profit hit!", "Your stop loss stepped in…", "Ka-ching!", and so on.
- **You're ready!** A modal shows the first trade's result and the **next objective** from the server (e.g. *Close 25 trades · 1 / 25 · Earns the Opening Bell title + $2,500 on every fresh start*). It ends with a confetti shower and **Keep trading** / **See my goals** buttons.
- **Welcome back.** Returning players get a small Bucky bubble with their name, next goal, a progress bar and any open positions. It dismisses itself after 7 s, or on tap.
- **Replay.** Help (`?`) → *How to play* → **Replay welcome guide**. On phones the path is More → How to play.

## How it works

- **Saved state.** It reuses the profile's existing `Tutorial` field (`Pending` / `Done` / `Skipped`) and the existing `Flag` request (`TutorialDone` / `TutorialSkipped`). There are no server or checkpoint changes. The flag is resent every 3 s until the server confirms it. Skipping a replay keeps an earlier `Done`.
- **Separate overlay.** The guide lives on its own ScreenGui (`GetFundedGuide`, DisplayOrder 12, the same insets as the terminal), so the terminal's full canvas rebuilds never reset its animations. It finds controls by path on every frame. A new mount removes any stale guide.
- **What TerminalUI reports.** TerminalUI now reports only two real actions: `guide:Signal("Market")` from `selectContract`, and `guide:Signal("Protection")` after protection settings save successfully. Fills and closes are read from `session.Fills` / `session.History`, compared with a snapshot taken when the missions start.
- **Old coach removed.** The previous 5-step "First trade" coach has been removed from TerminalUI and replaced by this guide. That includes `coachSteps`, `coachProgress`, the `CoachStep` attribute and the `s.Coach*` state. For diagnostics, the root now carries `GuidePhase` and `GuideStep`.
- **Comfort settings.**
  - `GetFundedSoundOn` and `GetFundedReducedMotion` are player attributes shared by the loading screen, the terminal and the guide for the session.
  - Reduced motion defaults to the player's Roblox **Reduce Motion** setting (`GuiService.ReducedMotionEnabled`).
  - Settings has a new **Reduced motion** switch.
  - In calm mode, `UIFeedback` drops scaling, bouncing and shaking but keeps colour and sheen. Bucky stays still apart from blinking and talking. Confetti becomes a few fading sparkles, and the ring stops pulsing.
- **Artwork.** Bucky, the stars, coins, candles and confetti are drawn with native GuiObjects plus the ★ and ▲ glyphs, so nothing new needs uploading. The trophy on the "You're ready!" card reuses the game's existing trophy asset.

## Files

- New: `src/LoadingScreen.client.luau` (→ `ReplicatedFirst.LoadingScreen`), `src/WelcomeGuide.luau`, `src/Mascot.luau`, `src/Confetti.luau` (→ `ReplicatedStorage.MarketReign`).
- Changed: `src/TerminalUI.luau` (guide hooks, Reduced motion setting, Help replay button, old coach removed), `src/UIFeedback.luau` (`FX:SetCalm`).
- Backups of the Studio sources before this change: `backups/first-join-20261019/` (TerminalUI, UIFeedback).

## Verification (Studio Play, in-memory stores)

Play tests used a temporary MarketServer patch that swapped both DataStores (world checkpoint, leaderboard) for in-memory stores. No DataStore was read or written. The patch was removed afterwards, and every script listed above matches `src/` in Studio.

Everything below used real mouse input and real server requests.

- **First join.**
  - The loading screen ran on the real stages and revealed the terminal.
  - Intro → **Let's go!** → BX picker → BT chosen (mission 1) → Stop loss popup opened and saved with the red X (mission 2) → **BUY 1 BT** filled (mission 3).
  - The market then fell and the server's **stop loss closed the trade at −$500**. The guide completed mission 4 from that close and showed **You're ready!** with *Close 25 trades · 1 / 25*.
  - Server log: `ProtectionPreferences`, `Place BT`, `Flag TutorialDone`; profile `Tutorial=Done`.
- **Skip from the intro.** Bucky's toast showed and the profile became `Tutorial=Skipped`. **Replay** from Help showed the "Welcome guide" refresher, and the mid-guide *Skip guide* confirm offered *Keep going*.
- **Phone layout (390×735).** The terminal re-rendered its mobile UI. The missions were done again on the phone controls: chart picker → BG, Risk controls → red X, **SELL 1 BG**, then position bar Close → Close dialog → confirm. **You're ready!** used stacked full-width buttons.
- **Returning player.** After remounting the terminal, the welcome-back bubble showed "Next goal: Close 25 trades · 1 / 25".
- **Reduced motion.** The Settings switch updated the player attribute, `UIFeedback` (`ReducedMotion=true`), a still Bucky and a static ring.
- **Loading layouts** were checked at 1914×793, 390×780, 844×390 and 700×393 with a simulated 58 px top bar.
- **Regression suites.** SingleAccountTests 22/22 and SecurityTests 2/2 passed. MarketTests passed 12/14. The two failures are *Daily quote baseline…* (`Participants:61`) and *Seeded participants…* (`BotPopulation:43`), both in server simulation code this change does not touch. Studio's `MarketTests` module does not match `src/MarketTests.luau`, which predates this work.

**Not checked:** a physical phone, a tablet, a gamepad and a real slow connection. The slow-loading panel was only seen in an Edit-mode preview. Nothing has been published. Studio holds the installed sources, but the place still needs saving or publishing.

Two dev audit scripts still look for the old coach (`CoachStep` / `SkipTour`) and are now out of date: `tools/AuditColorfulUI.luau` and `tools/AuditMobileArcadeClean.client.luau`. `tools/` is unchanged.
