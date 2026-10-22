from pathlib import Path
import json
R=Path(__file__).resolve().parent
parts=sorted(R.glob('native-parity-*.part'),key=lambda p:int(p.stem.split('-')[-1]))
a=json.loads(b''.join(p.read_bytes()for p in parts));b=json.loads((R/'parity-local-Candidate-Seed71.json').read_text(encoding='utf8'));differences=[]
def compare(a,b,path='root'):
 if a in ({},[])and b in ({},[]):return
 if type(a)!=type(b)and not(isinstance(a,(int,float))and isinstance(b,(int,float))):differences.append((path,'type'));return
 if isinstance(a,dict):
  for k in a.keys()|b.keys():
   if k not in a or k not in b:differences.append((path+'.'+k,'missing'))
   else:compare(a[k],b[k],path+'.'+k)
 elif isinstance(a,list):
  if len(a)!=len(b):differences.append((path,'length'))
  for i,(x,y)in enumerate(zip(a,b)):compare(x,y,path+f'[{i}]')
 elif a!=b:differences.append((path,a,b))
compare(a,b)
result={'Differences':len(differences),'Examples':differences[:20],'Steps':400,'TradeHash':a['Engine']['TradeHash']}
(R/'runtime-parity.json').write_text(json.dumps(result,indent=2));print(result);assert not differences
