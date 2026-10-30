"""Bundle both bot commands against the backed-up Studio Edit source."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import json, hashlib, difflib
ROOT=Path(__file__).resolve().parents[2]
BACK=ROOT/'backups/bots-stats-20261015'
OUT=ROOT/'output/bots-stats-20261015'
NAMES=['BotRefresh','OwnerBotsCommand','BotRefreshTests','MarketEngine','BotPopulation','WorldService','WorldCheckpoint','BotStats','BotStatsTests']
PATHS={f'ServerScriptService.MarketReign.{n}':f'{n}.luau' for n in NAMES}
PATHS.update({'ServerScriptService.MarketReign.MarketServer':'MarketServer.server.luau',
              'ReplicatedStorage.MarketReign.BotStatsView':'BotStatsView.luau',
              'StarterGui.MarketReign.TradingClient':'TradingClient.client.luau'})
old=json.loads((BACK/'private-studio-sources.json').read_text())['Sources']
def sha(s):return hashlib.sha256(s.replace('\r\n','\n').encode()).hexdigest()
def quote(s):
    assert ']====]' not in s
    return '([====[!'+s+']====]):sub(2)'
release={}
for path,name in PATHS.items():
    source=(source_file(ROOT, name)).read_text(encoding='utf-8-sig')
    release[path]={'Source':source,'Hash':sha(source),'ExpectedHash':sha(old[path]) if path in old else None,
                   'ClassName':'Script' if '.server.' in name else 'LocalScript' if '.client.' in name else 'ModuleScript','File':name}
lines=['-- Edit-only, hash-checked install; never runs commands, saves checkpoints or publishes.',
       'assert(not game:GetService("RunService"):IsRunning(),"Stop Play before installing bot commands.")',
       'local E=game:GetService("EncodingService")',
       'local function hash(s)local b=E:ComputeStringHash(s:gsub("\\r\\n","\\n"),Enum.HashAlgorithm.Sha256);return(b:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end',
       'local release={}']
for path,item in release.items():
    lines.append('release['+quote(path)+']={Source='+quote(item['Source'])+',Hash='+quote(item['Hash'])+',ExpectedHash='+(quote(item['ExpectedHash'])if item['ExpectedHash']else'nil')+',ClassName='+quote(item['ClassName'])+'}')
lines += ['local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end',
          'for path,item in pairs(release)do local _,_,v=resolve(path);assert(hash(item.Source)==item.Hash,"Release hash mismatch "..path);if item.ExpectedHash then assert(v and v.ClassName==item.ClassName,"Wrong class "..path);assert(hash(v.Source)==item.ExpectedHash or hash(v.Source)==item.Hash,"Source changed since backup "..path)else assert(not v or v.ClassName==item.ClassName and hash(v.Source)==item.Hash,"New module collision "..path)end end',
          'local paths={};for path in pairs(release)do table.insert(paths,path)end;table.sort(paths)',
          'for _,path in ipairs(paths)do local item=release[path];local parent,name,v=resolve(path);if not v then v=Instance.new(item.ClassName);v.Name=name;v.Source=item.Source;v.Parent=parent else v.Source=item.Source end;assert(hash(v.Source)==item.Hash,"Installed hash mismatch "..path)end',
          'return "Installed /bots refresh and /bots stats. Save locally. Nothing published."']
(OUT/'InstallBotCommands.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(OUT/'release.json').write_text(json.dumps(release,indent=2),encoding='utf-8')
(OUT/'source-manifest.json').write_text(json.dumps({p:{k:v for k,v in x.items()if k!='Source'}for p,x in release.items()},indent=2))
patch=[]
changed=['OwnerBotsCommand.luau','MarketServer.server.luau','TradingClient.client.luau','BotStats.luau','BotStatsTests.luau','BotStatsView.luau']
for name in changed:
    before=source_file(BACK, name)
    patch.extend(difflib.unified_diff(before.read_text(encoding='utf-8-sig').splitlines(True)if before.exists()else[],(source_file(ROOT, name)).read_text(encoding='utf-8-sig').splitlines(True),fromfile='a/src/'+name,tofile='b/src/'+name))
(OUT/'stats-only.patch').write_text(''.join(patch),encoding='utf-8')
unchanged=[]
for path in (BACK/'src').rglob('*.luau'):
    if path.name not in changed:
        assert path.read_bytes()==(source_file(ROOT, path.name)).read_bytes(),'Unrelated source changed: '+path.name
        unchanged.append(path.name)
(OUT/'scope-audit.json').write_text(json.dumps({'Changed':changed,'Unchanged':sorted(unchanged)},indent=2))
print('Packaged',len(release),'sources; stats implementation changes only',len(changed),'files.')
