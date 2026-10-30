-- Server-only storage and ownership settings. Never copy a live checkpoint into ReplicatedStorage.
return {
 Enabled=true,
 StoreName="MarketReign_Continuous_v1",
 WorldKey="primary-exchange",
 LeaseSeconds=90,
 SafetySeconds=15,
 SaveSeconds=15,
 RetrySeconds=5,
 -- Limited launch: one shared trading server. Followers wait; they never create
 -- another exchange or move accounts into a different world to bypass this limit.
 LaunchMaxPlayers=60,
 ConnectionAttempts=3,
 ConnectionRetrySeconds=15,
 ConnectionFullRetrySeconds=30,
 ConnectionMaxRetrySeconds=60,
 ConnectionAttemptSeconds=45,
 ConnectionManualRetrySeconds=5,
 ConnectionRouteSpacingSeconds=0.5,
 -- Roblox budgets writes per KEY over the preceding 60 seconds, rounded to KB.
 -- Keep the ownership/commit manifest small. Each bounded checkpoint slot accepts
 -- at most one full write per 65 seconds; six routine slots sustain 15-second saves.
 -- Two additional slots are reserved for shutdown/failover bursts.
 -- https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits
 CheckpointSlots=8,
 ShutdownSlots=2,
 CheckpointSlotSeconds=65,
 CheckpointWriteBytesPerMinute=4000000,
 -- Checkpoint size limits, checked before every commit (a refused save pauses trading; the last save stays).
 -- Raw JSON: the writer refuses exactly what the reader refuses (WorldCheckpoint.MaxDecodedBytes, 32,000,000),
 -- so every checkpoint that can be saved can be restored, and every save that restores today can be saved again.
 -- MaxEncodedBytes bounds the WHOLE checkpoint-slot value (revision + compressed checkpoint) plus
 -- RecordHeadroomBytes, below Roblox's 4,194,304-character value limit (the JSON-encoded length). It is above the previous 3,500,000 check
 -- on the checkpoint alone, so no save the previous build accepted can become unsavable after this update.
 MaxEncodedBytes=3600000,
 RecordHeadroomBytes=4096,
 -- Growth headroom. New profiles and free restarts pause once the last saved checkpoint used
 -- CapacityFraction of either limit; a first Start can use the band up to
 -- NewAccountCapacityFraction. Existing accounts keep trading throughout; nothing is deleted.
 CapacityFraction=0.8,
 NewAccountCapacityFraction=0.9,
 -- Per-connection acknowledgement queue. Replies wait for the player's next market packet; a client that
 -- never subscribes keeps at most MaxQueuedReplies, each for at most ReplyMaxAgeSeconds. Dropped replies
 -- force a full state resync on the next packet.
 MaxQueuedReplies=64,
 ReplyMaxAgeSeconds=30,
 -- Unpublished Studio files cannot use Roblox persistence. Keep an explicitly labelled local sandbox.
 AllowUnsavedStudio=true,
 StudioReplaySeed=0, -- A positive value replays a NEW Studio world only; live servers always seed privately.
}
