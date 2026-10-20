local fs=require('@lune/fs')
local luau=require('@lune/luau')
luau.compile(fs.readFile('output/bots-refresh-20261015/InstallBotsRefresh.luau'))
print('Edit-only bot refresh installer compiles')
