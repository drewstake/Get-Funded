-- Read the native Studio export and compare every tracked source without executing it.
local fs=require('@lune/fs')
local serde=require('@lune/serde')
local roblox=require('@lune/roblox')
local luau=require('@lune/luau')
local path='output/single-account-20261001/Get Funded - Single Account.rbxl'
local game=roblox.deserializePlace(fs.readFile(path))
local manifest=serde.decode('json',fs.readFile('output/single-account-20261001/source-manifest.json'))
local report={Path=path,Sources={},RemovedTestsAbsent=true,TemporaryFixturesAbsent=true}
local sourceFiles={}
local pathManifest=serde.decode('json',fs.readFile('build/place-manifest.json'))
for _,row in ipairs(pathManifest.scripts)do sourceFiles[row.file:match('[^/]+$')]=row.file end
for _,item in ipairs(manifest) do
 local parent=game
 for part in item.Parent:gmatch('[^.]+') do parent=assert(parent:FindFirstChild(part),part) end
 local instance=assert(parent:FindFirstChild(item.Name),item.Name)
 local expected=fs.readFile(assert(sourceFiles[item.File],item.File)):gsub('\r\n','\n')
 assert(instance.Source:gsub('\r\n','\n')==expected,'Saved source mismatch: '..item.File)
 luau.compile(instance.Source)
 table.insert(report.Sources,item.File)
end
for _,v in ipairs(game:GetDescendants()) do
 assert(v.Name~='SingleAccountQA' and v.Name~='PreviewSharedBuild' and v.Name~='PreviewEngineBuild','Temporary fixture saved')
end
for _,name in ipairs({'FundedTests','DepletionTests','ProgressionTests','ReearnTests','PermanentShopTests','StatsTests','LeaderboardTests'}) do
 assert(not game.ServerScriptService.MarketReign:FindFirstChild(name),'Retired test saved')
end
assert(game.StarterGui.MarketReign:FindFirstChild('Workspace'),'Saved preview missing')
report.Instances=#game:GetDescendants()
fs.writeFile('output/single-account-20261001/place-verification.json',serde.encode('json',report,true))
print('Native saved place verified: '..#report.Sources..' matching compiled sources; '..report.Instances..' instances')
