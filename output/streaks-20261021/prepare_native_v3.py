from pathlib import Path
import shutil
R=Path(__file__).resolve().parent
shutil.copy2(R/'parity-local-Candidate-Seed71.json',R/'snapshots/normalized-InstalledV2.json')
shutil.copy2(R/'parity-local-Candidate-Seed71.json',R/'v2-parity-local.json')
for p in R.glob('native-parity-*.part'):shutil.copy2(p,R/('v2-'+p.name))
s=(R/'NativeVerify.luau').read_text(encoding='utf8').replace('candidate/','candidate-v3/').replace("{'Participants','WorldCheckpoint'","{'BotMomentum','BotMomentumTests','Participants','WorldCheckpoint'")
(R/'NativeVerifyV3.luau').write_text(s,encoding='utf8')
