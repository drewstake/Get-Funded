from pathlib import Path
root = Path(__file__).resolve().parent / 'snapshots'
for first in root.glob('*-1.part'):
    prefix = first.name[:-7]
    chunks = sorted(root.glob(prefix + '-*.part'), key=lambda p: int(p.stem.rsplit('-', 1)[1]))
    (root / (prefix + '.json')).write_bytes(b''.join(p.read_bytes() for p in chunks))
