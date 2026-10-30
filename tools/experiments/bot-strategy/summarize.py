"""Compare the frozen baseline with final-source results and verify provenance."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from collections import Counter
from pathlib import Path
import hashlib
import json
from statistics import mean

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'output/bot-strategy-20261018'
def read(name):return json.loads((OUT/name).read_text())
def compact(d):
    gates=Counter()
    for values in d['Gates'].values():gates.update(values)
    return {
        'Seed':d['Seed'],'Seconds':d['Seconds'],'Variant':d['Variant'],
        'Pnl':{kind:round(g['DeltaPnl'],2) for kind,g in d['Groups'].items()},
        'NoOneContractCapital':{kind:g['NoContractCapital'] for kind,g in d['Groups'].items()},
        'ScalperEntryAttempts':gates['EntrySubmit'],'ScalperClosingFills':d['Groups']['Scalper']['Closes'],
        'AllScalpersFlatPercent':100*d['Samples']['AllScalpersFlat']/d['Samples']['Count'],
        'Gates':dict(gates),'Audit':d['Audit'],
        'Markets':{key:{'TwoSidedPercent':100*m['TwoSided']/m['Samples'],'AverageSpreadTicks':m['Spread']/max(1,m['TwoSided'])} for key,m in d['Samples']['Markets'].items()},
    }
manifest=read('candidate-manifest.json')
for name,digest in manifest.items():
    assert hashlib.sha256((source_file(ROOT, name)).read_text(encoding='utf-8-sig').encode()).hexdigest()==digest,name+' changed after staging'
tests=read('tests.json');assert tests['Failures']==0
seeds=(73521,5501,4407)
baseline=[compact(read(f'baseline-{s}-7200.json')) for s in seeds]
candidate=[compact(read(f'candidate-{s}-7200.json')) for s in seeds]
comparison={kind:{'BeforeMeanPnl':mean(d['Pnl'][kind] for d in baseline),'AfterMeanPnl':mean(d['Pnl'][kind] for d in candidate),
                  'BeforeBySeed':[d['Pnl'][kind] for d in baseline],'AfterBySeed':[d['Pnl'][kind] for d in candidate]}
            for kind in candidate[0]['Pnl']}
activity={field:{'Before':mean(d[field] for d in baseline),'After':mean(d[field] for d in candidate)}
          for field in ('ScalperEntryAttempts','ScalperClosingFills','AllScalpersFlatPercent')}
holdout={variant:compact(read(f'{variant}-90217-21600.json')) for variant in ('baseline','candidate')}
report={'Scope':'Fresh isolated populations; simulated dollars; no player orders or funding changes. Three fixed two-hour seeds plus a previously unused six-hour seed.',
        'TwoHourComparison':comparison,'ScalperActivity':activity,'Baseline':baseline,'Candidate':candidate,'SixHourHoldout':holdout,
        'Tests':{'Total':tests['Total'],'Failures':tests['Failures']},'CandidateSourceHashesVerified':True,
        'BaselineProvenance':read('baseline-provenance.json'),
        'Implementation':{'FairValue':'Protective and Reversion observations anchor to current internal fair value plus independent noise.',
            'Reversion':'New exposure requires a current fair-value deviation and a confirmed turn. Unconfirmed reductions are capped and reduce-only.',
            'Scalpers':'12-30 simulated-second lookback; one-tick/volatility-scaled movement; directional confirmation and separate target-versus-cost check.',
            'Persistence':'Checkpoint V18 and separate BotSignals policy version 1; no population, capital, position or order reset; bounded time history persists.'},
        'Limitations':['Market paths and RNG consumption diverge after strategy changes, so these are equal-seed sensitivity comparisons, not identical-trade replays.',
            'Gains redistribute between counterparties. Other bot types can lose; simulated profits are not a guarantee.',
            'Source and offline tests only; no connected Studio/native Play validation or publication was performed.',
            'Existing depleted accounts keep their balances; this strategy update does not provide new capital.']}
(OUT/'comparison.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'Targets':{k:v for k,v in comparison.items() if k in ('Protective','Reversion','Scalper')},'ScalperActivity':activity,
                  'Holdout':{v:{k:d['Pnl'][k] for k in ('Protective','Reversion','Scalper')} for v,d in holdout.items()},
                  'Tests':report['Tests']},indent=2))
