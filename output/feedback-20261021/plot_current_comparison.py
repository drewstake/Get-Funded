from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from metrics import meaningful
cases=[('Installed baseline','baseline','Baseline'),('Momentum re-entry gate','episode','Candidate'),('Longer Value memory','value-memory','Candidate'),('Combined','combined','Candidate')]
fig,axes=plt.subplots(2,2,figsize=(14,8),sharey=True,facecolor='#091b30');limits=[]
for ax,(label,folder,arm)in zip(axes.flat,cases):
 d=json.loads((R/f'development-{folder}'/f'CurrentBX-{arm}.json').read_text());bars=d['Markets']['BX']['Bars'];x=meaningful(bars,.25)
 ax.set_facecolor('#091b30');price=lambda v:100*(v/bars[0]['Open']-1)
 for i,b in enumerate(bars):
  col='#27e8b8'if b['Close']>=b['Open']else '#ff4e80';ax.vlines(i,price(b['Low']),price(b['High']),color=col,lw=.8)
  lo=price(min(b['Open'],b['Close']));hi=abs(price(b['Close'])-price(b['Open']))
  if hi:ax.add_patch(Rectangle((i-.32,lo),.64,hi,color=col))
  else:ax.hlines(lo,i-.32,i+.32,color=col)
  limits.extend([price(b['Low']),price(b['High'])])
 ax.set_title(f'{label}\nLongest meaningful leg: {x["MeaningfulMaxLeg"]}m; counter-moves: {x["MeaningfulCounters"]}',color='white',loc='left',fontsize=11)
 ax.tick_params(colors='#bbcce0');ax.grid(alpha=.15);ax.axhline(0,color='#56718a',lw=.5);ax.set_xlim(-1,60);ax.set_xlabel('Simulated minutes',color='white');ax.set_ylabel('Change from first open (%)',color='white')
for ax in axes.flat:ax.set_ylim(min(limits)-.05,max(limits)+.05)
fig.suptitle('Current saved BX — same checkpoint, 20-minute adaptation, then 60 actual one-minute candles\nAll panels share one vertical scale. None of these candidates passed.',color='white',fontsize=14)
fig.tight_layout(rect=[0,0,1,.92]);fig.savefig(R/'CurrentBX-four-arms.png',dpi=140);plt.close(fig)
