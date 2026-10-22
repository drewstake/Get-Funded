from pathlib import Path
import json
from shape_metrics import shape
from analyze import measures
R=Path(__file__).resolve().parent
d=json.loads((R/'snapshots/normalized-Latest.json').read_text(encoding='utf8'))
out={}
for key,b in d['Engine']['Books'].items():
    if key not in ['BX','BT','BG']:continue
    bars=[x for x in b['Candles']['1m'] if x['Time']+60<=d['Engine']['Time']][-180:]
    x=measures(bars,.1 if key=='BG'else.25)
    out[key]={'Minutes':len(bars),**shape(bars,.1 if key=='BG'else.25),**{k:x[k] for k in ['LongestRun','Pullbacks','Efficiency10']}}
(R/'current-chart-diagnosis.json').write_text(json.dumps(out,indent=2),encoding='utf8')
print(json.dumps(out,indent=2))
