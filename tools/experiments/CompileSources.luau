local fs=require('@lune/fs')
local serde=require('@lune/serde')
local luau=require('@lune/luau')
local manifest=serde.decode('json',fs.readFile('build/place-manifest.json'))
local failed=0
assert(#manifest.scripts>0,'No sources discovered')
for _,item in ipairs(manifest.scripts)do
 local ok,err=pcall(luau.compile,fs.readFile(item.file))
 if not ok then failed+=1;print(item.file..': '..tostring(err))end
end
assert(failed==0,tostring(failed)..' sources failed compilation')
print('All '..#manifest.scripts..' sources compile')
