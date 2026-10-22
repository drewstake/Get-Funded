from pathlib import Path
import shutil,json
R=Path(__file__).resolve().parent;P=R.parent/'microstructure-20261022'
for name in ['original','snapshots']:
 shutil.copytree(P/name,R/name)
for name in ['ExactJson.luau','LocalLab.luau','MomentumBenchmark.luau','TraceDiagnostics.luau','QuoteDriftProbe.luau','metrics.py','analyze.py','shape_metrics.py','measurement_audit.py','plot_comparison.py','summarize_batch.py','run_batch.py','run_migrations.py','run_endurance.py','endurance_summary.py','bridge.py','source-comparison-bundle.json']:
 text=(P/name).read_text(encoding='utf8').replace('microstructure-20261022','diversity-20261022').replace('8835','8836')
 if name=='LocalLab.luau':text=text.replace("{'BotReversion','BotReversionTests'}","{'BotReversion','BotReversionTests','BotDiversity','BotDiversityTests'}")
 if name=='run_batch.py':text=text.replace("'variants/reserve-delay'","'variants/stretch'")
 (R/name).write_text(text,encoding='utf8')
for name in ['logs','variants','diagnostics','migrations','suites','no-recovery-baseline']:(R/name).mkdir(exist_ok=True)
shutil.copytree(P/'development-baseline',R/'development-baseline')
plan=json.loads((P/'experiment.json').read_text());plan['PriorInvestigation']='../microstructure-20261022/RESULTS.md'
plan['Candidates']=['stretch','portfolio','mixed','mixed-wide'];plan['Rounds']=['round1-plan.json']
plan['Selection']='Continue unchanged development gates. Separate validation seeds/worlds remain ungenerated until a single frozen candidate passes development and chart review. Do not reuse validation after a failure.'
(R/'experiment.json').write_text(json.dumps(plan,indent=2))
print('New continuation workspace with unchanged original sources, six development snapshots and gates')
