from pathlib import Path
import json
root = Path(__file__).resolve().parents[3]
out = root/'output/latency-20261027'
parts = sorted(out.glob('saved-checkpoint-*.json'))
assert len(parts) == 4
raw = ''.join(json.loads(p.read_text())['Data'] for p in parts)
assert json.loads(raw)['Checkpoint']['Version'] == 32
(out/'saved-checkpoint.json').write_text(raw, encoding='utf-8')
print('Read-only saved checkpoint assembled:', len(raw))
