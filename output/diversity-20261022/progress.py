from pathlib import Path
import json
from metrics import meaningful
from analyze import measures
R=Path(__file__).resolve().parent
for name in json.loads((R/'experiment.json').read_text())['Candidates']:
 folder=R/('development-'+name);files=list(folder.glob('*-Candidate.json'))
 print(name, len(files),'/6')
 p=folder/'CurrentBX-Candidate.json'
 if p.exists():
  d=json.loads(p.read_text());bars=d['Markets']['BX']['Bars'];m=meaningful(bars,.25);v=measures(bars,.25)
  print(' CurrentBX/BX:',{k:m[k] for k in ['MeaningfulLong8','MeaningfulMaxLeg','MeaningfulCounters','MeaningfulPullbacks']},'RV',round(v['OneMinuteRV'],4),'Ranges',v['Range30'])
 print('')
