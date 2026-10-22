local fs=require('@lune/fs');local luau=require('@lune/luau');local serde=require('@lune/serde')
local base='output/timeframe-shift-20261022/';local out={Compiled={}}
for _,file in ipairs(fs.readDir(base..'candidate'))do
 if file:sub(-5)=='.luau'then luau.compile(fs.readFile(base..'candidate/'..file));table.insert(out.Compiled,file)end
end
table.sort(out.Compiled);assert(#out.Compiled==4)
fs.writeFile(base..'compile-result.json',serde.encode('json',out));print('Compiled four frozen client modules')
