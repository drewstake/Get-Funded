from pathlib import Path
import json,hashlib,importlib.util
R=Path(__file__).resolve().parent;W=R.parents[1]
validation=json.loads((R/'native-validation.json').read_text());assert validation['Ok']and validation['Result']['Passed']
manifest=json.loads((R/'manifest.json').read_text())
assert all(hashlib.sha256((R/'candidate'/n).read_text(encoding='utf8').encode()).hexdigest()==h for n,h in manifest.items())
# Reuse only the replacement function, never rerun candidate freezing on import.
namespace={};text=(R/'prepare.py').read_text(encoding='utf8');start=text.index('def once(');end=text.index("for name in ['MarketClient.luau'")
exec(text[start:end],namespace)
backup=R/'repo-before';backup.mkdir(exist_ok=True)
for name in ['MarketClient.luau','TerminalUI.luau','ChartView.luau']:
 p=W/'src'/name;assert not(backup/name).exists(),'Local update already done'
 (backup/name).write_bytes(p.read_bytes());before=p.read_text(encoding='utf8');after=namespace['change'](name,before)
 # Keep the original working-tree newline style and its unrelated version differences.
 newline='\r\n'if b'\r\n'in p.read_bytes()else'\n'
 with p.open('w',encoding='utf8',newline=newline)as f:f.write(after)
p=W/'src/ChartTimeframes.luau';assert not p.exists();p.write_bytes((R/'candidate/ChartTimeframes.luau').read_bytes())
print('Updated four local src files with scoped presentation edits; original repo files backed up')
