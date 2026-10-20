local fs=require('@lune/fs');local luau=require('@lune/luau')
local count=0
for _,name in ipairs(fs.readDir('src'))do
 if name:sub(-5)=='.luau'then luau.compile(fs.readFile('src/'..name));count+=1 end
end
luau.compile(fs.readFile('output/bot-fairness-20261019/InstallBotFairness.luau'))
print('Compiled',count,'source files and guarded installer')
