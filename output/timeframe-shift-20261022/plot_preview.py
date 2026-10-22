from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent
sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
d=json.loads((R/'history-fixtures.json').read_text())['CurrentBX']
choices=[('Previous 1m','1m',60),('New 1m · existing 5m candles','5m',300)]
fig,axes=plt.subplots(2,1,figsize=(13,7.5),facecolor='#071b39');limits=[]
for ax,(label,key,seconds)in zip(axes,choices):
 ax.set_facecolor('#071b39');bars=[b for b in d['CandlesBySeries']['BX:'+key]if b['Time']+seconds<=d['Time']][-60:]
 for i,b in enumerate(bars):
  c='#27e8b8'if b['Close']>=b['Open']else'#ff4e80';ax.vlines(i,b['Low'],b['High'],color=c,linewidth=.8)
  height=abs(b['Close']-b['Open']);low=min(b['Close'],b['Open'])
  if height:ax.add_patch(Rectangle((i-.32,low),.64,height,facecolor=c,edgecolor=c,linewidth=.4))
  else:ax.hlines(low,i-.32,i+.32,color=c,linewidth=.7)
  limits.extend([b['Low'],b['High']])
 ax.set_title(label+' · 60 completed candles',color='white',loc='left',fontsize=14)
 ax.tick_params(colors='#afc2dd');ax.grid(color='#263d60',alpha=.5);ax.set_xlim(-1,60);ax.set_ylabel('BX price',color='#afc2dd')
 for spine in ax.spines.values():spine.set_color('#263d60')
pad=(max(limits)-min(limits))*.05
for ax in axes:ax.set_ylim(min(limits)-pad,max(limits)+pad);ax.set_xlabel('Candle index',color='#afc2dd')
fig.suptitle('Timeframe shift preview · captured BX history\nOriginal OHLC preserved · common price scale · different time spans',color='white',fontsize=16)
fig.tight_layout(rect=[0,0,1,.91]);fig.savefig(R/'timeframe-preview.png',dpi=140,facecolor=fig.get_facecolor())
print('Rendered original candles without changing market data')
