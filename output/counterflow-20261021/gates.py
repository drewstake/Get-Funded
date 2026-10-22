from pathlib import Path
import json,sys,hashlib
from shape_metrics import summarize
R=Path(__file__).resolve().parent
def check(folder,variant):
    d=summarize(folder);b,c=d['Aggregate']['Baseline'],d['Aggregate']['Candidate']
    g=json.loads((R/'experiment.json').read_text())['Gates'];checks={}
    for field,ratio in [('LongRun8CandleShare',.75),('Directional10WindowFraction',.75),('LongestRun',.8)]:checks[field]=c[field]<=b[field]*ratio
    for field,ratio in [('Pullbacks',1.5),('OneSecondRV',1),('FifteenSecondMidpointRV',1),('OneMinuteRV',.9),('MeanMinuteRangePercent',.9),('MeanRange30',.9)]:checks[field]=c[field]>=b[field]*ratio
    checks['Complete']=len(d['Cases'])==6
    checks['Shape majority']=len(d['Wins']['Shape'])>=4;checks['Pullback majority']=len(d['Wins']['Pullbacks'])>=4
    checks['Recovery']=c['Recovery']<=b['Recovery']*1.1;checks['Barcode']=c['Alternating4Fraction']<.08
    checks['Replay']=c['Replay']and b['Replay'];checks['Solvency']=c['Insolvent']<=b['Insolvent'];checks['Participation']=c['Eligible']>=b['Eligible']*.95
    checks['Quote availability']=c['NoQuoteFraction']<=max(.001,b['NoQuoteFraction']*1.1)
    latest={r['Arm']:r for r in d['Markets'] if r['Case']=='Latest' and r['Market']=='BX'}
    if len(latest)==2:
        x,y=latest['Baseline'],latest['Candidate']
        checks['Current BX long-leg share']=y['LongRun8CandleShare']<=x['LongRun8CandleShare']*.75
        checks['Current BX significant streak']=y['SignificantLongestRun']<=x['SignificantLongestRun']*.8
        checks['Current BX pullbacks']=y['Pullbacks']>x['Pullbacks']
    else:checks['Current BX complete']=False
    manifest=json.loads((R/'variants'/variant/'manifest.json').read_text())
    checks['Frozen production source']=all(hashlib.sha256((R/'variants'/variant/name).read_bytes()).hexdigest()==h for name,h in manifest.items())
    result={'Passed':all(checks.values()),'Checks':checks,**d}
    (R/(folder+'-gates.json')).write_text(json.dumps(result,indent=2),encoding='utf8')
    return result
if __name__=='__main__':
    for variant in ['profit','profit-patient']:
        d=check('results-'+variant,variant)
        print(json.dumps({'Variant':variant,'Passed':d['Passed'],'Checks':d['Checks'],'Aggregate':d['Aggregate'],'Wins':d['Wins']},indent=2))
