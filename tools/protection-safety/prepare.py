"""Build detached Luau modules; the harness forbids live Roblox services.

From the project root:
  python tools/protection-safety/prepare.py
  tools/runtime/lune.exe run output/test-run/run.luau
Pass suite names or --all to the Luau runner to select more tests.
"""
from pathlib import Path
import argparse, re, shutil
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--output',default='output/test-run')
out=root/parser.parse_args().output;target=out/'candidate';target.mkdir(parents=True,exist_ok=True)
original=out/'original';original.mkdir(parents=True,exist_ok=True)
paths=sorted((root/'src').rglob('*.luau'))
# Roblox modules still share their original instance containers. Flatten only the
# detached harness, where static requires use module filenames. Never silently
# overwrite modules if a future source group introduces an ambiguous basename.
if len({path.name.casefold() for path in paths}) != len(paths):
    raise ValueError('Duplicate source filename in detached harness')
# Reused targeted runs must not retain removed suites or sources.
for directory in (target,original):
    for old in directory.rglob('*.luau'):
        if old.name not in {path.name for path in paths}: old.unlink()
shutil.copyfile(root/'tools/execution-integrity/environment.luau',out/'environment.luau')
shutil.copyfile(root/'tools/protection-safety/report.luau',out/'report.luau')
for path in paths:
    shutil.copyfile(path,original/path.name)
    s=path.read_text(encoding='utf-8-sig')
    s=re.sub(r'require\((?:script\.Parent|game\.(?:ReplicatedStorage|ServerScriptService)\.MarketReign)\.(\w+)\)',r'require("./\1")',s)
    s=re.sub(r'local root=script\.Parent','local root={}',s)
    s=re.sub(r'require\(root\.(\w+)\)',r'require("./\1")',s)
    if 'game:' in s or 'Enum.' in s or 'task.' in s:s='local env=require("../environment")\nlocal game,Enum,task=env.game,env.Enum,env.task\n'+s
    for name in ('Instance','UDim2','UDim','Color3','Vector2','Vector3'):
        if name+'.' in s:s=f'local {name}=require("@lune/roblox").{name}\n'+s
    (target/path.name).write_text(s,encoding='utf-8')
runner=(root/'tools/protection-safety/run.luau').read_text(encoding='utf-8')
runner=runner.replace('output/c1-protection-fix-20261026',out.relative_to(root).as_posix())
(out/'run.luau').write_text(runner,encoding='utf-8')
print('Prepared detached regression modules in '+str(out))
