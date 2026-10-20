local fs=require('@lune/fs');local luau=require('@lune/luau');local count=0
for _,name in ipairs(fs.readDir('src'))do if name:sub(-5)=='.luau'then luau.compile(fs.readFile('src/'..name));count+=1 end end
luau.compile(fs.readFile('tools/order-driven-market/ValidateStudio.luau'))
print('Compiled',count,'sources and detached validator')
