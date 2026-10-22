from pathlib import Path
R=Path(__file__).resolve().parent
s=(R/'original/server/BotMomentumTests.luau').read_text(encoding='utf8')
extra='''
 test('Episode gate blocks repeated same-direction entry, without blocking an opposite signal',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,s=fixture();history(e,p,b,side)
   s.EntryEpisodeSide=side;s.EntryEpisodeExtreme=b.Last;local trades=e.NextTrade
   M.Step(p,a);assert(s.Phase=='Waiting'and e.NextTrade==trades and not e.Accounts[a.Id].Positions.BX)
   s.EntryEpisodeSide=-side;s.NextReview=0;M.Step(p,a)
   assert(s.Phase=='Building'and e.Accounts[a.Id].Positions.BX.Direction==side);e:Audit()
  end
 end)
 test('Episode gate ignores tiny flickers and rearms on a substantial private retracement',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,s=fixture();history(e,p,b,side)
   s.EntryEpisodeSide=side;s.EntryEpisodeExtreme=b.Last+side
   M.Step(p,a);assert(s.Phase=='Waiting')
   s.EntryEpisodeExtreme=b.Last+side*(math.max(6,a.Stop*.35)+1);s.NextReview=0
   M.Step(p,a);assert(s.Phase=='Building');e:Audit()
  end
 end)
 test('Episode eligibility never postpones an ordinary time exit',function()
  for _,side in ipairs({1,-1})do
   local e,p,a,b,s=fixture();history(e,p,b,side);M.Step(p,a)
   assert(e.Accounts[a.Id].Positions.BX);s.EntryEpisodeSide=side;s.EntryEpisodeExtreme=b.Last
   s.OpenedAt=e.Time-s.HoldSeconds;p.Markets.BX.MomentumHistory={}
   M.Step(p,a);assert(not e.Accounts[a.Id].Positions.BX and s.Phase=='Waiting');e:Audit()
  end
 end)
'''
for name in ['episode','combined']:
 (R/'variants'/name/'BotMomentumTests.luau').write_text(s.replace(' return out\nend',extra+' return out\nend'),encoding='utf8')
print('Added symmetric entry, retracement and exit tests; production source hashes unchanged')
