from pathlib import Path
import json
root=Path(__file__).resolve().parent
reports={}
for arm in ('Baseline','Candidate'):
    passed=failed=0; failures=[]; crashed=[]
    for f in (root/'suites').glob(arm+'-*.json'):
        row=json.loads(f.read_text(encoding='utf8'))
        if not row['Ok']:
            crashed.append([row['Suite'],row['Results']]);continue
        tests=row['Results'];tests=tests.get('Results',[])if isinstance(tests,dict)else tests
        for test in tests:
            if test['Passed']:passed+=1
            else:failed+=1;failures.append([row['Suite'],test['Name'],test['Detail']])
    reports[arm]={'Passed':passed,'Failed':failed,'Failures':failures,'Crashed':crashed}
old={(s,n)for s,n,_ in reports['Baseline']['Failures']}
new={(s,n)for s,n,_ in reports['Candidate']['Failures']}
reports['NewFailures']=sorted(new-old)
print('Baseline:',reports['Baseline']['Passed'],'passed;',reports['Baseline']['Failed'],'failed')
print('Candidate:',reports['Candidate']['Passed'],'passed;',reports['Candidate']['Failed'],'failed')
print('New failures:',reports['NewFailures'],'Crashes:',reports['Candidate']['Crashed'])
(root/'suite-comparison.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
assert not reports['NewFailures'] and not reports['Candidate']['Crashed']
