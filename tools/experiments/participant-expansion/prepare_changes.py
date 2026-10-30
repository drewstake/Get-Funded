from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[3]
def edit(name, pairs):
 p=root/name;s=p.read_text(encoding='utf-8-sig')
 for old,new in pairs:
  assert old in s,(name,old)
  s=s.replace(old,new)
 p.write_text(s,encoding='utf-8')
edit('src/shared/MarketConfig.luau',[
 ('Reserve = {Count=6,','Reserve = {Count=18,'),
 ('ParticipantsPerInstrument = 76','ParticipantsPerInstrument = 228'),
 ('BotPopulation = {Version=1','BotPopulation = {Version=2'),
 ('Counts={Maker=20,Liquidity=24,Momentum=12,Value=20,Reversion=12,Protective=8,Scalper=24,Whale=4,Reserve=6}',
  'Counts={Maker=60,Liquidity=72,Momentum=36,Value=60,Reversion=36,Protective=24,Scalper=72,Whale=12,Reserve=18}'),
 ('ScalpersPerInstrument = 24','ScalpersPerInstrument = 72'),('MakersPerInstrument = 20','MakersPerInstrument = 60'),
 ('WhalesPerInstrument = 4','WhalesPerInstrument = 12'),
 ('-- Exact allocation. Capital is simulation funding, distinct from trading P&L.',
  '-- Three times the V1 population in every group. Per-bot funding, size and cadence stay the same.\n -- V2 appends new participants to saved funded worlds without refreshing existing bots.'),
 ('-- Additional funded institutions, anchored to independent simulated fair value.','-- Additional funded institutions, quoting around executed market prices.'),
 ('-- Twice as many makers share the former aggregate quote budget.','-- Per-maker quote sizing; population expansion adds funded depth.')])
edit('src/server/WorldCheckpoint.luau',[
 ('local Checkpoint={Version=22,','-- V23 expands funded populations without rewriting existing bots or recapitalizing losses.\nlocal Checkpoint={Version=23,'),
 ('[22]=true}}','[22]=true,[23]=true}}'),
 (' if upgradeBots then\n',' if upgradeBots then\n  if savedPolicy>=1 then\n   for _,kind in ipairs(currentConfig.BotPopulation.Order)do\n    assert(config.BotPopulation.Counts[kind]<=currentConfig.BotPopulation.Counts[kind]\n     and config.BotPopulation.Capital[kind]==currentConfig.BotPopulation.Capital[kind],"Population expansion must preserve existing allocation and funding")\n   end\n  end\n')])
for name in ['BotRefreshTests','OrderFlowMarketTests']:
 edit(next((root/'src').rglob(name+'.luau')).relative_to(root).as_posix(),[('CP.Version==22','CP.Version==23')])
edit('src/tests/BotPopulationTests.luau',[
 ('n==130 and sum==68000000 and styles.Momentum==12 and styles.Reversion==12','n==390 and sum==204000000 and styles.Momentum==36 and styles.Reversion==36'),
 ('total==204000000 and #p.Agents==390','total==612000000 and #p.Agents==1170'),
 ('n>380','n>1150'),('390 bots, $204M, 12/12','1170 bots, $612M, 36/36'),
 ('V14→V15','V14→V23')])
edit('src/tests/LegacyRetirementTests.luau',[
 ('#p.Agents==390','#p.Agents==1170'),('#bp.Agents==654','#bp.Agents==1434'),('plan.Receipt.Count==390','plan.Receipt.Count==1170')])
for name in ['prepare.py','tests.luau','run.luau','studio_bridge.py','InstallStudio.luau','build_release.py']:
 s=(root/'tools/experiments/order-driven-market'/name).read_text(encoding='utf-8-sig').replace('order-driven-market-20261019','participant-expansion-20261019')
 if name=='build_release.py':
  s=s.replace("targets['ServerScriptService.MarketReign.ProtectiveOrdersTests']='src/tests/ProtectiveOrdersTests.luau'",'')
  s=s.replace("prior.update(json.loads((BACK/'private-studio-extra.json').read_text()))",'')
 if name=='InstallStudio.luau':s=s.replace('Before order-driven market','Before participant expansion').replace('Order-driven price discovery and observed-move banners','Triple market participants')
 if name=='tests.luau':s=s.replace("'BotPopulationTests',","'BotPopulationTests','ParticipantExpansionTests','LegacyRetirementTests',")
 (root/'tools/experiments/participant-expansion'/name).write_text(s,encoding='utf-8')
print('Updated population configuration, migration version and validation harness')
