"""Find a source by filename without depending on its filesystem group."""
from pathlib import Path


def source_file(root, filename):
    name = Path(filename).name
    if str(filename) != name:
        raise ValueError(f'Expected a source filename: {filename}')
    matches = list((Path(root) / 'src').rglob(name))
    if len(matches) != 1 or not matches[0].is_file():
        raise ValueError(f'Expected exactly one source named {name}, found {len(matches)}')
    return matches[0]
