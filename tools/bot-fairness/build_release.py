"""Package only this task's changes; the installer verifies prior source and rolls back on failure."""
from pathlib import Path
import difflib
import hashlib
import json

ROOT=Path(__file__).resolve().parents[2]
BACK=ROOT/'backups/bot-fairness-20261019/src'
OUT=ROOT/'output/bot-fairness-20261019'
def sha(text): return hashlib.sha256(text.replace('\r\n','\n').encode()).hexdigest()
def quote(text):
    assert ']====]' not in text
    return '([====[!'+text+']====]):sub(2)'
modules={};patch=[]
for path in sorted((ROOT/'src').glob('*.luau')):
    previous=BACK/path.name
    # Studio retains an old fixed-multiplier assertion; the workspace fixture already
    # correctly follows configuration. Preserve/review its actual Studio source too.
    if path.name=='MakerLiquidityTests.luau':
        previous=ROOT/'backups/bot-fairness-20261019/studio/MakerLiquidityTests.luau'
    before=previous.read_text(encoding='utf-8-sig') if previous.exists() else ''
    after=path.read_text(encoding='utf-8-sig')
    if before==after: continue
    assert '.server.' not in path.name and '.client.' not in path.name, path
    root='ReplicatedStorage' if path.stem=='MarketConfig' else 'ServerScriptService'
    key=root+'.MarketReign.'+path.stem
    modules[key]={'File':path.relative_to(ROOT).as_posix(),'Source':after,'Hash':sha(after),
                  'ExpectedHash':sha(before) if previous.exists() else None,'ClassName':'ModuleScript'}
    patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile='a/src/'+path.name,tofile='b/src/'+path.name))
assert len(modules)==13, list(modules)
lines=['-- Edit-only install. No DataStore write, cash adjustment, play/stop, file save or publication.',
       'assert(not game:GetService("RunService"):IsRunning(),"Install in Edit mode")',
       'assert(game.PlaceId==137759823569682,"This release targets Get Funded!")',
       'local Encoding=game:GetService("EncodingService")',
       'local function hash(s)local b=Encoding:ComputeStringHash(s:gsub("\\r\\n","\\n"),Enum.HashAlgorithm.Sha256);return(b:gsub(".",function(c)return string.format("%02x",string.byte(c))end))end',
       'local release={}']
for path,item in modules.items():
    lines.append('release['+quote(path)+']={Source='+quote(item['Source'])+',Hash='+quote(item['Hash'])+',ExpectedHash='+(quote(item['ExpectedHash']) if item['ExpectedHash'] else 'nil')+'}')
lines += [
 'local function resolve(path)local parts=string.split(path,".");local parent=game;for i=1,#parts-1 do parent=assert(parent:FindFirstChild(parts[i]),"Missing parent "..path)end;return parent,parts[#parts],parent:FindFirstChild(parts[#parts])end',
 'for path,item in pairs(release)do local _,_,instance=resolve(path);assert(hash(item.Source)==item.Hash,"Bad release "..path);if item.ExpectedHash then assert(instance and instance:IsA("ModuleScript") and (hash(instance.Source)==item.ExpectedHash or hash(instance.Source)==item.Hash),"Source changed: "..path)else assert(not instance or instance:IsA("ModuleScript") and hash(instance.Source)==item.Hash,"New module collision: "..path)end end',
 'local history=game:GetService("ChangeHistoryService");history:SetWaypoint("Before bot fairness fix")',
 'local names={};for path in pairs(release)do table.insert(names,path)end;table.sort(names)',
 'local rollback={};local installed={}',
 'local ok,err=pcall(function()for _,path in ipairs(names)do local item=release[path];local parent,name,instance=resolve(path);if not instance then instance=Instance.new("ModuleScript");instance.Name=name;table.insert(rollback,{Instance=instance,New=true});instance.Source=item.Source;instance.Parent=parent else table.insert(rollback,{Instance=instance,Source=instance.Source});instance.Source=item.Source end;assert(hash(instance.Source)==item.Hash,"Verification failed: "..path);installed[path]=item.Hash end end)',
 'if not ok then for i=#rollback,1,-1 do local row=rollback[i];if row.New then row.Instance:Destroy()else row.Instance.Source=row.Source end end;error(err)end',
 'history:SetWaypoint("Passive liquidity, public reversal signals and bounded bot risk")',
 'return {Installed=installed,Count=#names,Published=false,Saved=false}']
(OUT/'InstallBotFairness.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(OUT/'release.json').write_text(json.dumps(modules,indent=2),encoding='utf-8')
(OUT/'release-manifest.json').write_text(json.dumps({k:{a:b for a,b in v.items() if a!='Source'} for k,v in modules.items()},indent=2),encoding='utf-8')
(OUT/'bot-fairness-only.patch').write_text(''.join(patch),encoding='utf-8')
print('Packaged',len(modules),'sources with prior-hash checks and rollback.')
