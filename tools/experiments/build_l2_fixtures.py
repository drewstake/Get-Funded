from pathlib import Path
import json
r = Path(__file__).resolve().parents[2]
client=(r/'src/shared/MarketClient.luau').read_text(encoding='utf-8').replace('return Market\n',(r/'tools/experiments/Level2FixtureClient.txt').read_text(encoding='utf-8')+'\nreturn Market\n')
ui=(r/'src/shared/TerminalUI.luau').read_text(encoding='utf-8').replace('require(script.Parent.MarketClient)','require(script.Parent.Level2FixtureClient)').replace('b.Activated:Connect(function(...)','local hook=Instance.new("BindableFunction");hook.Name="TestActivate";hook.OnInvoke=fn;hook.Parent=b;b.Activated:Connect(function(...)').replace('local controller={Root=root,State=s,Chart=chartView}','local controller={Root=root,State=s,Chart=chartView};function controller:TestRender()render()end;function controller:TestDepth()updateLevel2()end')
print(json.dumps([
 ['game.ReplicatedStorage.MarketReign.Level2FixtureClient','ModuleScript',client],
 ['game.ReplicatedStorage.MarketReign.Level2FixtureUI','ModuleScript',ui],
 ['game.ServerScriptService.MarketReign.Level2Validation','Script',(r/'tools/studio/ValidateLevel2.server.luau').read_text(encoding='utf-8')],
 ['game.StarterPlayer.StarterPlayerScripts.Level2Validation','LocalScript',(r/'tools/studio/ValidateLevel2.client.luau').read_text(encoding='utf-8')],
]))
