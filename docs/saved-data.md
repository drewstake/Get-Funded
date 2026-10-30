# Saved-data compatibility

Saved-world compatibility is a separate release requirement from source/export
equality. Installed V28 saves must remain readable; never reuse a checkpoint version
for an incompatible format. The current writer
uses V33, reads V1–V28 and V30–V33, and deliberately rejects the uninstalled V29 research
format. Preserve the installed bot policies and their persisted state when merging
older source exports. `CheckpointCompatibilityTests` checks V28 recovery and a
complete WorldService restart using in-memory storage. Before replacing an existing
cloud draft, also restore a read-only copy of its Studio checkpoint in detached
modules, check its ledgers and continued replay, and verify the resulting Studio
source against the manifest. Never reset an unreadable world or use production
DataStore writes as a compatibility test.

V33 keeps the same logical saved world and stores the immutable retirement archive
as a separately checksummed compressed section. The core checksum binds its archive
digest and size. The combined raw and complete stored-record limits still apply.
The archive is frozen before its encoding is cached; public `Capture` remains an
independent mutable copy. Routine encoding serializes all mutable fields before any
yield, then compresses and hashes immutable bytes between frames. The saved step and
leaderboard projection belong to that same snapshot even while simulation continues.
Older builds reject V33 rather than silently discarding archived markets.

The V3 ownership manifest stores that immutable archive in one checksummed record,
confirmed before a checkpoint slot may reference it. Routine slots contain the full
mutable core and an archive reference; their original combined size limit still
includes all archived data. Readers fetch both records without cache and verify the
existing core/archive checksum binding. V1/V2 manifests and inline checkpoints remain
readable; older ownership writers reject V3. Failed staging or publication retains
the previous committed reference. Restart reuses the verified archive encoding so
JSON key ordering cannot create another archive. No history or account data is dropped.

## Market and population migrations

BX is the only active market. V32 retires BT and BG through the existing audited
settlement path: last-trade settlement, preserved history and equity, and archived
bot accounts. Population policy V3 appends 780 BX participants to the existing 390,
for 1,170 total. Existing accounts, orders and history remain intact; new traders
receive the same finite capital and risk limits as their V2 counterparts. Restart
is idempotent, and older population policies fail closed. Older writers must not
reopen the retired markets.

V31 adoption preserves existing positions, balances and historical bot losses.
Oversized positions can close but cannot add exposure above the new limits.
Migration does not forgive debt, recapitalize bots or manufacture fills.

## Legacy player profiles

`FundedAccounts.Migrate` validates and reuses V4 single-account profiles. Older
profiles migrate in the restored engine before admitting trades. Keep the original
profile in `LegacyProfile`, all ledger accounts and orphan player accounts, and
the balances, positions and orders recorded in `Migration.Accounts`.

Legacy positions settle through the engine's reduce-only administrative path;
old accounts are then archived and locked. New-run capital is the configured
starting balance plus the selected account's realized result after settlement.
Balances from multiple accounts and old wallet currency are not combined. That
carry is capital, not new trading profit: its result already exists in the old
ledger. Preserve titles, awards, lifetime losses and idempotence across restarts.
Missing historical accounts, unsupported versions or failed settlement must stop
migration instead of silently dropping records. `SingleAccountTests` covers this
contract alongside checkpoint compatibility tests.

## Storage and recovery

`src/server/WorldConfig.luau` defines the store, world key, save cadence, lease
and size limits. `WorldLease` fences writers and stages checkpoint slots before
publishing their reference. Corrupt or incompatible saves fail closed. Storage
failures pause trading rather than reseeding the exchange. Shutdown freezes
execution before flushing and releasing ownership. A crash can lose activity
since the last committed checkpoint; this is not a per-fill durable journal.

Keep internal `MarketReign` instance paths and storage keys stable. Studio and
Live scopes are separate; use detached in-memory fixtures for automated checks.
Never use production DataStore writes to test a migration. Reverting scripts
alone is not a safe rollback after a checkpoint-format upgrade.

The leaderboard projection is published only from committed exchange state and
is fenced by WorldId and SaveSequence. Do not reset the world store independently
of its leaderboard namespace.

Local recovery files remain under ignored `backups/`, including the pre-existing
`archived-place-files-20261026.zip` and its `archived-places.json` inventory.
Saved checkpoint captures and historical evidence remain in ignored `output/`.
They are local recovery material, not build inputs or fresh-checkout fixtures.
