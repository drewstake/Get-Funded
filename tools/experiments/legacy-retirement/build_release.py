import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[3]
BACK=ROOT/'backups/legacy-retirement-20261018'
OUT=ROOT/'output/legacy-retirement-20261018'
old=json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
def sha(text):return hashlib.sha256(text.replace('\r\n','\n').encode()).hexdigest()
modules={}
for path in (ROOT/'src').rglob('*.luau'):
    before=source_file(BACK, path.name)
    source=path.read_text(encoding='utf-8-sig')
    if before.exists() and before.read_text(encoding='utf-8-sig')==source:continue
    assert '.server.' not in path.name and '.client.' not in path.name
    matches=[key for key in old if key.split('.')[-1]==path.stem]
    assert len(matches)<=1,path
    key=matches[0] if matches else 'ServerScriptService.MarketReign.'+path.stem
    previous=old.get(key)
    if before.exists():
        assert previous is not None,key+' missing from Studio backup'
        # Reviewed difference: Studio's older WorldTests still expected the pre-V15
        # population. Bring that test module up to the already-validated fixtures.
        if path.stem!='WorldTests':assert sha(previous)==sha(before.read_text(encoding='utf-8-sig')),key+' differs from original workspace'
    else:assert previous is None,key+' already exists'
    modules[key]={'File':path.relative_to(ROOT).as_posix(),'Hash':sha(source),'PriorHash':sha(previous) if previous is not None else None}
(OUT/'release-manifest.json').write_text(json.dumps({'Modules':modules},indent=2))
installer=(ROOT/'tools/experiments/bot-strategy/InstallStudio.luau').read_text().replace('8798','8796').replace('Before bot strategy update','Before legacy market retirement').replace('Bot fair tracking, reversal confirmation and scalper filters','Legacy markets settled and archived; only BX BT BG active')
(Path(__file__).parent/'InstallStudio.luau').write_text(installer)
print(json.dumps({'Modules':list(modules),'Count':len(modules)},indent=2))
