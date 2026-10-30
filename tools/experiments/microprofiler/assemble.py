"""Recover native .gprx captures from the loopback transport's compressed pieces."""
from pathlib import Path
import base64, json, zstandard
root=Path(__file__).resolve().parents[3]/'output/microprofiler-20261027'
for prefix in ('before','callback','native-candidate','checkpoint-confirmed','after'):
 for meta in root.glob(prefix+'-*-info.json'):
  name=meta.name.removesuffix('-info.json'); info=json.loads(meta.read_text())
  output=root/(name+'.gprx')
  if output.exists(): continue
  packed=''.join(json.loads((root/f'{name}-part-{i}.json').read_text())['Data'] for i in range(1,info['Parts']+1))
  raw=zstandard.decompress(base64.b64decode(packed));assert len(raw)==info['Bytes']
  output.write_bytes(raw)
print('Native profiler captures assembled')
