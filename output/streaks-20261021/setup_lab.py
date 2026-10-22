from pathlib import Path
import shutil
R=Path(__file__).resolve().parent
OLD=R.parent/'reversion-20261021'
for d in ['original','snapshots']:
    shutil.copytree(OLD/d,R/d,dirs_exist_ok=True)
for f in ['ExactJson.luau','LocalLab.luau','MomentumBenchmark.luau','analyze.py','plot_comparison.py']:
    text=(OLD/f).read_text(encoding='utf8').replace('output/reversion-20261021/','output/streaks-20261021/')
    (R/f).write_text(text,encoding='utf8')
for d in ['candidate','results','logs','suites','diagnostics','variants','endurance','no-recycling']:(R/d).mkdir(exist_ok=True)
text=(R/'LocalLab.luau').read_text()
text=text.replace("if mode=='tests'then", "if mode=='diagnose'then\n local D=load(root,'Diagnose.luau');local result=D.Run(root,snapshot(name));fs.writeFile(base..'diagnostics/'..name..'.json',Http:JSONEncode(result));print('diagnosed',name)\nelseif mode=='tests'then")
(R/'LocalLab.luau').write_text(text)
bridge=Path('tools/reversion_lab_bridge.py').read_text().replace('reversion-20261021','streaks-20261021').replace('8820','8821')
Path('tools/streaks_lab_bridge.py').write_text(bridge)
