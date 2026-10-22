from pathlib import Path
import hashlib, json, shutil
R=Path(__file__).resolve().parent; P=R.parent/'feedback-20261021'
for d in ['snapshots','logs','diagnostics','suites','variants','development-baseline']:(R/d).mkdir(exist_ok=True)
parts=sorted((R/'capture').glob('part-*.txt'),key=lambda p:int(p.stem.split('-')[1]))
(R/'snapshots/normalized-CurrentBX.json').write_bytes(b''.join(p.read_bytes() for p in parts))
checks=[]
for p in (R/'original').rglob('*.luau'):
 old=P/'original'/p.relative_to(R/'original')
 checks.append({'File':p.relative_to(R/'original').as_posix(),'SHA256':hashlib.sha256(p.read_text().encode()).hexdigest(),'MatchesPrior':old.exists() and p.read_text()==old.read_text()})
assert len(checks)==105 and all(x['MatchesPrior'] for x in checks)
s=json.loads((R/'snapshots/normalized-CurrentBX.json').read_text()); assert s['Config']['NewsFrequency']==0
(R/'baseline-verification.json').write_text(json.dumps({'Sources':checks,'Capture':json.loads((R/'capture/metadata.json').read_text()),'SnapshotSHA256':hashlib.sha256((R/'snapshots/normalized-CurrentBX.json').read_bytes()).hexdigest()},indent=2))
for name in ['LocalLab.luau','ExactJson.luau','MomentumBenchmark.luau','analyze.py','shape_metrics.py','metrics.py','plot_comparison.py','TraceDiagnostics.luau','current_chart.py','plot_flow.py','trace_summary.py']:
 (R/name).write_text((P/name).read_text().replace('feedback-20261021','microstructure-20261022'),encoding='utf8')
for name in ['Seed71','Seed7919','Seed104729','Older','Aged']:
 shutil.copy2(P/'snapshots'/f'normalized-{name}.json',R/'snapshots'/f'normalized-{name}.json')
plan=json.loads((P/'experiment.json').read_text())
plan.update({'Date':'2026-10-22','Development':['Seed71','Seed7919','Seed104729','CurrentBX','Older','Aged'],
 'Validation':['Seed42017','Seed88069','CurrentBXLater','AgedLater'],
 'Candidates':['reserve-delay','reserve-rest','maker-rest','maker-no-skew'],
 'Selection':'Iterative controlled development; each new arm frozen before running. Reserve holdouts remain unread until a single candidate passes all development gates and chart review. Failed holdouts cannot be reused for tuning.',
 'AdditionalGates':{'StrictPullbacks':'At least one more completed strict pullback than baseline in total','CurrentBXMinuteRVRatio':.9,'Range30RetentionRatio':.8},
 'Ablations':'reserve-delay removes same-decision replacement; reserve-rest retains quotes until existing expiry; maker-rest retains normal quotes except existing adverse stale-risk cancellation; maker-no-skew removes only inventory reservation-price skew, retaining quantity feedback. Each arm changes one mechanism.'})
(R/'experiment.json').write_text(json.dumps(plan,indent=2))
p=(R/'original/server/Participants.luau').read_text(); cp=(R/'original/server/WorldCheckpoint.luau').read_text()
reserve='e:Cancel(a.Id,held.Id);held=nil\n  end'
assert p.count(reserve)==1
variants={
 'reserve-delay':p.replace(reserve,'e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil;a.ReserveReplenishAt[slot]=e.Time+(c.ReplenishSeconds or 0)\n  end'),
 'reserve-rest':p.replace('if held and e.Time-held.Time>=c.RestSeconds and math.abs(held.Price-tick)>=c.RepriceTicks then','if false and held and e.Time-held.Time>=c.RestSeconds and math.abs(held.Price-tick)>=c.RepriceTicks then'),
 'maker-rest':p.replace('if held and (stale or age>=minRest and (not eligible or math.abs(held.Price-tick)>=reprice))then','if held and (stale or age>=minRest and not eligible)then'),
 'maker-no-skew':p.replace('local center=reference-inventory/a.Limit*(5+stress*5)','local center=reference'),
}
for name,source in variants.items():
 assert source!=p
 d=R/'variants'/name;d.mkdir(exist_ok=True)
 files={'Participants.luau':source,'WorldCheckpoint.luau':cp.replace('Version=28,Readable={[28]=true','Version=29,Readable={[29]=true,[28]=true')}
 for name,src in files.items():(d/name).write_text(src,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({name:hashlib.sha256(src.encode()).hexdigest() for name,src in files.items()},indent=2))
print('Verified all 105 installed modules. Captured current saved step',s['Engine']['Step'])
