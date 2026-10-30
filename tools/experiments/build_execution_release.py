"""Package the validated sources with an Edit-only, hash-checked Studio installer."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import hashlib, json, difflib
ROOT=Path(__file__).resolve().parents[2]
BACK=ROOT/'backups/execution-integrity-20261015'
OUT=ROOT/'output/execution-integrity-20261015'
FILES=['MarketEngine.luau','MarketServer.server.luau','MarketClient.luau','PlayerExecution.luau','ProtectiveOrders.luau','ProtectiveOrdersTests.luau','Participants.luau','BotExitRetry.luau','BotExitRetryTests.luau','WorldCheckpoint.luau','WorldService.luau','ExecutionIntegrityTests.luau','RequestJournal.luau','RequestJournalTests.luau','RequestQueue.luau']
old=json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
def sha(s): return hashlib.sha256(s.replace('\r\n','\n').encode()).hexdigest()
def quote(s):
    assert ']====]' not in s
    # Luau discards the first newline of a long string. A sentinel preserves
    # leading blank lines so the embedded source matches its verified hash.
    return '([====[!'+s+']====]):sub(2)'
release={}
for file in FILES:
    name=file.replace('.server','').replace('.client','').removesuffix('.luau')
    path=('ReplicatedStorage' if name=='MarketClient' else 'ServerScriptService')+'.MarketReign.'+name
    source=(source_file(ROOT, file)).read_text(encoding='utf-8-sig')
    release[path]={'Source':source,'Hash':sha(source),'ExpectedHash':sha(old[path]) if path in old else None,'ClassName':'Script' if '.server.' in file else 'ModuleScript','File':file}
(OUT/'release.json').write_text(json.dumps(release,indent=2),encoding='utf-8')
lines=['-- No DataStore writes, no Play/Stop action, no save or publication. Run only after stopping safely.',
       'assert(not game:GetService("RunService"):IsRunning(),"Installation requires Edit mode; active positions/orders must be reviewed before stopping.")',
       'local Encoding=game:GetService("EncodingService")',
       'local function hash(source)local bytes=Encoding:ComputeStringHash(source:gsub("\\r\\n","\\n"),Enum.HashAlgorithm.Sha256);return(bytes:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end',
       'local release={}']
for path,item in release.items():
    lines.append('release[ '+quote(path)+' ]={Source='+quote(item['Source'])+',Hash='+quote(item['Hash'])+',ExpectedHash='+(quote(item['ExpectedHash']) if item['ExpectedHash'] else 'nil')+',ClassName='+quote(item['ClassName'])+'}')
lines += ['local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end',
          'for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Release hash mismatch "..path);if item.ExpectedHash then assert(instance and instance.ClassName==item.ClassName,"Missing/wrong class "..path);assert(hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash,"Source changed since evidence capture: "..path)else assert(not instance or instance.ClassName==item.ClassName and hash(instance.Source)==item.Hash,"New module collision "..path)end end',
          'local ordered={};for path in pairs(release)do table.insert(ordered,path)end;table.sort(ordered)',
          'for _,path in ipairs(ordered)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new(item.ClassName);instance.Name=name;instance.Source=item.Source;instance.Parent=parent else instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Installed hash mismatch "..path)end',
          'return "Installed "..#ordered.." validated sources. No restart, save or publication was performed by this installer."']
(OUT/'InstallValidatedExecution.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(OUT/'source-manifest.json').write_text(json.dumps({p:{k:v for k,v in x.items() if k!='Source'} for p,x in release.items()},indent=2))
patch=[]
for file in FILES:
    before=source_file(BACK, file)
    old_source=before.read_text(encoding='utf-8-sig') if before.exists() else ''
    new_source=(source_file(ROOT, file)).read_text(encoding='utf-8-sig')
    patch.extend(difflib.unified_diff(old_source.splitlines(True),new_source.splitlines(True),fromfile='a/src/'+file,tofile='b/src/'+file))
(OUT/'execution-only.patch').write_text(''.join(patch),encoding='utf-8')
unchanged=[]
for file in (BACK/'src').rglob('*.luau'):
    if file.name not in FILES:
        assert file.read_bytes()==(source_file(ROOT, file.name)).read_bytes(), 'Unrelated source changed: '+file.name
        unchanged.append(file.name)
(OUT/'scope-audit.json').write_text(json.dumps({'ReleaseFiles':FILES,'UnrelatedSourcesUnchanged':sorted(unchanged)},indent=2))
(BACK/'private-installer.json').write_text(json.dumps({'Code':(OUT/'InstallValidatedExecution.luau').read_text(encoding='utf-8')}),encoding='utf-8')
print('Packaged',len(release),'sources; installer refuses Play mode and changed sources.')
