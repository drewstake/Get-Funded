from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
P=(R/'original/server/Participants.luau').read_text(encoding='utf8')
M=(R/'original/server/BotMomentum.luau').read_text(encoding='utf8')
CP=(R/'original/server/WorldCheckpoint.luau').read_text(encoding='utf8')
# Preserve Momentum v2 profiles exactly: no profile migration or correction bundled in.
# Entry eligibility rearms only on a privately observed retracement since the previous entry.
M=M.replace("if quantity>0 then\n    s.Phase='Building'", "if quantity>0 and not (s.EntryEpisodeSide==signal.Side) then\n    s.EntryEpisodeSide=signal.Side;s.EntryEpisodeExtreme=signal.Last\n    s.Phase='Building'")
needle="local signal=M.Signal(p,a,s)"
M=M.replace(needle,needle+"""
  if s.EntryEpisodeSide then
   local last=b.Last or b.Reference
   s.EntryEpisodeExtreme=s.EntryEpisodeSide==1 and math.max(s.EntryEpisodeExtreme,last)or math.min(s.EntryEpisodeExtreme,last)
   -- A fresh opportunity requires a real pullback, not cooldown expiry in the same impulse.
   local reset=math.max(6,a.Stop*.35)
   if (s.EntryEpisodeExtreme-last)*s.EntryEpisodeSide>=reset then s.EntryEpisodeSide=nil;s.EntryEpisodeExtreme=nil end
  end""")
assert 's.EntryEpisodeSide=signal.Side' in M
# Slower Value memories retain trader-specific profile ratios, timing and observation noise.
# Orders, inventory feedback, all risk allowances and ordinary exits remain the existing ones.
V=P.replace('elapsed/a.BeliefHalfLife','elapsed/(a.BeliefHalfLife*10)')
assert V!=P
for name,files in {'episode':{'BotMomentum.luau':M},'value-memory':{'Participants.luau':V},'combined':{'BotMomentum.luau':M,'Participants.luau':V}}.items():
 d=R/'variants'/name;d.mkdir(parents=True,exist_ok=True)
 # Version lab snapshots so an experimental checkpoint cannot be read by installed code.
 files['WorldCheckpoint.luau']=CP.replace('Version=28,Readable={[28]=true','Version=29,Readable={[29]=true,[28]=true')
 for file,source in files.items():(d/file).write_text(source,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan={'Baseline':'105 Studio modules identical to installed CP28/Momentum2/Maker8/Whale1; news off',
 'Development':['Seed71','Seed7919','Seed104729','CurrentBX','Older','Aged'],
 'Validation':['Seed42017','Seed88069','CurrentBXLater','AgedLater'],
 'Candidates':['episode','value-memory','combined'],
 'Selection':'Three frozen targeted arms, no retuning. Promote only a development pass; frozen separate validation cannot be extended to rescue a failure.',
 'Gates':{'MeaningfulLong8Ratio':.8,'MeaningfulMaxLegRatio':.85,'Directional10Ratio':.8,'MeaningfulCounterRatio':1.3,'CaseShapeWins':4,'OneMinuteRVRatio':.9,'MeanMinuteRangeRatio':.9,'Midpoint15RVRatio':.9,'RecoveryMaximumRatio':1.1,'Alternating4Maximum':.08,'NoQuoteMaximum':.001,'SpreadP95MaximumRatio':1.5},
 'CurrentBX':'Long-leg occupancy must fall, maximum leg must not rise, meaningful counter count must rise.',
 'MeaningfulCounter':'Close retracement >= max(6 ticks, 0.025% of extreme price, 20% of preceding leg). Dojis and smaller flickers never reset.',
 'Target':'30-minute range 0.7-1.5% soft; report coverage and declines, never optimize candle colors',
 'Safety':'Matching/accounting/margin/stops/funding unchanged; exact replay each run. Before any installation: native suite/parity, no-recovery endurance, explicit version migration tests.'}
(R/'experiment.json').write_text(json.dumps(plan,indent=2))
print('Three source-frozen lab-only candidates prepared')
