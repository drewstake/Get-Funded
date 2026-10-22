from pathlib import Path
import json,sys,subprocess
from metrics import summarize
from measurement_audit import classify
R=Path(__file__).resolve().parent
stage=sys.argv[1] if len(sys.argv)>1 else 'development'
names=sys.argv[2:]or json.loads((R/'experiment.json').read_text())['Candidates']
out={}
for name in names:
 folder=stage+'-'+name;d=summarize(folder)
 (R/(folder+'-metrics.json')).write_text(json.dumps(d,indent=2))
 events=[]
 for p in (R/folder).glob('*.json'):
  raw=json.loads(p.read_text())
  for key,m in raw['Markets'].items():events.append({'Case':raw['Case'],'Arm':raw['Arm'],'Market':key,'Events':classify(m['Bars'],.1 if key=='BG'else .25)})
 (R/(folder+'-event-classification.json')).write_text(json.dumps(events,indent=2))
 out[name]={'Pass':d['Pass'],'Failed':[k for k,v in d['Gates'].items()if not v],'Aggregate':d['Aggregate'],'CurrentBX':[x for x in d['Markets']if x['Case']=='CurrentBX'and x['Market']=='BX']}
 print(name,json.dumps({'Failed':out[name]['Failed'],'Aggregate':d['Aggregate']},indent=2))
 subprocess.run([sys.executable,'-X','utf8',str(R/'plot_comparison.py'),folder],check=True)
(R/(stage+'-batch-summary.json')).write_text(json.dumps(out,indent=2))
