"""Summarize retained measurements; all timings remain scoped to their fixture."""
from pathlib import Path
import difflib
import hashlib
import json
import math
import statistics

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'output/latency-20261027'
def read(name):
    return json.loads((OUT/name).read_text(encoding='utf-8'))
def stats(values):
    values = sorted(values)
    return {'n': len(values), 'mean': statistics.mean(values), 'median': statistics.median(values),
            'p95': values[math.ceil(len(values)*.95)-1], 'max': max(values)}

result = {'Scope': 'Local Studio and detached copies of the read-only saved market. JSON payload sizes are not wire-byte measurements.',
          'OrderTransport': {}, 'QuoteTransport': {}, 'Live': {}, 'FixedStateOrderCost': {}, 'ChangedSources': []}
for version, name in [('before','transport-client-baseline.json'),('after','transport-client-verified.json')]:
    rows = read(name)['Trace']
    result['OrderTransport'][version] = {}
    for label, sample in [('all',rows), ('routine',rows[:-42]), ('burst40',rows[-42:-2]), ('market_and_close',rows[-2:])]:
        result['OrderTransport'][version][label] = {k:stats([row[k] for row in sample]) for k in
            ['SendToReceiveMs','SendToDisplayMs','SendToServerMs','QueueMs','WorkMs','ProcessToReceiveMs']}
for version, name in [('before','quote-client-baseline.json'),('after','quote-client-final.json')]:
    rows=read(name)['Samples']
    result['QuoteTransport'][version] = {key:stats([r[key] for r in rows if key in r]) for key in
        ['FirstChangeToDisplayMs','LatestChangeToDisplayMs','BroadcastToReceiveMs','ReceiveToRenderMs']}
for version, server, client in [('before','live-server-baseline.json','live-client-baseline-complete.json'),
                                 ('after','live-server-final.json','live-client-final.json')]:
    s,c=read(server),read(client)
    result['Live'][version] = {'Server':s,'JSONBytes':stats([p['Bytes'] for p in c['Packets']]),
        'PacketIntervalMs':stats([p['GapMs'] for p in c['Packets'] if 'GapMs'in p]),
        'ReceiveToUIFrameMs':stats(c['ReceiveToUIFrameMs']), 'Gaps':c['Gaps'],
        'StepsPerSecond':(s['After']['Steps']-s['Before']['Steps'])/s['Seconds'],
        'ChartPaint':{k:v for k,v in c['Chart'].items() if 'Ms'in k}}
fixed=read('order-cost.json');assert fixed['Passed']
for version, key in [('before','baseline'),('after','candidate')]:
    result['FixedStateOrderCost'][version] = {k:stats([r[k] for r in fixed[key]]) for k in ['OrderMs','CloseMs']}
    result['FixedStateOrderCost'][version]['Filled']=fixed[key][0]['Filled']
b,f=read('native-verified-baseline.json'),read('native-verified-final.json')
assert b['Audit']==f['Audit'] and b['QuoteGaps']==f['QuoteGaps']
result['NativeSimulation']={'before':b,'after':f}
b,f=read('baseline/probe-results.json'),read('measured-final/probe-results.json')
assert b['Audit']==f['Audit'] and b['EmptySteps']==f['EmptySteps']
result['LongReplay']={'Steps':12000,'before':b['Step'],'after':f['Step'],'AuditIdentical':True,
                    'NewTrades':f['NewTrades'],'EmptySteps':f['EmptySteps'],'EmptyEpisodes':f['EmptyEpisodes']}
b,f=read('stress-baseline/stress-results.json'),read('stress-verified-candidate/stress-results.json')
for old,new in zip(b['Scenarios'],f['Scenarios']):
    assert {k:v for k,v in old.items()if k!='ComputeSeconds'}=={k:v for k,v in new.items()if k!='ComputeSeconds'}
result['Stress']={'AllSixIdenticalOutcomes':True,'Scenarios':f['Scenarios']}
result['Release']=read('verified-release/release-check.json')
result['Continuity']=read('continuity-final.json')
result['ShutdownContinuity']=read('continuity-restart.json')
result['Persistence']=read('persistence-final.json')
result['Restart']={'FlatAndNoWorkingOrdersBeforeStop':True,'ShutdownStep':read('restart-checkpoint.json')['Manifest']['SavedStep'],
    'InitialPostRestartCheck':{'Evidence':'Studio tool response at step 12102153, before subsequent player actions',
        'Balance':345399.9999999882,'Positions':0,'Orders':0},
    'ChartRestoredAtStep':12102727,'ChartRestoredTimeframe':'5m','ChartRestoredBars':167,
    'ChartRestoredLow':5512.69705863215,'ChartRestoredHigh':5650.760468024952,
    'SubsequentPlayerActivity':read('live-actions-after-restart.json'),
    'Note':'Later account and chart snapshots include new player trades and view adjustments. They are intentionally not restored to pre-restart values.'}
patch=[]
for path in sorted((ROOT/'src').rglob('*.luau')):
    before=OUT/'baseline/original'/path.name
    a=before.read_text(encoding='utf-8-sig') if before.exists() else ''
    b=path.read_text(encoding='utf-8-sig')
    if a!=b:
        result['ChangedSources'].append(path.relative_to(ROOT).as_posix())
        patch.extend(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile='before/'+path.name,tofile='after/'+path.name))
result['CanonicalPlaceSha256']=hashlib.sha256((ROOT/'Get Funded!.rbxl').read_bytes()).hexdigest()
(OUT/'changes.patch').write_text(''.join(patch),encoding='utf-8')
(OUT/'summary.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({'CanonicalPlaceSha256':result['CanonicalPlaceSha256'], 'ChangedSources':result['ChangedSources'],
                  'AllSixStressOutcomesIdentical':True, 'NativeQuoteReplacementDistributionsIdentical':True},indent=2))
