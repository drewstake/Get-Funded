"""Run detached attack simulations and optionally replay an exported saved position."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--snapshot', type=Path)
parser.add_argument('--player', default='player:42875739:single:12')
parser.add_argument('--scenario', choices=['buy', 'sell', 'cycle', 'passive', 'multi-owner', 'rich'])
parser.add_argument('--lune', type=Path, default=ROOT/'tools/runtime/lune.exe')
args = parser.parse_args()
out = args.output.resolve()
if out.exists() or not out.is_relative_to(ROOT):
    parser.error('--output must be a new directory in this repository')
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'src').rglob('*.luau'))}
subprocess.run([sys.executable, str(ROOT/'tools/protection-safety/prepare.py'), '--output', str(out.relative_to(ROOT))], cwd=ROOT, check=True)
for template in ['stress.luau', 'replay_saved.luau', 'refresh_saved.luau']:
    source = (Path(__file__).parent/template).read_text(encoding='utf-8')
    source = source.replace('__OUTPUT__', json.dumps(out.as_posix(), ensure_ascii=False))
    source = source.replace('__SNAPSHOT__', json.dumps(args.snapshot.resolve().as_posix() if args.snapshot else '', ensure_ascii=False))
    source = source.replace('__PLAYER__', json.dumps(args.player))
    (out/template).write_text(source, encoding='utf-8')
if args.snapshot:
    subprocess.run([str(args.lune), 'run', str(out/'replay_saved.luau')], cwd=ROOT, check=True)
    subprocess.run([str(args.lune), 'run', str(out/'refresh_saved.luau')], cwd=ROOT, check=True)
subprocess.run([str(args.lune), 'run', str(out/'stress.luau')] + ([args.scenario] if args.scenario else []), cwd=ROOT, check=True)
assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'src').rglob('*.luau'))}, 'Source changed during validation'
(out/'validated-sources.json').write_text(json.dumps(hashes, indent=2)+'\n')
print('Market safety validation passed:', out)
