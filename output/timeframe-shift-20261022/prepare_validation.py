from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
cases={}
for case in ['CurrentBX','Older','Aged']:
 p=R.parent/'diversity-20261022/snapshots'/('normalized-'+case+'.json');d=json.loads(p.read_text());cache={};quotes={}
 for key,b in d['Engine']['Books'].items():
  tick=d['Config']['Contracts'][key]['Tick'];last=(b['Last']or b['Reference'])*tick
  quotes[key]={'Last':last,'Open':b['Candles']['1D'][-1]['Open']}
  for tf,bars in b['Candles'].items():cache[key+':'+tf]=bars
 cases[case]={'Time':d['Engine']['Time'],'Step':d['Engine']['Step'],'Quotes':quotes,'CandlesBySeries':cache,'SourceSHA256':hashlib.sha256(p.read_bytes()).hexdigest()}
(R/'history-fixtures.json').write_text(json.dumps(cases),encoding='utf8')
(R/'bridge.py').write_text((R.parent/'diversity-20261022/bridge.py').read_text().replace('8836','8837'),encoding='utf8')
print('Prepared read-only historical fixtures for',list(cases))
