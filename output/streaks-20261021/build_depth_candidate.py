from pathlib import Path
R=Path(__file__).resolve().parent
d=R/'variants/shorter-thinner';d.mkdir(exist_ok=True)
c=(R/'variants/refill/MarketConfig.luau').read_text()
c=c.replace('BotMomentum = {Version=1,','BotMomentum = {Version=2,').replace('Horizons={{60,180},{180,480},{480,1200}}','Horizons={{20,90},{90,240},{240,600}}').replace('HoldMultiple={1.5,2.5},MinHoldSeconds=180,MaxHoldSeconds=1800','HoldMultiple={1,2},MinHoldSeconds=60,MaxHoldSeconds=900').replace('PositionRiskFraction=.025,BuildSeconds={90,240}','PositionRiskFraction=.025,BuildSeconds={30,120}')
c=c.replace('MakerQuoteSizeMultiplier = 0.9','MakerQuoteSizeMultiplier = 0.45')
(d/'MarketConfig.luau').write_text(c)
for f in ['Participants.luau','WorldCheckpoint.luau']:(d/f).write_text((R/'variants/refill'/f).read_text())
