from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'output/legacy-retirement-20261018'
def read(name):return json.loads((OUT/name).read_text())
offline=read('tests.json');native=read('studio-tests.json');status=read('studio-validation-status.json')
first=read('first-stop.json');restart=read('restart-observation.json');final=read('final-stop.json');source=read('source-audit.json')
assert offline['Failures']==native['Failures']==0 and status['Success']
assert first['LeaseUntil']==final['LeaseUntil']==0
assert restart['SessionStartStep']==first['Step']
assert final['Participants']==final['FundingEligible']==390 and final['ArchivedBots']==264
assert final['ArchiveUnchanged'] and final['CapitalPreserved'] and not final['GameErrors']
assert source['VerifiedModules']==11 and source['EditMode'] and not source['TemporaryObjects']
summary={
    'Result':'Installed and validated in Studio; publication and public-server restart still required.',
    'OfflineTests':offline['Total'],'NativeTests':native['Total'],'Failures':0,
    'LiveBackupMigration':read('studio-live-migration.json'),
    'StudioBackupMigration':read('studio-studio-migration.json'),
    'Benchmark':read('benchmark.json'),
    'Playtest':{'InitialStep':final['InitialStep'],'FirstStopStep':first['Step'],
                'RestartStep':restart['SessionStartStep'],'FinalStep':final['Step'],
                'SimulatedMinutes':(final['Step']-final['InitialStep'])*.25/60,
                'Final':final},
    'Sources':source,'Published':False,'LiveDataStoreWritten':False,
    'LocalRbxlSaved':False,'StudioDataStoreSaved':True,
}
(OUT/'summary.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({k:summary[k] for k in ('Result','OfflineTests','NativeTests','Failures')}))
print('Final saved step:',final['Step'],'Simulated minutes:',summary['Playtest']['SimulatedMinutes'])
