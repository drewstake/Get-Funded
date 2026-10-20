import subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
variant=sys.argv[1];seconds=sys.argv[2]
for seed in sys.argv[3:]:
    subprocess.run([str(ROOT/'tmp/single-account/runtime/lune.exe'),'run','tmp/bot-population/compare.luau',variant,seed,seconds],cwd=ROOT,check=True)
