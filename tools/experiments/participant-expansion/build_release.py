"""Freeze the reviewed participant expansion V23 sources, with actual Studio preflight hashes."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'output/participant-expansion-20261019'
BACK=ROOT/'backups/participant-expansion-20261019'
targets=json.loads((OUT/'targets.json').read_text())

prior=json.loads((BACK/'private-studio-before.json').read_text())
prior.update(json.loads((BACK/'private-studio-extra.json').read_text()))
prior.update(json.loads((BACK/'private-studio-liquidity.json').read_text()))
prior.update(json.loads((BACK/'private-studio-signals.json').read_text()))

def sha(s):return hashlib.sha256(s.replace('\r\n','\n').encode()).hexdigest()
release={}
for path,filename in targets.items():
    source=(ROOT/filename).read_text(encoding='utf-8-sig')
    release[path]={'File':filename,'Source':source,'Hash':sha(source),
                   'ExpectedHash':sha(prior[path]) if prior.get(path) else False,
                   'ClassName':'Script' if '.server.' in filename else 'ModuleScript'}
(OUT/'release.json').write_text(json.dumps(release,indent=2),encoding='utf-8')
(OUT/'release-manifest.json').write_text(json.dumps({k:{a:b for a,b in v.items() if a!='Source'} for k,v in release.items()},indent=2),encoding='utf-8')
print('Frozen',len(release),'reviewed sources; no Studio changes')
