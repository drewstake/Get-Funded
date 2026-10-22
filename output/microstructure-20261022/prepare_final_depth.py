from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent; source=R/'variants/no-skew-sparse-whale'; target=R/'variants/no-skew-sparse30-whale';target.mkdir(exist_ok=False)
files={p.name:p.read_text(encoding='utf8')for p in source.glob('*.luau')}
assert files['MarketConfig.luau'].count('MakerLanes = {Count=20,')==1
files['MarketConfig.luau']=files['MarketConfig.luau'].replace('MakerLanes = {Count=20,','MakerLanes = {Count=30,')
for f,s in files.items():(target/f).write_text(s,encoding='utf8')
(target/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
(R/'round6-plan.json').write_text(json.dumps({'Variant':'no-skew-sparse30-whale','Change':'From the frozen no-skew/sparse/Whale arm, change only Maker lanes from 20 to 30 (three to two makers per lane). Preserve spacing, quote sizes, all inventory/capital/margin/participation limits and slippage guards.',
 'Basis':'The 20-lane combination raised meaningful counter events 61 to 102 and strict completed pullbacks 0 to 12, with minute and midpoint RV retained; max leg falls 23.17 to 17.33. Occupancy 75.65% narrowly misses 74.15%; range 0.343% misses 0.372%; CurrentBX movement also fails. Less touch depth is a previously isolated mechanism for restoring movement, not a new price target.',
 'Gates':'Unchanged. This is a new frozen development candidate. No independent-validation cases have been accessed. This completes the planned depth follow-up; no threshold relaxation or validation extension.'},indent=2))
print('Frozen no-skew-sparse30-whale')
