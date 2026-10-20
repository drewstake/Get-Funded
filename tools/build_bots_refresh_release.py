"""Package only this task's edits, preserving the earlier execution/performance fixes."""
from pathlib import Path
import difflib, hashlib, json

ROOT=Path(__file__).resolve().parents[1]
BACK=ROOT/'backups/bots-refresh-20261015'
OUT=ROOT/'output/bots-refresh-20261015'
FILES=['BotRefresh.luau','OwnerBotsCommand.luau','BotRefreshTests.luau','MarketEngine.luau',
       'BotPopulation.luau','WorldService.luau','WorldCheckpoint.luau','MarketServer.server.luau']
old=json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
def sha(s): return hashlib.sha256(s.replace('\r\n','\n').encode()).hexdigest()
def quote(s):
    assert ']====]' not in s
    return '([====[!'+s+']====]):sub(2)'

release={}
for name in FILES:
    path='ServerScriptService.MarketReign.'+name.replace('.server','').removesuffix('.luau')
    source=(ROOT/'src'/name).read_text(encoding='utf-8-sig')
    release[path]={'Source':source,'Hash':sha(source),'ExpectedHash':sha(old[path]) if path in old else None,
                   'ClassName':'Script' if '.server.' in name else 'ModuleScript','File':name}
lines=['-- Edit-only install. No play/stop action, checkpoint write, local save, or publication.',
       'assert(not game:GetService("RunService"):IsRunning(),"Stop Play safely before installing /bots refresh.")',
       'local Encoding=game:GetService("EncodingService")',
       'local function hash(s)local b=Encoding:ComputeStringHash(s:gsub("\\r\\n","\\n"),Enum.HashAlgorithm.Sha256);return(b:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end',
       'local release={}']
for path,item in release.items():
    lines.append('release['+quote(path)+']={Source='+quote(item['Source'])+',Hash='+quote(item['Hash'])+',ExpectedHash='+(quote(item['ExpectedHash']) if item['ExpectedHash'] else 'nil')+',ClassName='+quote(item['ClassName'])+'}')
lines += [
 'local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end',
 'for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Release hash mismatch "..path);if item.ExpectedHash then assert(instance and instance.ClassName==item.ClassName,"Missing/wrong class "..path);assert(hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash,"Source changed since backup: "..path)else assert(not instance or instance.ClassName==item.ClassName and hash(instance.Source)==item.Hash,"New module collision "..path)end end',
 'local ordered={};for path in pairs(release)do table.insert(ordered,path)end;table.sort(ordered)',
 'for _,path in ipairs(ordered)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new(item.ClassName);instance.Name=name;instance.Source=item.Source;instance.Parent=parent else instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Installed source mismatch "..path)end',
 'return "Installed /bots refresh (8 sources). Save the local place, then start a new play session. Nothing published."']
installer='\n'.join(lines)+'\n'
(OUT/'InstallBotsRefresh.luau').write_text(installer,encoding='utf-8')
(OUT/'release.json').write_text(json.dumps(release,indent=2),encoding='utf-8')
(OUT/'source-manifest.json').write_text(json.dumps({p:{k:v for k,v in x.items()if k!='Source'}for p,x in release.items()},indent=2))
patch=[]
for name in FILES:
    original=BACK/'source-complete'/name
    before=original.read_text(encoding='utf-8-sig')if original.exists()else ''
    after=(ROOT/'src'/name).read_text(encoding='utf-8-sig')
    patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/src/'+name,tofile='b/src/'+name))
for relative in ['tools/ReplenishBotCapital.luau','MARKET_ENGINE.md']:
    patch.extend(difflib.unified_diff((BACK/relative).read_text(encoding='utf-8-sig').splitlines(True),(ROOT/relative).read_text(encoding='utf-8-sig').splitlines(True),fromfile='a/'+relative,tofile='b/'+relative))
(OUT/'bots-refresh-only.patch').write_text(''.join(patch),encoding='utf-8')
unchanged=[]
for original in (BACK/'source-complete').glob('*.luau'):
    if original.name not in FILES:
        assert original.read_bytes()==(ROOT/'src'/original.name).read_bytes(),'Unrelated source changed: '+original.name
        unchanged.append(original.name)
(OUT/'scope-audit.json').write_text(json.dumps({'ReleaseFiles':FILES,'UnchangedSources':sorted(unchanged),
 'ProtectedSources':['MarketConfig.luau','Participants.luau','BotExitRetry.luau','SimulationScheduler.luau','PlayerExecution.luau','RequestJournal.luau','RequestQueue.luau','ProtectiveOrders.luau']},indent=2))
print('Packaged 8 sources with Edit-only and source-hash checks.')
