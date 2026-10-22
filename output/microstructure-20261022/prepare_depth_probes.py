"""Round 4: quantity at the touch, isolated and crossed with the no-skew ablation."""
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
C=(R/'original/shared/MarketConfig.luau').read_text(encoding='utf8')
assert C.count('MakerLanes = {Count=10,')==1
C=C.replace('MakerLanes = {Count=10,','MakerLanes = {Count=20,')
CP=(R/'variants/maker-no-skew/WorldCheckpoint.luau').read_text(encoding='utf8')
P=(R/'variants/maker-no-skew/Participants.luau').read_text(encoding='utf8')
for name,files in {'sparse-touch':{'MarketConfig.luau':C},'no-skew-sparse-touch':{'MarketConfig.luau':C,'Participants.luau':P}}.items():
 d=R/'variants'/name;d.mkdir(exist_ok=False);files['WorldCheckpoint.luau']=CP
 for f,s in files.items():(d/f).write_text(s,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
(R/'round4-plan.json').write_text(json.dumps({'Basis':'Removing repeated Maker skew cuts minute volatility by 21% and 30-minute range by 47%, while much directional ten-close concentration disappears. The first lane has six of the 60 Makers. Doubling the number of lanes keeps all capital/agents/size limits but places three in each lane, reducing near-touch depth without injecting directional flow.',
 'Variants':['sparse-touch','no-skew-sparse-touch'],
 'Selection':'Isolated depth effect and factorial interaction with previously tested no-skew. Same fixed gates. This is a frozen research config; no ConfigService enrollment, live testing override or live refresh is used because exact checkpoint replay and one shared exchange are required.',
 'Limits':'Count20 is one predeclared discrete depth intervention, not a sweep. Lane spacing, all other config fields, recovery, capital, safeguards and margins are unchanged. A promoted release would require versioned adoption and renewed validation.'},indent=2))
print('Frozen sparse-touch and no-skew-sparse-touch')
