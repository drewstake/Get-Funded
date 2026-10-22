from pathlib import Path
R=Path(__file__).resolve().parent;d=R/'variants/value-horizon';d.mkdir(exist_ok=True)
s=(R/'original/server/Participants.luau').read_text().replace('elapsed/a.BeliefHalfLife','elapsed/(a.BeliefHalfLife*(self.Config.BotSignals and self.Config.BotSignals.ValueBeliefHorizonMultiple or 1))')
(d/'Participants.luau').write_text(s)
c=(R/'original/shared/MarketConfig.luau').read_text().replace('BotSignals = {Version=2,','BotSignals = {Version=3,ValueBeliefHorizonMultiple=4,')
(d/'MarketConfig.luau').write_text(c)
(d/'WorldCheckpoint.luau').write_text((R/'variants/combined/WorldCheckpoint.luau').read_text())
