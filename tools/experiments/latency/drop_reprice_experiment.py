"""Retain measured CPU/transport/save improvements; remove the adverse strategy experiment."""
from pathlib import Path
root=Path(__file__).resolve().parents[3]
source=root/'src'
path=root/'src/server/MarketEngine.luau';s=path.read_text();start=s.index('-- Server-only passive bot replacement.');end=s.index('function Engine:AmendOrder(owner,request)',start);s=s[:start]+s[end:];path.write_text(s)
path=root/'src/server/Participants.luau';s=path.read_text()
start=s.index('   if a.Quotes[slot]and not held then\n');end=s.index('   local tick=math.max(1,math.round(center',start)
s=s[:start]+'   if a.Quotes[slot]and not held then a.Quotes[slot]=nil;a.ReplenishAt[slot]=e.Time+replenish end\n'+s[end:]
baseline=(root/'output/latency-20261027/baseline/original/Participants.luau').read_text()
start=s.index('   local unsafe=blocked');end=s.index('   if eligible and not held',start)
bs=baseline.index('   if held and (blocked');be=baseline.index('   if eligible and not held',bs)
s=s[:start]+baseline[bs:be]+s[end:];path.write_text(s)
path=root/'src/shared/MarketConfig.luau';s=path.read_text();s='\n'.join(line for line in s.split('\n') if 'MakerSafeReprice =' not in line);path.write_text(s)
path=root/'src/server/WorldCheckpoint.luau';s=path.read_text().replace(' and pending safe reprices','').replace(',"MakerSafeReprice"','');path.write_text(s)
path=root/'src/tests/MakerLiquidityTests.luau';s=path.read_text().replace('Legacy repricing withdraws','Repricing withdraws').replace('  e.Config.MakerSafeReprice=false\n','');path.write_text(s)
path=root/'src/tests/LatencyTests.luau';s=path.read_text();start=s.index(" test('Passive replacement preserves");end=s.index(" test('Sectioned saves retain",start);s=s[:start]+s[end:];path.write_text(s)
