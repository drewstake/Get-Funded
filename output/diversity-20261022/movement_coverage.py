from pathlib import Path
import json,math
R=Path(__file__).resolve().parent
def coverage(bars,tick):
 closes=[x['Close']for x in bars];squared=[];quiet=longest=run=0
 for previous,current in zip(closes,closes[1:]):
  squared.append((math.log(current/previous)*100)**2)
  low=abs(current-previous)<max(6*tick,abs(previous)*.00025)
  quiet+=low;run=run+1 if low else 0;longest=max(longest,run)
 total=sum(squared);squared.sort(reverse=True)
 return {'Intervals':len(closes)-1,'LowChangeShare':quiet/max(1,len(closes)-1),'LongestLowChangeRun':longest,'LargestMinuteVarianceShare':squared[0]/total if total else 0,'LargestFiveVarianceShare':sum(squared[:5])/total if total else 0}
assert coverage([{'Close':100}]*60,.25)['LowChangeShare']==1
assert coverage([{'Close':100}]*30+[{'Close':110}]*30,.25)['LargestMinuteVarianceShare']==1
rows=[]
for folder in sorted(R.glob('development-*')):
 if not folder.is_dir()or folder.name=='development-baseline':continue
 for p in folder.glob('*-Candidate.json'):
  d=json.loads(p.read_text())
  for key,m in d['Markets'].items():rows.append({'Variant':folder.name.removeprefix('development-'),'Case':d['Case'],'Market':key,**coverage(m['Bars'],.1 if key=='BG'else .25)})
for p in (R/'development-baseline').glob('*.json'):
 d=json.loads(p.read_text())
 for key,m in d['Markets'].items():rows.append({'Variant':'Baseline','Case':d['Case'],'Market':key,**coverage(m['Bars'],.1 if key=='BG'else .25)})
(R/'movement-coverage.json').write_text(json.dumps({'Role':'Descriptive support for existing candle review, not a replacement or relaxation of original gates. Low-change compares adjacent minute closes against the original six-tick/0.025% price floor; it does not classify a pullback.','Rows':rows},indent=2))
for x in rows:
 if x['Case']=='CurrentBX'and x['Market']=='BX'and x['Variant']in ['Baseline','portfolio','portfolio-dense','inner-patient-stretch','diverse-patient-stretch','last-reserve-diverse']:print(x)
