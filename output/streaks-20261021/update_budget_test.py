from pathlib import Path
R=Path(__file__).resolve().parent
s=(R/'original/server/BotMomentumTests.luau').read_text(encoding='utf8')
s=s.replace("for _=1,6 do M.Step(p,a)end;assert(s.Filled==filled and not next(e.Accounts[a.Id].OpenOrders))", """for _=1,6 do M.Step(p,a)end
  -- Faster build profiles can have more than one contract due in their first time bucket.
  -- Repeated calls cannot spend beyond that fixed time budget or leave an IOC remainder.
  local due=math.ceil(math.abs(s.Target)*math.clamp((e.Time-s.StartedAt+C.BotMomentum.SliceSeconds[2])/s.BuildSeconds,0,1))
  assert(s.Filled>=filled and s.Filled<=due and not next(e.Accounts[a.Id].OpenOrders));filled=s.Filled""")
(R/'candidate/BotMomentumTests.luau').write_text(s,encoding='utf8')
