from pathlib import Path
import shutil,json
R=Path(__file__).resolve().parent
for directory in ['candidate-v3','development-v3','holdout-v3','details-v3','no-recycling-v3','transition-v3']:
 shutil.copytree(R/directory,R/(directory+'-broad-rejected'),dirs_exist_ok=True)
for f in ['installation-gates-v3.json','candidate-manifest-v3.json','suite-comparison.json','runtime-parity.json']:
 shutil.copy2(R/f,R/('broad-rejected-'+f))
p=R/'candidate-v3/BotMomentum.luau';s=p.read_text(encoding='utf8')
s=s.replace('''-- Keep at least one sampled interval between the lookback and confirmation boundary.
 -- Otherwise a short-horizon profile can remain permanently unable to form a signal.
 s.Confirmation=math.min(s.Confirmation,math.max(c.SampleSeconds,s.Horizon-c.SampleSeconds))''','''-- Correct only impossible profiles; preserve every already-valid confirmation window.
 -- A confirmation at/behind the lookback boundary can never form a signal.
 if s.Confirmation>=s.Horizon then s.Confirmation=math.max(c.SampleSeconds,s.Horizon-c.SampleSeconds)end''')
p.write_text(s,encoding='utf8')
p=R/'candidate-v3/BotMomentumTests.luau';s=p.read_text(encoding='utf8').replace('state.Confirmation+C.BotMomentum.SampleSeconds<=state.Horizon','state.Confirmation<state.Horizon').replace('s.Confirmation+C.BotMomentum.SampleSeconds<=s.Horizon','s.Confirmation<s.Horizon')
s=s.replace(' return out\nend', ''' test('The confirmation correction preserves every already-valid narrow window',function()
  for _,case in ipairs({{21,20,20},{20,25,15}})do
   local c=copy(C);c.BotMomentum.Horizons={{case[1],case[1]}};c.BotMomentum.ConfirmationSeconds={case[2],case[2]}
   local e=E.new(c,71);local p=P.new(e)
   for _,a in ipairs(p.Agents)do if a.Kind=='Momentum'then local s=M.Adopt(p,a);assert(s.Confirmation==case[3])end end
  end
 end)
 return out
end''')
p.write_text(s,encoding='utf8')
fix=json.loads((R/'profile-fix.json').read_text());fix['Fix']='Only if Confirmation >= Horizon, set Confirmation to Horizon minus one sample interval. Preserve every valid profile exactly.';fix['BroadCorrectionRejected']=True
(R/'profile-fix.json').write_text(json.dumps(fix,indent=2))
