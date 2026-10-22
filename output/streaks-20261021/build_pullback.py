from pathlib import Path
R=Path(__file__).resolve().parent;d=R/'variants/pullback-entry';d.mkdir(exist_ok=True)
s=(R/'original/server/BotMomentum.luau').read_text()
s=s.replace("elseif math.abs(move)>=required and move*confirmation>=0 then side=move>0 and 1 or -1 end", """elseif math.abs(move)>=required then
  side=move>0 and 1 or -1
  if s.Cohort>1 then
   -- Slow trend followers buy dips/sell rallies inside an established trend.
   -- Breakouts and the fast cohort retain continuation entries. No imposed turn.
   local retracement=side==1 and high-last or last-low
   local minimum=math.max(c.PullbackMinTicks,spread,volatility*c.PullbackVolatility)
   if retracement<minimum or retracement>math.abs(move)*c.PullbackMaxFraction then side=0 end
  elseif move*confirmation<0 then side=0 end
 end""")
(d/'BotMomentum.luau').write_text(s)
c=(R/'original/shared/MarketConfig.luau').read_text().replace('BotMomentum = {Version=1,','BotMomentum = {Version=2,PullbackMinTicks=2,PullbackVolatility=.15,PullbackMaxFraction=.75,')
(d/'MarketConfig.luau').write_text(c)
(d/'WorldCheckpoint.luau').write_text((R/'variants/combined/WorldCheckpoint.luau').read_text())
