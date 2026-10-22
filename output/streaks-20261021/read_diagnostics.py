import json,collections
from pathlib import Path
R=Path(__file__).resolve().parent
for path in (R/'diagnostics').glob('*.json'):
    d=json.loads(path.read_text());totals=collections.defaultdict(lambda:collections.Counter())
    for r in d['Rows']:
        side=(r['Close']>r['Open'])-(r['Close']<r['Open'])
        for k,f in r['Flows'].items():
            t=totals[k];t['volume']+=f['Buy']+f['Sell'];t['aligned_net']+=side*(f['Buy']-f['Sell']);t['aligned_move']+=side*f['Move'];t['absolute_move']+=f['AbsoluteMove']
    print(path.stem)
    for k,v in sorted(totals.items(),key=lambda kv:-kv[1]['aligned_move']):print(k,dict(v))
