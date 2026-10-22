"""One named case only; this plot never summarizes incomplete multi-case comparisons."""
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from metrics import meaningful
names=sys.argv[1:]or['inner-patient-stretch','inner-patient-quote-safe','rolling-portfolio-depth','rolling-cost-aware','rolling-touch-participation']
base=json.loads((R/'development-baseline/CurrentBX-Baseline.json').read_text())
paths=[('Installed baseline',base)]+[(n,json.loads((R/('development-'+n)/'CurrentBX-Candidate.json').read_text()))for n in names]
fig,axes=plt.subplots(len(paths),1,figsize=(14,2.6*len(paths)),facecolor='#071b39',squeeze=False)
limits=[]
for ax,(name,data)in zip(axes[:,0],paths):
 ax.set_facecolor('#071b39');bars=data['Markets']['BX']['Bars'];first=bars[0]['Open'];norm=lambda x:100*(x/first-1)
 for i,b in enumerate(bars):
  color='#27e8b8'if b['Close']>=b['Open']else'#ff4e80'
  ax.vlines(i,norm(b['Low']),norm(b['High']),color=color,linewidth=.8)
  low=norm(min(b['Open'],b['Close']));height=abs(norm(b['Close'])-norm(b['Open']))
  if height:ax.add_patch(Rectangle((i-.32,low),.64,height,facecolor=color,edgecolor=color,linewidth=.4))
  else:ax.hlines(low,i-.32,i+.32,color=color,linewidth=.7)
  limits.extend([norm(b['Low']),norm(b['High'])])
 m=meaningful(bars,.25)
 ax.set_title(f"{name} | longest meaningful leg {m['MeaningfulMaxLeg']}m | strict completed pullbacks {m['MeaningfulPullbacks']}",loc='left',color='white',fontsize=11)
 ax.tick_params(colors='#afc2dd');ax.set_ylabel('Change (%)',color='#afc2dd');ax.grid(color='#263d60',alpha=.45);ax.set_xlim(-1,60)
 for spine in ax.spines.values():spine.set_color('#263d60')
pad=(max(limits)-min(limits))*.07
for ax in axes[:,0]:ax.set_ylim(min(limits)-pad,max(limits)+pad)
axes[-1,0].set_xlabel('Simulated minutes after adaptation',color='#afc2dd')
fig.suptitle('Current saved world · BX · matched one-minute OHLC\nSame vertical scale; each path normalized to its own first open',color='white',fontsize=16)
fig.tight_layout(rect=[0,0,1,.955]);fig.savefig(R/'CurrentBX-candidate-comparison.png',dpi=140,facecolor=fig.get_facecolor());print('Rendered CurrentBX only:',names)
