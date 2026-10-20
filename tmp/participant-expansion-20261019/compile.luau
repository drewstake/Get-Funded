local fs=require('@lune/fs');local luau=require('@lune/luau');local n=0
for _,name in ipairs(fs.readDir('src'))do if name:sub(-5)=='.luau'then luau.compile(fs.readFile('src/'..name));n+=1 end end
print('Compiled',n,'Luau files')
