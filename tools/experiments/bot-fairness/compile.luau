local fs=require('@lune/fs');local luau=require('@lune/luau')
local count=0
local manifest=require('@lune/serde').decode('json',fs.readFile('build/place-manifest.json'))
for _,row in ipairs(manifest.scripts)do luau.compile(fs.readFile(row.file));count+=1 end
assert(count>0,'No sources discovered')
luau.compile(fs.readFile('output/bot-fairness-20261019/InstallBotFairness.luau'))
print('Compiled',count,'source files and guarded installer')
