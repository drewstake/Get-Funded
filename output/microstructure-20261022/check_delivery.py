"""Check a complete rejection delivery and hash its reproducibility inputs/outputs."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parent
decision=json.loads((R/'decision.json').read_text())
assert not decision['Qualified'] and not decision['Installed'] and not decision['Published']
assert len(decision['Variants'])==15 and all(not x['Pass'] and x['Failed'] for x in decision['Variants'].values())
readback=json.loads((R/'final-studio-readback.json').read_text())
assert readback['Modules']==105 and readback['AllSourceAndEditorMatch']
assert all(x['MatchesOriginal'] and x['EditorMatchesOriginal']for x in readback['Sources'])
integrity=json.loads((R/'run-integrity.json').read_text())
assert integrity['UniqueDevelopmentRuns']==96 and integrity['MeasuredMarketHours']==288
plan=json.loads((R/'experiment.json').read_text())
assert all(not(R/'snapshots'/('normalized-'+name+'.json')).exists()for name in plan['Validation'])
report=(R/'RESULTS.md').read_text(encoding='utf8')
links=re.findall(r'\]\(([^)]+)\)',report)
assert all((R/path).exists()for path in links),[p for p in links if not(R/p).exists()]
endurance=json.loads((R/'endurance-summary.json').read_text())
assert len(endurance)==8 and all(x['Replay'] and x['RecoveryTransfers']==0 and all(k['PositiveEquity']==k['Count']for k in x['Kinds'].values())for x in endurance)
files=set()
for p in R.iterdir():
 if p.is_file() and p.suffix in {'.py','.luau','.json','.md','.png'} and p.name!='reproducibility-manifest.json':files.add(p)
for folder in ['original','snapshots','variants','diagnostics','migrations']:
 files.update(p for p in (R/folder).rglob('*')if p.is_file())
for name in ['baseline']+plan['Candidates']:
 arm='Baseline'if name=='baseline'else'Candidate'
 files.update((R/('development-'+name)).glob('*-'+arm+'.json'))
for folder in R.glob('no-recovery-*'):
 if folder.is_dir():files.update(folder.glob('*.json'))
files.add(R.parent/'momentum-20261021/runtime/lune.exe')
entries={}
for p in sorted(files):
 h=hashlib.sha256()
 with p.open('rb')as f:
  for block in iter(lambda:f.read(1<<20),b''):h.update(block)
 entries[p.relative_to(R).as_posix()if p.is_relative_to(R)else '../'+p.relative_to(R.parent).as_posix()]={'SHA256':h.hexdigest(),'Bytes':p.stat().st_size}
manifest={'Interpretation':'Byte hashes at final delivery; individual frozen variant manifests separately use canonical UTF-8/LF text hashes. Cached baseline copies, progress, scaffolding logs and Python caches are not required for this inventory.','UniqueDevelopmentRuns':96,'MeasuredMarketHours':288,'NoRecoveryEnduranceRuns':8,'ReportLinksChecked':len(links),'StudioReadbackUTC':readback['CheckedUTC'],'Files':entries}
(R/'reproducibility-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('Delivery checks passed:',len(entries),'hashed files;',len(links),'valid report links; 15 rejected variants; 105 unchanged Studio source/editor buffers')
