from pathlib import Path
from analyze import summarize
import json
R=Path(__file__).resolve().parent
keys=['LongestRun','Pullbacks','OneSecondRV','MeanRange30','Transfers','NoQuoteFraction']
for folder in sorted(R.glob('results-*')):
 if not folder.is_dir():continue
 d=summarize(folder.name)
 if not d['Aggregate']:continue
 (R/(folder.name+'-summary.json')).write_text(json.dumps(d,indent=2))
 print(folder.name,len(d['Cases']))
 for arm,v in d['Aggregate'].items():print(arm, {k:round(v[k],4)for k in keys})
