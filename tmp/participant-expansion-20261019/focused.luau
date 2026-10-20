local failed=0
for _,name in ipairs({'BotExitRetryTests','ExecutionIntegrityTests','SharedDepthTests','ParticipantExpansionTests'})do
 for _,r in ipairs(require('./candidate/'..name).Run())do if not r.Passed then failed+=1;print(name,r.Name,r.Detail)end end
 print('Completed',name)
end
assert(failed==0)
