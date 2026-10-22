from pathlib import Path
root=Path(__file__).resolve().parent
for name in ['Current','Older','Aged']:
    parts=sorted((root/'snapshots').glob(f'normalized-{name}-*.part'),key=lambda p:int(p.stem.split('-')[-1]))
    (root/f'snapshots/normalized-{name}.json').write_bytes(b''.join(p.read_bytes()for p in parts))
def edit(name,fn,folder='server'):
    source=(root/f'original/{folder}/{name}.luau').read_text(encoding='utf8')
    (root/f'candidate/{name}.luau').write_text(fn(source),encoding='utf8')
edit('BotOrderFlow',lambda s:s.replace('local Momentum=require(script.Parent.BotMomentum)','local Momentum=require(script.Parent.BotMomentum)\nlocal Whale=require(script.Parent.BotWhale)').replace('function Pressure.Step(p,a)','function Pressure.Step(p,a)\n if Whale.Enabled(p,a)then Whale.Step(p,a);return end'))
edit('MarketConfig',lambda s:s.replace(' BotInformationVersion = 1,', ''' -- Patient institutional execution; existing capital, margin and recovery limits still apply.
 BotWhale = {Version=1,BuildSeconds={300,900},HoldSeconds={180,600},ReduceSeconds={120,360},
  TargetFraction={.45,.85},PositionRiskFraction=.025,Participation={.04,.10},QuietSeconds=30,
  SliceSeconds={5,12},SliceFraction={.15,.35},RefillSeconds={8,20},QuoteSeconds={25,60},
  RepriceTicks=4,MinRestSeconds=15,MaxSlippageTicks=3,PriceToleranceStops={.5,1.5},
  AggressiveProbability={.10,.35},StartDelay={5,60},CooldownSeconds={60,180},StopCooldownSeconds={90,240}},
 BotInformationVersion = 1,'''),'shared')
edit('WorldCheckpoint',lambda s:s.replace('local Checkpoint={Version=26','-- V27 persists patient Whale mandates, child reservations, fill baselines and private RNG.\nlocal Checkpoint={Version=27').replace('[26]=true}}','[26]=true,[27]=true}}').replace(' local momentum=currentConfig.BotMomentum', ''' local whale=currentConfig.BotWhale and currentConfig.BotWhale.Version or 0
 local savedWhale=config.BotWhale and config.BotWhale.Version or 0
 assert(savedWhale<=whale,'Cannot downgrade Whale policy')
 if savedWhale<whale then config.BotWhale=clone(currentConfig.BotWhale)end
 local momentum=currentConfig.BotMomentum'''))
for name in ['BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotRefreshTests']:
    edit(name,lambda s:s.replace('CP.Version==26','CP.Version==27'))
p=root/'candidate/BotOrderFlowTests.luau'
s=p.read_text(encoding='utf8').replace('local c=clone(C);c.BotOrderFlow.SliceFraction','-- Exercise the retained legacy executor explicitly; BotWhaleTests covers the current policy.\n local c=clone(C);c.BotWhale=nil;c.BotOrderFlow.SliceFraction')
p.write_text(s,encoding='utf8')
