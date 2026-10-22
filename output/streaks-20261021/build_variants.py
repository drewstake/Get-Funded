from pathlib import Path
R=Path(__file__).resolve().parent
base=(R/'original/server/BotMomentum.luau').read_text()
source=base.replace("s.ReviewSeconds=range(s,c.ReviewSeconds);s.NextReview=e.Time", """s.ReviewSeconds=range(s,c.ReviewSeconds);s.NextReview=e.Time
 if c.ProfitAtStop then s.ProfitTicks=math.max(c.MinProfitTicks,a.Stop*range(s,c.ProfitAtStop));s.ProfitFraction=range(s,c.ProfitFraction)end
 s.NextEntrySlice=e.Time""")
source=source.replace("s.CooldownUntil=e.Time+range(s,stopped", "s.HarvestRemaining=nil;s.Harvested=nil\n s.CooldownUntil=e.Time+range(s,stopped")
source=source.replace("s.BuildUntil=e.Time+s.BuildSeconds;s.BreakoutLevel=signal.Level;s.InvalidSince=nil", "s.BuildUntil=e.Time+s.BuildSeconds;s.BreakoutLevel=signal.Level;s.InvalidSince=nil;s.Harvested=nil;s.HarvestRemaining=nil")
source=source.replace("if s.Phase=='Holding'or s.Phase=='Waiting'then return end", """-- Harvest part of an earned gain once per position, through real capped exits.
 -- Leave the core position and its existing protections intact; never rebuild the sold tranche.
 if pos and s.Phase~='Reducing'and s.ProfitTicks and not s.Harvested then
  local bid,ask=e:PublicPrices(a.Key);local exit=pos.Direction==1 and bid or ask
  if exit and (exit-pos.Entry)*pos.Direction>=s.ProfitTicks*b.Spec.Tick then
   s.Harvested=true;s.HarvestRemaining=math.max(1,math.floor(pos.Quantity*s.ProfitFraction))
   s.Phase='Holding';cancelEntries(e,a)
  end
 end
 local harvesting=pos and s.Phase~='Reducing'and(s.HarvestRemaining or 0)>0
 if (s.Phase=='Holding'and not harvesting)or s.Phase=='Waiting'then return end""")
source=source.replace("local reducing=s.Phase=='Reducing'", "local reducing=s.Phase=='Reducing'or harvesting")
source=source.replace("local target=reducing and 0 or math.clamp(s.Target,-capacity,capacity)", "local target=harvesting and inventory-pos.Direction*math.min(pos.Quantity,s.HarvestRemaining)or reducing and 0 or math.clamp(s.Target,-capacity,capacity)")
source=source.replace("else\n  local due=math.ceil", "else\n  if c.EntryRestSeconds and e.Time<(s.NextEntrySlice or 0)then return end\n  local due=math.ceil")
source=source.replace("if not reducing then s.Filled=(s.Filled or 0)+result.Filled end", """if not reducing then
   s.Filled=(s.Filled or 0)+result.Filled
   if c.EntryRestSeconds then s.NextEntrySlice=e.Time+range(s,c.EntryRestSeconds)end
  elseif harvesting then s.HarvestRemaining=math.max(0,s.HarvestRemaining-result.Filled)end""")
configs={
 'harvest':'ProfitAtStop={.20,.55},MinProfitTicks=5,ProfitFraction={.3,.7},',
 'bursts':'EntryRestSeconds={5,20},',
 'combined':'ProfitAtStop={.20,.55},MinProfitTicks=5,ProfitFraction={.3,.7},EntryRestSeconds={5,20},',
}
for name,extra in configs.items():
 d=R/'variants'/name;d.mkdir(exist_ok=True)
 c=(R/'original/shared/MarketConfig.luau').read_text().replace('BotMomentum = {Version=1,','BotMomentum = {Version=2,'+extra)
 if name!='harvest':c=c.replace('ReviewSeconds={5,15},SliceSeconds={3,8},SliceFraction={.25,.55}', 'ReviewSeconds={5,15},SliceSeconds={3,8},SliceFraction={.65,1.4}')
 (d/'MarketConfig.luau').write_text(c)
 (d/'BotMomentum.luau').write_text(source)
 cp=(R/'original/server/WorldCheckpoint.luau').read_text().replace('Version=27,Readable={','Version=28,Readable={[28]=true,')
 (d/'WorldCheckpoint.luau').write_text(cp)
