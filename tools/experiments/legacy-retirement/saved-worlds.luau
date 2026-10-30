local fs=require('@lune/fs');local serde=require('@lune/serde');local H=require('./environment').game:GetService('HttpService')
local CP=require('./candidate/WorldCheckpoint');local Tests=require('./candidate/LegacyRetirementTests')
for _,scope in ipairs({'live','studio'})do
 local saved=H:JSONDecode(fs.readFile('backups/legacy-retirement-20261018/private-'..scope..'-checkpoint.json'))
 local result=Tests.Captured(CP.Decode(saved.Record.Checkpoint),240)
 fs.writeFile('output/legacy-retirement-20261018/'..scope..'-migration.json',serde.encode('json',result,true))
 print(scope,result)
end
