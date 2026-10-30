import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import difflib, json
root = Path(__file__).resolve().parents[2]
changes = []
for name, file, parent in [
    ('MarketDepthAccess','MarketDepthAccess.luau','ServerScriptService'),
    ('Level2View','Level2View.luau','ReplicatedStorage'),
    ('MarketServer','MarketServer.server.luau','ServerScriptService'),
    ('MarketClient','MarketClient.luau','ReplicatedStorage'),
    ('ShopView','ShopView.luau','ReplicatedStorage'),
    ('TerminalUI','TerminalUI.luau','ReplicatedStorage'),
]:
    new = (source_file(root, file)).read_text(encoding='utf-8')
    baseline = root/'backups/level2-20261002/studio'/f'{name}.luau'
    edits=[]
    if baseline.exists():
        a=baseline.read_text(encoding='utf-8').splitlines(True)
        b=new.splitlines(True)
        for group in difflib.SequenceMatcher(None,a,b).get_grouped_opcodes(3):
            edits.append({'old_string':''.join(a[group[0][1]:group[-1][2]]), 'new_string':''.join(b[group[0][3]:group[-1][4]])})
    else:
        edits=[{'old_string':'','new_string':new}]
    changes.append({'name':name,'file_path':f'game.{parent}.MarketReign.{name}','edits':edits,'new':not baseline.exists()})
print(json.dumps(changes,ensure_ascii=True))
