local t=require('./candidate/ParticipantExpansionTests').Run()
for _,r in ipairs(t)do print(r.Name,r.Passed,r.Detail)end
