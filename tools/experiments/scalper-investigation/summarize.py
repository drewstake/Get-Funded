"""Summarize completed diagnostic simulations without modifying source or results."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
from collections import defaultdict, Counter
import hashlib
import json

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'output/scalper-investigation-20261019'
by_variant=defaultdict(list)
for path in OUT.glob('*-*-7200.json'):
    data=json.loads(path.read_text())
    by_variant[data['Variant']].append(data)
result={}
for variant,runs in sorted(by_variant.items()):
    rows=[r['Groups']['Total'] for r in runs]
    def total(field): return sum(r[field] for r in rows)
    counterparties=Counter()
    for r in rows: counterparties.update(r['Counterparties'])
    styles={}
    for style in ('Momentum','Reversion'):
        gs=[r['Groups'][style] for r in runs]
        styles[style]={'MeanPnl':sum(g['Pnl'] for g in gs)/len(gs),
                       'ProfitableBotsBySeed':[g['Positive'] for g in gs],
                       'ClosingFillWinRate':sum(g['Wins'] for g in gs)/sum(g['Closes'] for g in gs)}
    result[variant]={'Seeds':[r['Seed'] for r in runs], 'PnlBySeed':[round(r['Pnl'],2) for r in rows],
        'MeanPnl':total('Pnl')/len(rows),'ProfitableBotsBySeed':[r['Positive'] for r in rows],
        'ClosingFills':total('Closes'),'Wins':total('Wins'),'Losses':total('Losses'),'Even':total('Even'),
        'ClosingFillWinRate':total('Wins')/total('Closes'),
        'ProfitFactor':total('GrossWins')/total('GrossLosses'),
        'PassiveEntryFraction':total('PassiveEntries')/total('Entries'),
        'MakerEntryContractFraction':counterparties['Maker']/sum(counterparties.values()),
        'MeanMakerQuoteAgeAtAggressiveEntry':total('EntryMakerAge')/max(1,total('MakerEntryCount')),
        'MeanEntryFairEdgeTicks':total('EntryFairEdgeTicks')/total('Entries'),
        'MeanRealizedPerClosedContract':total('Realized')/total('ClosedContracts'),
        'Styles':styles,'MaxAbsoluteAuditError':max(abs(r['Audit'][key]) for r in runs for key in ('CashError','EquityError'))}
manifest=json.loads((OUT/'source-manifest.json').read_text())
verified=all(hashlib.sha256((source_file(ROOT, name)).read_text(encoding='utf-8-sig').encode()).hexdigest()==digest for name,digest in manifest.items())
output={'Scope':'Fresh current-source simulations, three new seeds, two simulated hours each. No refresh, funding changes or player trades. Variants change endogenous market paths; these are sensitivity experiments, not matched-trade causal decompositions.',
        'SourceUnchanged':verified,'Variants':result,
        'VariantDefinitions':{
            'baseline':'Current source, unchanged strategy and matching.',
            'random_direction':'Keep original entry gates and exits; select buy/sell with an independent seeded coin flip after gates pass.',
            'no_fair_filter':'Remove private-fair-distance predicates only from scalper reversal entries; retain observed-price turn conditions.',
            'public_fair':'Replace private fair value with recent price-window range midpoint for scalper reversal entries only. This tests one proxy, not all public-price strategies.',
            'fast_makers':'Maker minimum rest 18 -> 0.25 simulated seconds; reprice threshold 3 -> 1 tick. Pricing center and decision scheduling unchanged.',
            'fair_makers':'Maker center uses current internal fair value instead of 83% last trade + 17% fair value. Inventory skew and rest/reprice rules unchanged.'},
        'SourceEvidence':{
            'PrivateFair':'src/server/BotSignals.luau:37',
            'ScalperSignalsOverrideBiasNoise':'src/server/Participants.luau:331 and 335',
            'MakerPricingCenter':'src/server/Participants.luau:240',
            'MakerRestReprice':'src/shared/MarketConfig.luau:15',
            'RealizedPnl':'src/server/MarketEngine.luau:197',
            'ExecutionAtRestingPrice':'src/server/MarketEngine.luau:402',
            'PersistedBotHistoriesOmitted':'src/server/WorldCheckpoint.luau:81'},
        'Limitations':[
            'Not a replay of the pasted report: the exact historical checkpoint was not supplied.',
            'Aggregate counterparties at entry do not attribute every dollar of subsequent P&L to that counterparty.',
            'Win rate counts closing fills, including partial closes; it is not a full-position roundtrip statistic.',
            'Bot histories are stripped from durable checkpoints, so exact historical post-refresh win rates cannot be recovered from that checkpoint.',
            'Local source text matched the corresponding connected Studio script text using length and rolling checksums; this does not prove the historical pasted snapshot used those same sources.',
            'No game source, live balances, live orders, live configuration, or DataStore state was changed by this investigation.']}
test_path=OUT/'focused-tests.json'
if test_path.exists():
    tests=json.loads(test_path.read_text())
    output['FocusedTests']={'Total':tests['Total'],'Failures':tests['Failures']}
(OUT/'summary.json').write_text(json.dumps(output,indent=2))
print(json.dumps(output,indent=2))
