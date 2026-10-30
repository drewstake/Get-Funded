from pathlib import Path
import csv, json, statistics
ROOT=Path(__file__).resolve().parents[2]
BACK=ROOT/'backups/execution-integrity-20261015'; OUT=ROOT/'output/execution-integrity-20261015'
live=json.loads((BACK/'private-live-capture.json').read_text())
observed=json.loads((BACK/'private-observed-crossings.json').read_text())
trace=[]
for r in observed['Rows']:
    target=r['Target']; target_price=target['Price']*.25
    ahead=sum(o['Remaining'] for level in r['Asks'] for o in level['Orders'] if level['Price']<target['Price'] or level['Price']==target['Price'] and o['Priority']<target['Priority'])
    active=any(o['Id']==target['Id'] for level in r['Asks'] for o in level['Orders']) and not target.get('Queued',False)
    assert active and target['Time']<r['Time'] and ahead==0 and target_price-r['Fair']>r['GuardTicks']*.25
    trace.append({'TradeId':r['TradeId'],'Step':r['Step'],'SimulationTime':r['Time'],'Price':r['Price'],'Quantity':r['Quantity'],'Fair':r['Fair'],
                  'BestBid':r.get('Bid'),'BestAsk':r.get('Ask'),'TPOrder':target['Id'],'TPPrice':target_price,'TPRemaining':target['Remaining'],'TPSubmitted':target['Time'],
                  'TPPriority':target['Priority'],'QuantityAhead':ahead,'IncomingOrder':r['Incoming']['Id'],'IncomingRemaining':r['Incoming']['Remaining'],
                  'ExecutedOrder':r['Resting']['Id'],'ExecutedPriority':r['Resting']['Priority'],
                  'Reason':'Player-only fair-value collar skipped active TP; bot quote was exempt'})
with (OUT/'observed-trade-throughs.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(trace[0]));writer.writeheader();writer.writerows(trace)
summary={'ObservedExecutions':len(trace),'ObservedContracts':sum(x['Quantity'] for x in trace),'Position':live['Position'],'Target':live['Target'],
         'CaptureStep':live['Step'],'CaptureSimulationTime':live['Time'],'FairAtCapture':live['Snapshot']['Engine']['Books']['BX']['FairReference']*.25,
         'ChartMarket':'BX','ObservedFairMin':min(x['Fair'] for x in trace),'ObservedFairMax':max(x['Fair'] for x in trace),
         'LegitimateExplanationsExcluded':['TP predated every observed execution','TP was resting, not queued','No earlier quantity ahead at its price','Opposing quantity was positive','Owner connected and account not locked','Reduce-only position identity and quantity matched'],
         'Limitations':['Historical events outside the observation window lack the pre-match fair value and order identities needed for complete attribution.','Session restart/reconnect was observed between initial diagnostics and the detailed capture; this task did not issue a Play/Stop command.']}
(OUT/'incident-summary.json').write_text(json.dumps(summary,indent=2))
bench=json.loads((OUT/'captured-replay-benchmark.json').read_text())
metrics={}
for name in ('baseline','candidate'):
    runs=[r for r in bench['Runs'] if r['Variant']==name]
    metrics[name]={k:statistics.median(r[k] for r in runs) for k in ['MeanMs','P95Ms','MaxMs','ThroughputStepsPerSecond','FullBookScans','FailedExitAttempts','SubmitCalls']}
metrics['MeanLatencyReductionPercent']=(1-metrics['candidate']['MeanMs']/metrics['baseline']['MeanMs'])*100
metrics['P95ReductionPercent']=(1-metrics['candidate']['P95Ms']/metrics['baseline']['P95Ms'])*100
metrics['ScanReductionPercent']=(1-metrics['candidate']['FullBookScans']/metrics['baseline']['FullBookScans'])*100
(OUT/'performance-summary.json').write_text(json.dumps(metrics,indent=2))
print(json.dumps(metrics,indent=2))
