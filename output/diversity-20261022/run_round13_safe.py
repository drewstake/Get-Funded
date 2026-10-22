from pathlib import Path
import subprocess,json,hashlib,sys
R=Path(__file__).resolve().parent;L=R.parent/'momentum-20261021/runtime/lune.exe';names=['rolling-portfolio-safe','rolling-patient-safe']
for name in names:
 p=subprocess.run([str(L),'run',str(R/'LocalLab.luau'),'suite','Candidate','BotDiversityTests','variants/'+name,'suites'],capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
 (R/'logs'/('focused-'+name+'.log')).write_text(p.stdout+p.stderr,encoding='utf8');assert p.returncode==0,p.stderr
 d=json.loads((R/'suites/Candidate-BotDiversityTests.json').read_text());assert d['Ok']and all(x['Passed']for x in d['Results']),d
 d['Variant']=name;d['TestSHA256']=hashlib.sha256((R/'BotDiversityTests.luau').read_text(encoding='utf8').encode()).hexdigest()
 (R/('focused-'+name+'.json')).write_text(json.dumps(d,indent=2));print('Focused passed',name,len(d['Results']),flush=True)
subprocess.run([sys.executable,'-X','utf8',str(R/'run_batch.py'),'development',*names],check=True)
