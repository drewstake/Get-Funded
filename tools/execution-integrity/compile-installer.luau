local fs=require('@lune/fs')
local luau=require('@lune/luau')
luau.compile(fs.readFile('output/execution-integrity-20261015/InstallValidatedExecution.luau'))
print('Edit-only installer compiles')
