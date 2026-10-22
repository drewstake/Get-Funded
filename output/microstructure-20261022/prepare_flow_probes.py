"""Round 2: independently test existing opposing-flow timing, before any combinations."""
from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
P=(R/'original/server/Participants.luau').read_text(encoding='utf8')
M=(R/'original/server/BotMomentum.luau').read_text(encoding='utf8')
CP=(R/'original/server/WorldCheckpoint.luau').read_text(encoding='utf8').replace('Version=28,Readable={[28]=true','Version=29,Readable={[29]=true,[28]=true')
# Keep random draw and child cap machinery; only voluntary time-exit slice size changes.
needle="if reducing then size=math.min(size,pos.Quantity);cancelEntries(e,a)"
assert M.count(needle)==1
fast=M.replace(needle,"if reducing and s.ExitReason=='Time'then size=math.min(math.abs(delta),a.Size)end\n "+needle)
# A valuation edge is necessary for new Value risk, but inventory reductions can be valid
# even when belief converged back into the spread. The original signal decides direction.
guard="if math.abs(a.Belief-last)<(ask-bid)/2+a.EntryBuffer then return end"
assert P.count(guard)==1
value=P.replace(guard,"if not p and math.abs(a.Belief-last)<(ask-bid)/2+a.EntryBuffer then return end")
needle='local reducing=false\n if signals and a.Kind=="Reversion"then'
value=value.replace(needle,'''local reducing=false
 if a.Kind=='Value'and a.PolicyVersion then
  if p and side==-p.Direction then size=math.min(size,p.Quantity);reducing=true
  elseif math.abs(a.Belief-last)<(quote.Ask-quote.Bid)/2+a.EntryBuffer then return end
 end
 if signals and a.Kind=="Reversion"then''')
assert value!=P
# Reserve inventory previously only moved all quotes by <=4 ticks. A funded closing
# quote can retain its cost-based limit instead of fleeing the market after each print.
# Only the nearest reducing slot changes. Existing inventory/size limits and passive guard remain.
needle='local tick=math.max(1,fair-skew-side*math.ceil(offset*scale))'
assert P.count(needle)==1
cost=P.replace(needle,needle+'''
  if depth==1 and position and side==-position.Direction then
   local exit=math.round(position.Entry/b.Spec.Tick)+position.Direction*math.ceil(offset*scale)
   tick=side==1 and math.max(tick,exit)or math.min(tick,exit)
   local opposite=side==1 and b.Asks[1]or b.Bids[1]
   if opposite then tick=side==1 and math.min(tick,opposite.Price-1)or math.max(tick,opposite.Price+1)end
  end''')
variants={'time-exit-size':{'BotMomentum.luau':fast},'value-exit-gate':{'Participants.luau':value},'reserve-cost-quote':{'Participants.luau':cost}}
for name,files in variants.items():
 d=R/'variants'/name;d.mkdir(exist_ok=True);files['WorldCheckpoint.luau']=CP
 for f,s in files.items():(d/f).write_text(s,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
plan={'Basis':'Current BX has 2,591 Momentum time-exit contracts but little meaningful retracement; Value closes 1,234 contracts through stops versus 646 ordinary exits; Reserve has 74,884 same-decision replacements in 74,946 total and only 543 filled contracts.',
 'Variants':{'time-exit-size':'Concentrate existing time-exit flow into full normal child sizes, retaining the same decision cadence, hold deadlines, slippage, funding and risk exits.',
 'value-exit-gate':'Allow original Value signal to reduce inventory without a new-entry valuation-edge hurdle. New risk still needs the old edge. No profit target or new memory horizon.',
 'reserve-cost-quote':'Nearest closing-side Reserve quote retains a cost-based limit at entry plus existing depth offset, instead of always following prints. Passive guard and original size remain.'},
 'Selection':'Same fixed development gates. No independent-validation cases inspected. These are isolated probes; no effect attributed to a combination.'}
(R/'round2-plan.json').write_text(json.dumps(plan,indent=2))
print('Frozen',list(variants))
