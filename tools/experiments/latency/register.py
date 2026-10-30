from pathlib import Path
import json
root=Path(__file__).resolve().parents[3]
for path in (root/'src').rglob('*Tests.luau'):
    s=path.read_text(encoding='utf-8-sig')
    updated=s.replace('Version==32','Version==33')
    if path.name=='CheckpointCompatibilityTests.luau':
        updated=updated.replace('through V32','through V33').replace('restartable V32','restartable V33')
    if updated!=s:path.write_text(updated,encoding='utf-8')
path=root/'build/place-manifest.json'
m=json.loads(path.read_text())
for name,container in [('MarketPacket','ReplicatedStorage'),('LatencyTests','ServerScriptService')]:
    file=next((root/'src').rglob(name+'.luau')).relative_to(root).as_posix()
    if not any(row['file']==file for row in m['scripts']):
        m['scripts'].append({'file':file,'path':f'{container}.MarketReign.{name}','class':'ModuleScript'})
m['scripts'].sort(key=lambda row:row['file'])
path.write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
