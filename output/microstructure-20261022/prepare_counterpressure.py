from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
W=(R/'original/server/BotWhale.luau').read_text(encoding='utf8')
needle="random(s)<c.AggressiveProbability[1]+urgency*(c.AggressiveProbability[2]-c.AggressiveProbability[1])"
assert W.count(needle)==1
# Reuse the earlier urgency probe's fixed probability range; no profile/cycle reset.
# The reason to revisit is the independently demonstrated Maker skew recurrence.
W=W.replace(needle,'random(s)<.30+urgency*(.65-.30)')
CP=(R/'variants/maker-no-skew/WorldCheckpoint.luau').read_text(encoding='utf8')
P=(R/'variants/no-skew-sparse-touch/Participants.luau').read_text(encoding='utf8')
C=(R/'variants/no-skew-sparse-touch/MarketConfig.luau').read_text(encoding='utf8')
M=(R/'variants/time-exit-size/BotMomentum.luau').read_text(encoding='utf8')
variants={'whale-urgency':{'BotWhale.luau':W},
 'no-skew-sparse-whale':{'BotWhale.luau':W,'Participants.luau':P,'MarketConfig.luau':C},
 'no-skew-sparse-time':{'BotMomentum.luau':M,'Participants.luau':P,'MarketConfig.luau':C}}
for name,files in variants.items():
 d=R/'variants'/name;d.mkdir(exist_ok=False);files['WorldCheckpoint.luau']=CP
 for f,s in files.items():(d/f).write_text(s,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
(R/'round5-plan.json').write_text(json.dumps({'Basis':'Sparse touch alone retains range/volatility and improves max leg but fails occupancy. No-skew+sparse retains minute and midpoint movement and improves counters but still has long legs and insufficient range. Existing time exits and independent Whale mandates may have different impact after the inventory repricing recurrence is removed.',
 'Variants':{'whale-urgency':'Isolated existing 0.30–0.65 aggression probability, otherwise identical Whale policy, private RNG stream, mandates, participation budget, sizes and timing. No profile reset.',
 'no-skew-sparse-whale':'Cross the same Whale intervention with the frozen no-skew+sparse book.',
 'no-skew-sparse-time':'Cross the already isolated existing-time-exit concentration with the frozen no-skew+sparse book.'},
 'PriorFailure':'Earlier whale-urgency lengthened streaks with inventory-shifted quoting. This is explicitly a conditional interaction test motivated by the new balanced-flow causal fixture, not an assertion that the failed standalone policy is now good.',
 'Gates':'Unchanged; no unseen validation cases accessed; no new bot, capital, limits, forced reversal, news or price writers.'},indent=2))
print('Frozen',list(variants))
