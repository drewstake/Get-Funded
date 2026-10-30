# Runtime architecture

The server owns matching, accounts and persistence. Client UI sends requests and
renders authoritative snapshots; chart navigation and drawings do not change
market prices. Prices and candle volume come from matched orders.

| Filesystem group | Responsibility | Roblox location |
| --- | --- | --- |
| `src/server/` | Exchange, participants, accounts, protection, storage and routing | `ServerScriptService.MarketReign` |
| `src/shared/` | Config, client state, charts, terminal and UI components | `ReplicatedStorage.MarketReign` |
| `src/client/` | Loading screen and terminal startup | `ReplicatedFirst`, `StarterPlayer.StarterPlayerScripts` |
| `src/tests/` | Regression suites and detached test helpers | Explicit original paths in the build manifest |

`build/place-manifest.json` is authoritative. Filesystem groups do not create
Roblox folders. `TradingClient` stays in StarterPlayerScripts so deleting its
ScreenGui cannot interrupt cleanup. Test/helper modules retain their manifest
paths; only the detached harness flattens filenames for offline requires.

`MarketServer` validates requests and coordinates `WorldService`, `FundedAccounts`
and the engine. `MarketEngine`, `Participants`, and the bot strategy modules own
simulation and matching. `TradeProtection`, `ProtectiveOrders`, `PlayerExecution`
and `MarketSafety` enforce position and execution rules. `RequestJournal` keeps
request replay consistent with saved account state.

`MarketClient` and `MarketPacket` handle client state and transport. `TerminalUI`
mounts the chart, order ticket and views. `ChartView`, `ChartViewport`, `ChartTools`
and `ChartPaintPool` handle drawing, navigation, interaction and object reuse.
`LoadingScreen`, `WelcomeGuide`, `Mascot` and `UIFeedback` provide onboarding and
motion/sound preferences. Use `MarketConfig`, `ProgressionConfig` and `WorldConfig`
for current policy values rather than old feature reports.

Order responses carry authoritative account state on the same ordered remote stream
as market updates. They are coalesced once per heartbeat when a normal market packet
is not due. Depth still broadcasts every 0.1 seconds; account responses do not refresh
its timestamp. Unchanged portfolio metadata is omitted only while both profile and
account revisions match. The client requests a full subscription if its delta baseline
is missing. Quote strategy delays, 72 steps/second and the 8 ms simulation budget remain
unchanged. See `tools/experiments/latency/` and `output/latency-20261027/` for detached measurements,
saved-world replay, manipulation tests and the rejected safe-repricing experiment.

## Market safety and saved-position replay

Funded markets apply rolling price bands over 60 and 900 simulated seconds. The
anchors persist across checkpoints, so individual fills and restarts cannot reset
the bands. Player exposure is limited by funded reserve capacity, with a maximum
of 200 contracts per owner, market and direction. Pending entries and related
accounts share this allowance. Reserve inventory is sized against available
capital and stress loss, and new reserve risk stops at a 20% drawdown.

A stalled market close can rest as a position-linked closing limit at the last
permitted trade price. Opposing exits can then match through the normal order
book. Server-validated Close actions receive the same execution priority as
protective exits; they still require real counterpart orders and valid prices.
The UI identifies managed closing orders, which can be canceled but not dragged
to a new price. Small real depth can execute a close instead of rounding to zero.


## Limited launch and connection recovery

Launch capacity remains one shared trading server with 60 player slots. Follower
servers route to the current lease owner; they never create a second exchange or
move saved accounts to bypass capacity. The waiting screen explains full servers,
unavailable owners, transfer failures, and rejected new-account admission. Waiting
does not reserve a slot. Existing saved accounts can reconnect at the account or
checkpoint-size limit without another starting grant.

`WorldConfig` controls retries: three automatic attempts, 30/60-second full-server
backoff, 15/30/60 seconds for other failures, a 45-second completion watchdog,
and a five-second manual retry cooldown. A transfer API call that is still yielding
is never duplicated; its waiting screen offers leaving/rejoining if it remains stuck.
Follower dispatches are spaced apart. Late failure events must match the server-set
attempt, place, job and current owner. Disconnects discard their routing state.

`ConnectionTests` uses detached exchanges, fake clocks and fake transfers to cover
capacity boundaries, checkpoint recovery, retry limits, stale events, owner changes,
disconnects, pending transfers and disabled trading. Studio Edit checks can run this
suite safely without starting the game's services. `ConnectionPanel` uses an
`Activated` retry button and scrolls on short landscape screens.

Real `TeleportAsync`/`TeleportInitFailed` behavior and joining a truly full Roblox
server still require a separate published test experience and Roblox clients;
Studio does not support real teleports. Local checks do not publish or access
production player data. See [Roblox's teleport testing guidance](https://create.roblox.com/docs/projects/teleport).
