from pathlib import Path
r=Path(__file__).resolve().parent
for name in ['Current','Older','Aged']:
 parts=sorted((r/'snapshots').glob(f'normalized-{name}-*.part'),key=lambda p:int(p.stem.split('-')[-1]))
 (r/f'snapshots/normalized-{name}.json').write_bytes(b''.join(p.read_bytes()for p in parts))
def edit(name,fn,folder='server'):
 s=(r/f'original/{folder}/{name}.luau').read_text(encoding='utf8');(r/f'candidate/{name}.luau').write_text(fn(s),encoding='utf8')
edit('Participants',lambda s:s.replace('local Momentum=require(script.Parent.BotMomentum)','local Momentum=require(script.Parent.BotMomentum)\nlocal Maker=require(script.Parent.BotMaker)').replace('function Participants:_maker(a)','function Participants:_maker(a)\n if Maker.Enabled(self,a)then Maker.Step(self,a);return end'))
edit('MarketConfig',lambda s:s.replace(' MakerQuotePolicyVersion = 7,', ''' -- Inventory-aware Maker behavior; existing margin, population and recovery policy stay authoritative.
 BotMaker = {Version=1,ResponseSeconds={8,30},MaxAnchorLagTicks=3,
  SoftUtilization={.60,.75},UnwindUtilization={.80,.90},ResumeUtilization={.20,.35},
  MaxInventorySeconds={480,1200},AgeMinimumUtilization=.15,
  SkewTicks={5,10},NonlinearSkew=1.5,MinRestSeconds={18,30},
  RefillSeconds={5,12},RepriceSeconds={2,5},HitDecaySeconds={30,90},
  HitSpreadTicks=.5,HitSizePenalty=.25,MaxHitPressure=3,QuoteLifetimeMultiple=6},
 MakerQuotePolicyVersion = 7,'''),'shared')
edit('WorldCheckpoint',lambda s:s.replace('local Checkpoint={Version=27','-- V28 persists Maker inventory age, unwind hysteresis, quote clocks and private RNG.\nlocal Checkpoint={Version=28').replace('[27]=true}}','[27]=true,[28]=true}}').replace(' local whale=currentConfig.BotWhale', ''' local maker=currentConfig.BotMaker and currentConfig.BotMaker.Version or 0
 local savedMaker=config.BotMaker and config.BotMaker.Version or 0
 assert(savedMaker<=maker,'Cannot downgrade Maker policy')
 if savedMaker<maker then config.BotMaker=clone(currentConfig.BotMaker)end
 local whale=currentConfig.BotWhale'''))
for name in ['BotOrderFlowTests','BotParticipationTests','OrderFlowMarketTests','BotRefreshTests','BotWhaleTests']:
 edit(name,lambda s:s.replace('CP.Version==27','CP.Version==28'))
# Historical exact lane/size/refill assertions remain useful for the retained legacy executor.
edit('MakerLiquidityTests',lambda s:s.replace('local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)','local C=table.clone(require(game.ReplicatedStorage.MarketReign.MarketConfig))\n-- Legacy quoting fixtures; current inventory policy is covered by BotMakerTests.\nC.BotMaker=nil'))
