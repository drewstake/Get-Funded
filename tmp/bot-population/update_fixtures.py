from pathlib import Path
root=Path('src')
# These account/execution suites intentionally restore exchanges without a bot scheduler.
for name in ['ProtectiveOrdersTests','SharedDepthTests','ClosedTradePnlTests','TradePreferencesTests','ResetLiquidationTests']:
    path=root/(name+'.luau');s=path.read_text()
    s=s.replace('local C=require(game.ReplicatedStorage.MarketReign.MarketConfig)', 'local C=table.clone(require(game.ReplicatedStorage.MarketReign.MarketConfig))\nC.BotPopulation=nil -- This fixture intentionally has no autonomous population.')
    s=s.replace('assert(saved.Version==14)', 'assert(saved.Version==CP.Version and CP.Version>=14)')
    path.write_text(s)
path=root/'DepthRealismTests.luau';s=path.read_text().replace('local c=clone(C);c.ParticipantsPerInstrument=0', 'local c=clone(C);c.BotPopulation=nil;c.ParticipantsPerInstrument=0');path.write_text(s)
path=root/'ScalperTests.luau';s=path.read_text()
s=s.replace('count==18 and momentum==9 and reversion==9','count==24 and momentum==12 and reversion==12').replace('ContractOrder,18','ContractOrder,24').replace('54 scalpers','72 scalpers')
s=s.replace('a.Size=2;a.Limit=2;', 'e.Books.BX.Recent={last-30,last};a.Size=2;a.Limit=2;')
s=s.replace('a.Bias=100;p.Config.Scalper.AggressiveChance=0','e.Books.BX.Recent={last-30,last};a.Bias=100;p.Config.Scalper.AggressiveChance=0')
s=s.replace('test("Old checkpoints gain scalpers once without rewriting market history",function()', 'test("Old checkpoints gain scalpers once without rewriting market history",function()\n  local Default=clone(Default);Default.BotPopulation=nil;Default.ScalpersPerInstrument=18 -- Isolate the historical V11 upgrade.')
path.write_text(s)
path=root/'MakerLiquidityTests.luau';s=path.read_text().replace('after.Config.MakerQuoteSizeMultiplier==3','after.Config.MakerQuoteSizeMultiplier==C.MakerQuoteSizeMultiplier').replace('assert(migrated==30)','assert(migrated==60)');path.write_text(s)
path=root/'WorldTests.luau';s=path.read_text()
s=s.replace('Default.MakersPerInstrument==10 and Default.ParticipantsPerInstrument==36 and Default.WhalesPerInstrument==3','Default.MakersPerInstrument==20 and Default.ParticipantsPerInstrument==76 and Default.WhalesPerInstrument==4')
s=s.replace('makers==10 and traders==36 and whales==3','makers==20 and traders==76 and whales==4').replace('10 makers, 36 ordinary traders, 3 whales and 18 scalpers','20 makers, 76 ordinary traders, 4 whales and 24 scalpers')
for title in ['Older worlds gain makers once, preserving the tape, accounts and retired markets','Maker migration counts renamed agents and avoids occupied account ids']:
    s=s.replace(f'test("{title}",function()',f'test("{title}",function()\n  local Default=clone(Default);Default.BotPopulation=nil;Default.MakersPerInstrument=10 -- Isolate historical maker upgrade.')
s=s.replace('test("Restored book retains FIFO, partial fills, cancellations, account funds and protection",function()', 'test("Restored book retains FIFO, partial fills, cancellations, account funds and protection",function()\n  local Default=clone(Default);Default.BotPopulation=nil -- Intentionally empty scheduler.')
path.write_text(s)
