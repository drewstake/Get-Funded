from pathlib import Path
from collections import Counter,defaultdict
import json,statistics,sys
from trace_summary import summarize
R=Path(__file__).resolve().parent
def run(case):
 d=json.loads((R/f'diagnostics/{case}-diagnose.json').read_text());out={}
 for market in ['BX','BT','BG']:
  rows=[x for x in d['Rows']if x['Market']==market];ev=[x for x in d['Events']if x['Market']==market]
  kinds=defaultdict(Counter);birth={};ages=defaultdict(list);openTimes=defaultdict(list)
  for x in ev:
   v=kinds[x['Kind']];v['MatchedSides']+=x['Quantity'];v['IncomingContracts'if x['Incoming']else'PassiveContracts']+=x['Quantity']
   closing=min(x['Quantity'],abs(x['Before']))if x['Before']*x['Direction']<0 else 0
   v['OpeningContracts']+=x['Quantity']-closing;v['ClosingContracts']+=closing
   if closing:v['Exit/'+x['Reason']]+=closing
   if x['Before']==0 and x['After']!=0:
    v['NewEpisodes']+=1;birth[x['Agent']]=x['Time'];openTimes[x['Kind']].append(x['Time'])
   if x['Before']!=0 and (x['After']==0 or x['Before']*x['After']<0):
    v['ClosedEpisodes']+=1
    if x['Agent']in birth:ages[x['Kind']].append(x['Time']-birth.pop(x['Agent']))
  quotes={}
  for kind in ['Maker','Reserve']:
   q=Counter()
   for row in rows:q.update(row['Quotes'].get(kind,{}))
   quotes[kind]={'Replacements':q['SlotReplacements'],'SameDecision':q['SameDecision'],'SameDecisionFraction':q['SameDecision']/max(1,q['SlotReplacements']),'MeanPlacementInterval':q['SlotLifetime']/max(1,q['SlotReplacements']),'MeanCancelAge':q['Age']/max(1,q['Cancels'])}
  out[market]={'Lifecycle':kinds,'MedianObservedEpisodeSeconds':{k:statistics.median(v)for k,v in ages.items()if v},'Quotes':quotes}
 (R/f'trace-{case}-lifecycle.json').write_text(json.dumps(out,indent=2))
 summarize(case)
 print(json.dumps({case:out['BX']},indent=2))
if __name__=='__main__':run(sys.argv[1])
