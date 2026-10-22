from pathlib import Path
import json,sys
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
d=json.loads((R/'diagnostics/CurrentBX-final-diagnose.json').read_text());b=json.loads((R/'development-baseline/CurrentBX-Baseline.json').read_text());bars=b['Markets']['BX']['Bars'];start=b['MeasuredStart'];rows={round((x['Time']-start)/60):x for x in d['Rows']if x['Market']=='BX'}
fig,axes=plt.subplots(4,1,figsize=(16,13),sharex=True,facecolor='#091b30')
for ax in axes:ax.set_facecolor('#091b30');ax.tick_params(colors='#bbcce0');ax.grid(alpha=.15);ax.axhline(0,color='#56718a',lw=.5)
for i,v in enumerate(bars):
 color='#27e8b8'if v['Close']>=v['Open']else '#ff4e80';price=lambda x:100*(x/bars[0]['Open']-1)
 axes[0].vlines(i,price(v['Low']),price(v['High']),color=color,lw=.8);h=abs(price(v['Close'])-price(v['Open']));lo=price(min(v['Open'],v['Close']))
 if h:axes[0].add_patch(Rectangle((i-.32,lo),.64,h,color=color))
 else:axes[0].hlines(lo,i-.32,i+.32,color=color)
axes[0].set_title('Current saved BX world: actual 60-minute baseline replay and its order flow',color='white',loc='left');axes[0].set_ylabel('Price change (%)',color='white')
for label,color,check in [('Momentum builds','#27e8b8',lambda s,f:s.startswith('Momentum/')and f['OpenContracts']>0),('Momentum exits','#ffce66',lambda s,f:s.startswith('Momentum/')and f['CloseContracts']>0),('Value','#b68cff',lambda s,f:s.startswith('Value/'))]:
 vals=[sum(f['Buy']-f['Sell']for s,f in rows.get(i,{}).get('Flows',{}).items()if check(s,f))for i in range(60)]
 axes[1].plot(range(60),vals,label=label,color=color,lw=1.3)
axes[1].set_ylabel('Aggressor net contracts',color='white')
for kind,color in [('Momentum','#27e8b8'),('Maker','#ffce66'),('Value','#b68cff'),('Reserve','#ff4e80')]:
 axes[2].plot(range(60),[rows.get(i,{}).get('Inventory',{}).get(kind,float('nan'))for i in range(60)],label=kind,color=color,lw=1.3)
axes[2].set_ylabel('Net inventory at minute start',color='white')
for kind,color in [('Maker','#ffce66'),('Reserve','#ff4e80')]:
 vals=[]
 for i in range(60):
  q=rows.get(i,{}).get('Quotes',{}).get(kind,{});vals.append(q.get('SlotPriceChange',0)/max(1,q.get('SlotReplacements',0)))
 axes[3].plot(range(60),vals,label=kind,color=color,lw=1.3)
axes[3].set_ylabel('Mean replacement shift (ticks)',color='white');axes[3].set_xlabel('Minutes after adaptation',color='white');axes[3].set_xlim(-1,60)
for ax in axes[1:]:ax.legend(facecolor='#091b30',labelcolor='white',loc='upper right',ncol=4,fontsize=9)
fig.tight_layout();fig.savefig(R/'CurrentBX-order-flow.png',dpi=140);plt.close(fig)
print('Rendered current BX matched candles, taker flow, inventory and same-slot replacements')
