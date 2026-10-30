from pathlib import Path
import argparse
import subprocess
import shutil
import json
ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('variant', choices=['baseline','candidate'])
parser.add_argument('--steps',type=int,default=12000)
parser.add_argument('--label')
args=parser.parse_args()
out=ROOT/'output/latency-20261027'/(args.label or args.variant)
if args.variant=='candidate':
    subprocess.run([str(ROOT/'.venv-build/Scripts/python.exe'),str(ROOT/'tools/protection-safety/prepare.py'),'--output',str(out)],check=True)
shutil.copyfile(ROOT/'tools/experiments/latency/probe.luau',out/'probe.luau')
source="""local fs=require('@lune/fs');local serde=require('@lune/serde');local env=require('./environment')
local H=env.game:GetService('HttpService');local CP=require('./candidate/WorldCheckpoint')
local snapshot=CP.Decode(H:JSONDecode(fs.readFile('output/latency-20261027/saved-checkpoint.json')).Checkpoint)
local modules={}
__MODULES__
local report=require('./probe').Run(function(name)return assert(modules[name],name)end,snapshot,{Steps=__STEPS__,Scope='Offline Lune; no service access',EncodeJSON=function(v)return H:JSONEncode(v)end})
fs.writeFile('__OUT__/probe-results.json',serde.encode('json',report,true))
print(serde.encode('json',{Step=report.Step,Save=report.EncodeWorld,EmptySteps=report.EmptySteps,EmptyEpisodes=#report.EmptyEpisodes,NewTrades=report.NewTrades}))
"""
source=source.replace('__MODULES__','\n'.join(f"modules['{name}']=require('./candidate/{name}')" for name in ['MarketConfig','WorldCheckpoint','PlayerExecution','MarketSafety']))
source=source.replace('__STEPS__',str(args.steps)).replace('__OUT__',out.relative_to(ROOT).as_posix())
(out/'probe-run.luau').write_text(source,encoding='utf-8')
subprocess.run([str(ROOT/'tools/runtime/lune.exe'),'run',str(out/'probe-run.luau')],cwd=ROOT,check=True)
