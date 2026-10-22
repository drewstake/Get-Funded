from pathlib import Path
import shutil,json
R=Path(__file__).resolve().parent
shutil.copytree(R/'candidate',R/'installed-v2-source',dirs_exist_ok=True)
for f in ['applied.json','installation-gates.json','suite-comparison.json','runtime-parity.json']:
 shutil.copy2(R/f,R/('v2-'+f))
d=R/'candidate-v3';shutil.copytree(R/'candidate',d,dirs_exist_ok=True)
c=(d/'MarketConfig.luau').read_text(encoding='utf8').replace('BotMomentum = {Version=2,','BotMomentum = {Version=3,')
(d/'MarketConfig.luau').write_text(c,encoding='utf8')
s=(R/'original/server/BotMomentum.luau').read_text(encoding='utf8')
s=s.replace('s.Threshold=range(s,c.EntryStrength);s.Confirmation=range(s,c.ConfirmationSeconds)', '''s.Threshold=range(s,c.EntryStrength);s.Confirmation=range(s,c.ConfirmationSeconds)
 -- Keep at least one sampled interval between the lookback and confirmation boundary.
 -- Otherwise a short-horizon profile can remain permanently unable to form a signal.
 s.Confirmation=math.min(s.Confirmation,math.max(c.SampleSeconds,s.Horizon-c.SampleSeconds))''')
(d/'BotMomentum.luau').write_text(s,encoding='utf8')
p=d/'MakerLiquidityTests.luau';s=p.read_text(encoding='utf8').replace('re.Config.BotMomentum.Version==2','re.Config.BotMomentum.Version==3');p.write_text(s,encoding='utf8')
p=d/'BotMomentumTests.luau';s=p.read_text(encoding='utf8')
s=s.replace("assert(horizons[1]and horizons[2]and horizons[3]and styles.Trend and styles.Breakout)","""assert(horizons[1]and horizons[2]and horizons[3]and styles.Trend and styles.Breakout)
  for _,agent in ipairs(p.Agents)do local state=agent.Momentum;if state then assert(state.Confirmation+C.BotMomentum.SampleSeconds<=state.Horizon)end end""")
s=s.replace(" return out\nend", """ test('Every short-horizon profile has a usable confirmation window',function()
  for _,seed in ipairs({71,7919,104729,907,65537,675969248})do
   local e=E.new(copy(C),seed);local p=P.new(e)
   for _,a in ipairs(p.Agents)do if a.Kind=='Momentum'then
    local before=p.Random.State;local s=M.Adopt(p,a)
    assert(s.Confirmation>0 and s.Confirmation+C.BotMomentum.SampleSeconds<=s.Horizon)
    assert(before==p.Random.State)
   end end
  end
 end)
 return out
end""")
p.write_text(s,encoding='utf8')
(R/'profile-fix.json').write_text(json.dumps({'Issue':'A fast profile can have Confirmation >= Horizon and never signal','Fix':'Clamp confirmation to at most Horizon minus one sample interval','Policy':3,'Checkpoint':28,'RetestCases':['Seed71','Seed7919','Seed104729','Current','Older','Aged','Seed907','Seed65537','CurrentLater','OlderLater'],'Retuning':False},indent=2))
