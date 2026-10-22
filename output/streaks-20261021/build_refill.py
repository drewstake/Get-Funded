from pathlib import Path
R=Path(__file__).resolve().parent
for name,base in [('refill',None),('combined-refill','combined')]:
 d=R/'variants'/name;d.mkdir(exist_ok=True)
 if base:
  for f in (R/'variants'/base).glob('*.luau'):(d/f.name).write_text(f.read_text())
 source=(R/'original/server/Participants.luau').read_text()
 source=source.replace('local replenish=self.Config.MakerReplenishSeconds or math.max(4,minRest/3)', '''local replenish=self.Config.MakerReplenishSeconds or math.max(4,minRest/3)
 if self.Config.MakerRepricePause then
  -- Identity-derived latency is independent of scheduling and consumes no shared RNG.
  if not a.QuoteRefillFactor then
   local n=math.floor(math.abs(e.Seed))%2147483646+1
   for i=1,#a.Id do n=(n*31+string.byte(a.Id,i))%2147483646 end
   for _=1,6 do n=(n+1)*48271%2147483647 end
   a.QuoteRefillFactor=.6+.8*n/2147483647
  end
  replenish*=a.QuoteRefillFactor
 end''')
 source=source.replace('e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil', '''e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil
    if self.Config.MakerRepricePause then a.ReplenishAt[slot]=e.Time+replenish end''')
 (d/'Participants.luau').write_text(source)
 c=(d/'MarketConfig.luau').read_text()if base else(R/'original/shared/MarketConfig.luau').read_text()
 c=c.replace('MakerQuotePolicyVersion = 7','MakerQuotePolicyVersion = 8').replace('MakerReplenishSeconds = 3,','MakerRepricePause = true,\n MakerReplenishSeconds = 12,')
 (d/'MarketConfig.luau').write_text(c)
 cp=(R/'original/server/WorldCheckpoint.luau').read_text().replace('Version=27,Readable={','Version=28,Readable={[28]=true,')
 cp=cp.replace('local config=clone(snapshot.Config)', '''local config=clone(snapshot.Config)
 assert((config.MakerQuotePolicyVersion or 0)<=(currentConfig.MakerQuotePolicyVersion or 0),'Cannot downgrade Maker quote policy')''')
 cp=cp.replace('"MakerReplenishSeconds","MakerDecisionMultiplier"','"MakerReplenishSeconds","MakerDecisionMultiplier","MakerRepricePause"')
 (d/'WorldCheckpoint.luau').write_text(cp)
