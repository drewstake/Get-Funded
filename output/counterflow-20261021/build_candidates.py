from pathlib import Path
import json, hashlib
R=Path(__file__).resolve().parent
meta=json.loads((R/'baseline-verification.json').read_text(encoding='utf8'))
(R/'snapshots/normalized-Latest.json').write_bytes(b''.join((R/'snapshots'/f'latest-{i}.part').read_bytes() for i in range(1,meta['Parts']+1)))
base=(R/'original/server/BotMomentum.luau').read_text(encoding='utf8')
base=base.replace('s.Threshold=range(s,c.EntryStrength);s.Confirmation=range(s,c.ConfirmationSeconds)', '''s.Threshold=range(s,c.EntryStrength);s.Confirmation=range(s,c.ConfirmationSeconds)
 if s.Confirmation>=s.Horizon then s.Confirmation=math.max(c.SampleSeconds,s.Horizon-c.SampleSeconds)end''')
base=base.replace('a.Momentum=s;a.OrderObjective=nil;', '''-- Independent exit budgets; no shared random draw or common clock.
 s.ProfitTicks=math.max(c.ProfitMinimumTicks,a.Stop*range(s,c.ProfitStopMultiple))
 s.ProfitAge=math.clamp(s.Horizon*range(s,c.ProfitAgeFraction),c.ProfitMinAge,c.ProfitMaxAge)
 a.Momentum=s;a.OrderObjective=nil;''')
base=base.replace('s.BuildUntil=e.Time+s.BuildSeconds;s.BreakoutLevel=signal.Level;', 's.BuildUntil=e.Time+s.BuildSeconds;s.BuildAnchor=signal.Last;s.BreakoutLevel=signal.Level;')
base=base.replace(" if pos then\n  local last=b.Last or b.Reference", ''' -- Harvest a favorable, executable move before a thesis reversal. This uses the
 -- existing paced reduce-only executor; no cash/price writes or synthetic fills.
 if pos and s.Phase~='Reducing'and e.Time-(s.OpenedAt or e.Time)>=s.ProfitAge then
  local bid,ask=e:PublicPrices(a.Key)
  local executable=pos.Direction==1 and bid or ask
  if executable and (executable-pos.Entry)*pos.Direction/b.Spec.Tick>=s.ProfitTicks then
   s.Phase='Reducing';s.ExitReason='Profit'
  end
 end
 if pos then
  local last=b.Last or b.Reference''')
for name,patient in [('profit',False),('profit-patient',True)]:
    d=R/'variants'/name;d.mkdir(exist_ok=True)
    s=base
    if patient:
        s=s.replace(' else\n  local due=math.ceil', ''' else
  -- A favorable move can make a remaining purchase too expensive (or sale too
  -- cheap). Wait for a better quote within the original finite build deadline.
  local bid,ask=e:PublicPrices(a.Key);local entry=side==1 and ask or bid
  if not entry or (entry/b.Spec.Tick-(s.BuildAnchor or entry/b.Spec.Tick))*side>
   math.max(c.BuildMinTolerance,a.Stop*c.BuildStopTolerance)then return end
  local due=math.ceil''')
    (d/'BotMomentum.luau').write_text(s,encoding='utf8')
    c=(R/'original/shared/MarketConfig.luau').read_text(encoding='utf8').replace('BotMomentum = {Version=2,', 'BotMomentum = {Version=4,ProfitMinimumTicks=6,ProfitStopMultiple={.4,1.1},ProfitAgeFraction={.2,.5},ProfitMinAge=12,ProfitMaxAge=90,BuildMinTolerance=4,BuildStopTolerance=.3,')
    (d/'MarketConfig.luau').write_text(c,encoding='utf8')
    cp=(R/'original/server/WorldCheckpoint.luau').read_text(encoding='utf8').replace('local Checkpoint={Version=28,Readable={','-- V29 persists independently staggered Momentum profit exits and execution anchors.\nlocal Checkpoint={Version=29,Readable={[29]=true,')
    (d/'WorldCheckpoint.luau').write_text(cp,encoding='utf8')
    (d/'manifest.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in d.glob('*.luau')},indent=2))
print('Two frozen candidates prepared')
