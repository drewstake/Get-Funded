from pathlib import Path
import json,hashlib
R=Path(__file__).resolve().parent
P=(R/'original/server/Participants.luau').read_text(encoding='utf8')
CP=(R/'original/server/WorldCheckpoint.luau').read_text(encoding='utf8').replace('Version=28,Readable={[28]=true','Version=29,Readable={[29]=true,[28]=true')
delay='e:Cancel(a.Id,held.Id);held=nil;a.Quotes[slot]=nil;a.ReserveReplenishAt[slot]=e.Time+(c.ReplenishSeconds or 0)\n  end'
old='local center=reference-inventory/a.Limit*(5+stress*5)'
delta=P.replace(old,'''-- Inventory is already reflected in the last matched quote. Apply only a
 -- change in the private reservation discount, rather than repeating its level.
 local skew=math.round(inventory/a.Limit*(5+stress*5))
 local prior=a.LastReservationSkew or skew
 local center=reference-(skew-prior)
 a.LastReservationSkew=skew''')
combined=(R/'variants/maker-no-skew/Participants.luau').read_text(encoding='utf8').replace('e:Cancel(a.Id,held.Id);held=nil\n  end',delay)
for name,source in {'inventory-delta':delta,'no-skew-reserve-delay':combined}.items():
 d=R/'variants'/name;d.mkdir(exist_ok=False)
 files={'Participants.luau':source,'WorldCheckpoint.luau':CP}
 for f,s in files.items():(d/f).write_text(s,encoding='utf8')
 (d/'manifest.json').write_text(json.dumps({f:hashlib.sha256(s.encode()).hexdigest()for f,s in files.items()},indent=2))
(R/'round3-plan.json').write_text(json.dumps({'Basis':'Balanced funded-order fixture proves constant-inventory price skew is repeatedly reapplied to endogenous last price (40–160 ticks/40 balanced cycles). No-skew four completed development charts have much smaller waves but weaker movement. Reserve delay alone preserves/increases movement but fails shape gates across all six cases.',
 'Variants':{'inventory-delta':'Apply changes in rounded own inventory reservation discount, rather than repeatedly applying its full level to last. Persist last discount without additional RNG. All other baseline mechanisms remain.',
 'no-skew-reserve-delay':'Factorial interaction: combine independently tested no-skew and existing Reserve refill-delay semantics. Tests whether changed depth availability restores useful movement after removing recurrence.'},
 'Gates':'All original and added gates unchanged; independent holdouts still untouched.'},indent=2))
print('Frozen inventory-delta and no-skew-reserve-delay')
