"""Executable edge cases. Legacy metrics are retained without changing their definitions."""
from pathlib import Path
import json,math
from metrics import meaningful
from analyze import measures
R=Path(__file__).resolve().parent
def bars(xs):
 return [dict(Open=xs[max(0,i-1)],Close=x,High=max(xs[max(0,i-1)],x),Low=min(xs[max(0,i-1)],x),Time=60*i) for i,x in enumerate(xs)]
def classify(bars,tick):
 """Classify meaningful counter events prospectively, without calling all reversals pullbacks.
 Recovery reaches pre-retracement extreme; full reversal crosses the preceding leg's anchor.
 First boundary reached decides. No boundary in remaining data is unresolved/censored.
 This is descriptive only; legacy strict-pullback selection gate stays fixed.
 """
 cs=[b['Close'] for b in bars]; direction=0; anchor=extreme=cs[0]; events=[]
 for i,price in enumerate(cs[1:],1):
  floor=max(6*tick,abs(extreme)*.00025)
  if not direction:
   if abs(price-anchor)>=floor:direction=1 if price>anchor else -1;extreme=price
  elif (price-extreme)*direction>=0:extreme=price
  elif (extreme-price)*direction>=max(floor,abs(extreme-anchor)*.2)-1e-8:
   event={'Minute':i,'Anchor':anchor,'Extreme':extreme,'Direction':direction,'Status':'Unresolved','ResolvedMinute':None}
   for j in range(i,len(cs)):
    if (cs[j]-anchor)*direction<=0:
     event.update(Status='FullReversal',ResolvedMinute=j);break
    if (cs[j]-extreme)*direction>=0:
     event.update(Status='RecoveredPullback',ResolvedMinute=j);break
   events.append(event);anchor=extreme;extreme=price;direction=-direction
 return events
def run():
 checks=[]
 def check(name,test):assert test,name;checks.append(name)
 flat=meaningful(bars([100]*60),.25)
 check('Flat tape is not movement or counterflow',flat['MeaningfulCounters']==0 and measures(bars([100]*60),.25)['OneMinuteRV']==0)
 x=[100,103,106,109,108.75,109,111,110.75,112]
 check('Tiny opposite closes do not reset a meaningful leg',meaningful(bars(x),.25)['MeaningfulCounters']==0)
 x=[100,103,106,109,106,109,112,113]
 check('Substantial pullback recognized',meaningful(bars(x),.25)['MeaningfulCounters']>=1)
 check('Recovered pullback is not a full reversal',classify(bars(x),.25)[0]['Status']=='RecoveredPullback')
 x=[100,103,106,109,106,103,99]
 check('Full reversal crosses original anchor',classify(bars(x),.25)[0]['Status']=='FullReversal')
 x=[100,103,106,109,106,107]
 check('Right edge stays unresolved',classify(bars(x),.25)[0]['Status']=='Unresolved')
 x=[100,101,102,103,104,105,103.75,105,106]
 check('20% threshold does not bypass six-tick floor',meaningful(bars(x),.25)['MeaningfulCounters']==0)
 x=[10000,10003,10006,10009,10007,10009]
 check('Price-relative floor blocks smaller retracements',meaningful(bars(x),.25)['MeaningfulCounters']==0)
 x=[100,103,106,109,106,109,112,113]
 a=meaningful(bars(x),.25);b=meaningful(bars([v*10 for v in x]),2.5)
 check('Price and tick scaling invariant',all(a[k]==b[k]for k in ['MeaningfulCounters','MeaningfulMaxLeg','MeaningfulLong8','MeaningfulPullbacks']))
 x=[100,103,106,109,106,107,109,111]
 check('Legacy strict completed pullback needs recovery',meaningful(bars(x),.25)['MeaningfulPullbacks']==1)
 check('Legacy strict pullback excludes full reversal',meaningful(bars([100,103,106,109,106,103,99]),.25)['MeaningfulPullbacks']==0)
 (R/'measurement-audit.json').write_text(json.dumps({'Passed':checks,'Notes':['OHLC uses dollars; book internals and trace movement use ticks.','Legacy leg durations start at confirmation and include quiet minutes, with boundaries truncated.','Legacy strict pullbacks use three prior minutes and recovery within eight samples. This differs from full-leg recovery classification.','One-minute RV uses 59 close-to-close returns for 60 candles; first open-to-close omitted consistently.','Ten-minute directional metric actually uses ten closes (nine intervals); retained label and definition for comparison.','Original benchmark Depth container is unused; quote depth is obtained separately from trace samples.','Recovery baseline/terminal deltas omit adaptation; endurance disables recovery for adaptation too.','One-second and 15-second midpoint RV are sampled only with two-sided quotes; missing-side rate reported separately.']},indent=2))
 print('Passed',len(checks),'measurement audit cases')
if __name__=='__main__':run()
