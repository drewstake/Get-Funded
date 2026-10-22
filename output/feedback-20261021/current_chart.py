from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from metrics import meaningful
from shape_metrics import shape
from analyze import measures
d=json.loads((R/'snapshots/normalized-CurrentBX.json').read_text())
bars=[b for b in d['Engine']['Books']['BX']['Candles']['1m']if b['Time']+60<=d['Engine']['Time']][-180:]
out={'Step':d['Engine']['Step'],'Minutes':len(bars),**meaningful(bars,.25),**shape(bars,.25),**measures(bars,.25)}
(R/'current-chart-metrics.json').write_text(json.dumps(out,indent=2))
fig,axes=plt.subplots(3,1,figsize=(16,10),facecolor='#091b30')
for ax,offset in zip(axes,[0,60,120]):
 ax.set_facecolor('#091b30');xs=bars[offset:offset+60]
 for i,b in enumerate(xs):
  color='#27e8b8'if b['Close']>=b['Open']else '#ff4e80';ax.vlines(i,b['Low'],b['High'],color=color,lw=.8)
  low=min(b['Open'],b['Close']);height=abs(b['Close']-b['Open'])
  if height:ax.add_patch(Rectangle((i-.32,low),.64,height,color=color))
  else:ax.hlines(low,i-.32,i+.32,color=color)
 ax.set_title(f'BX saved world — completed minutes {offset+1}–{offset+len(xs)} (actual matched-order OHLC)',color='white',loc='left')
 ax.tick_params(colors='#bbcce0');ax.grid(alpha=.15);ax.set_xlim(-1,60);ax.set_ylabel('Price',color='white')
fig.tight_layout();fig.savefig(R/'current-BX.png',dpi=140);plt.close(fig)
print(json.dumps({k:out[k]for k in ['Step','MeaningfulLong8','MeaningfulMaxLeg','MeaningfulCounters','LongestRun','Pullbacks']},indent=2))
