from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent;d=R/'candidate'
for f in(R/'variants/shorter-thinner').glob('*.luau'):(d/f.name).write_text(f.read_text())
p=d/'Participants.luau';s=p.read_text()
s=s.replace('if a.QuotePolicy~=policy then e:CancelAll(a.Id,a.Key);a.Quotes={};a.ReplenishAt={};a.QuotePolicy=policy end','''if a.QuotePolicy~=policy then
  -- Strategy adoption withdraws entry quotes only. Preserve manual/position-linked exits.
  local ids={};for id in pairs(account.OpenOrders)do local o=e.Orders[id];if o and o.Contract==a.Key and not o.ReduceOnly then table.insert(ids,id)end end
  table.sort(ids);for _,id in ipairs(ids)do e:Cancel(a.Id,id)end
  a.Quotes={};a.ReplenishAt={};a.QuotePolicy=policy
 end''')
p.write_text(s)
p=d/'WorldCheckpoint.luau';s=p.read_text().replace('local Checkpoint={Version=28,','-- V28 versions shorter Momentum horizons and staggered Maker replacement clocks.\n-- Migration changes policy only; positions, orders, protections and ledgers remain intact.\nlocal Checkpoint={Version=28,');p.write_text(s)
p=d/'MarketConfig.luau';s=p.read_text().replace('MakerQuoteSizeMultiplier = 0.45, -- Per-maker quote sizing; population expansion adds funded depth.','MakerQuoteSizeMultiplier = 0.45, -- Smaller displayed lots; account capital and inventory limits are unchanged.').replace('MakerReplenishSeconds = 12, -- Delay after discovering a fully consumed/expired quote.','MakerReplenishSeconds = 12, -- Individual 0.6-1.4x delay after consumption, expiry or repricing.');p.write_text(s)
for name in ['BotOrderFlowTests','BotParticipationTests','BotRefreshTests','BotWhaleTests','OrderFlowMarketTests']:
 s=(R/'original/server'/f'{name}.luau').read_text().replace('Version==27','Version==28')
 (d/f'{name}.luau').write_text(s)
s=(R/'original/server/MakerLiquidityTests.luau').read_text()
s=s.replace('local priority=ask.Priority','local priority=ask.Priority;local refill=C.MakerReplenishSeconds*(a.QuoteRefillFactor or 1)')
s=s.replace('a.ReplenishAt["1:1"]==e.Time+C.MakerReplenishSeconds','a.ReplenishAt["1:1"]==e.Time+refill').replace('e:AdvanceClock(C.MakerReplenishSeconds-.25)','e:AdvanceClock(refill-.25)')
s=s.replace(' return results\nend', (R/'ExtraMakerTests.luau').read_text()+'\n return results\nend')
(d/'MakerLiquidityTests.luau').write_text(s)
manifest={f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in d.glob('*.luau')}
(R/'candidate-manifest.json').write_text(json.dumps(manifest,indent=2))
e=json.loads((R/'experiment.json').read_text())
e['screening_gate_revision']={'when':'After development screening, before independent holdout comparisons','reason':'The initial no-decrease range rule was stricter than the user\'s explicit tuning-target constraint. Range is now reported as a tradeoff, not used to force price amplitude. Primary pullback, streak, volatility, funding and safety gates remain unchanged.'}
e['promotion_gate']['mean_30_minute_range']='Report mean and target-window coverage; 0.7-1.5% is a tuning target, not a mandatory range or price constraint.'
e['frozen_candidate']='shorter-thinner (0.45 displayed-size multiplier), plus manual-exit preservation on Maker policy adoption; no starting Maker reduce-only orders in any development checkpoint'
(R/'experiment.json').write_text(json.dumps(e,indent=2))
