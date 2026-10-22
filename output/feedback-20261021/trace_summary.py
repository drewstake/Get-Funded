from pathlib import Path
import json,collections,statistics,sys
R=Path(__file__).resolve().parent
def summarize(case):
 path=R/'diagnostics'/f'{case}-diagnose.json'
 if not path.exists():path=R/'diagnostics'/f'{case}.json'
 d=json.loads(path.read_text());markets={}
 for market in ['BX','BT','BG']:
  rows=[r for r in d['Rows']if r['Market']==market and 'Open'in r];flows={};quotes={};inventory={}
  for r in rows:
   sign=(r['Close']>r['Open'])-(r['Close']<r['Open'])
   for label,f in r['Flows'].items():
    x=flows.setdefault(label,dict(AlignedTicks=0,Buy=0,Sell=0,OpenContracts=0,CloseContracts=0,Trades=0,Passive=collections.Counter()))
    x['AlignedTicks']+=f['Move']*sign
    for k in ['Buy','Sell','OpenContracts','CloseContracts','Trades']:x[k]+=f[k]
    x['Passive'].update(f['Passive'])
   for kind,q in r['Quotes'].items():
    x=quotes.setdefault(kind,collections.Counter());x.update(q)
    x['AlignedSlotTicks']+=q.get('SlotPriceChange',0)*sign
   for kind,qty in r['Inventory'].items():inventory.setdefault(kind,[]).append(qty)
  cycles=[x for x in d['Cycles']if x['Market']==market];cs={}
  for kind in ['Momentum','Whale']:
   xs=[x for x in cycles if x['Kind']==kind];prev=[x for x in xs if 'Previous'in x]
   cs[kind]={'Entries':len(xs),'RepeatObserved':len(prev),'SameDirectionRepeats':sum(x['Direction']==x['Previous']['Direction']for x in prev),'MedianRepeatSeconds':statistics.median([x['Time']-x['Previous']['Time']for x in prev])if prev else None}
  markets[market]={'Flows':dict(sorted(flows.items(),key=lambda kv:-kv[1]['AlignedTicks'])),'QuoteEvents':quotes,'Cycles':cs,'InventoryRange':{k:[min(v),max(v)]for k,v in inventory.items()},'MeanValueGapTicks':statistics.mean(r['ValueGap']/max(1,r['ValueSamples'])for r in rows)}
 result={'Case':case,'Markets':markets,'Audit':d['Audit']};(R/f'trace-{case}-summary.json').write_text(json.dumps(result,indent=2))
 print(json.dumps({'Case':case,'BX':markets['BX']},indent=2))
if __name__=='__main__':summarize(sys.argv[1])
