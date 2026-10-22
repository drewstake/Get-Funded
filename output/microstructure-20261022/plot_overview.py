from pathlib import Path
import sys,json,math
R=Path(__file__).resolve().parent;sys.path.insert(0,str(R.parent/'reversion-20261021/plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from metrics import meaningful
from analyze import measures
names=['baseline','reserve-delay','reserve-rest','maker-rest','maker-no-skew','time-exit-size','value-exit-gate','reserve-cost-quote','inventory-delta','no-skew-reserve-delay','sparse-touch','no-skew-sparse-touch','whale-urgency','no-skew-sparse-whale','no-skew-sparse-time','no-skew-sparse30-whale']
data=[]
for name in names:
 arm='Baseline'if name=='baseline'else'Candidate';p=R/('development-'+name)/('CurrentBX-'+arm+'.json')
 if p.exists():data.append((name,json.loads(p.read_text())['Markets']['BX']['Bars']))
fig,axes=plt.subplots(math.ceil(len(data)/3),3,figsize=(20,3.5*math.ceil(len(data)/3)),squeeze=False,sharex=True,sharey=True,facecolor='#091b30')
lo,hi=0,0
for ax,(name,bars)in zip(axes.flat,data):
 ax.set_facecolor('#091b30');first=bars[0]['Open'];price=lambda x:100*(x/first-1)
 for i,b in enumerate(bars):
  c='#27e8b8'if b['Close']>=b['Open']else'#ff4e80';ax.vlines(i,price(b['Low']),price(b['High']),color=c,lw=.7)
  h=abs(price(b['Close'])-price(b['Open']));bottom=price(min(b['Open'],b['Close']))
  if h:ax.add_patch(Rectangle((i-.32,bottom),.64,h,color=c))
  else:ax.hlines(bottom,i-.32,i+.32,color=c,lw=.7)
  lo=min(lo,price(b['Low']));hi=max(hi,price(b['High']))
 x=meaningful(bars,.25);m=measures(bars,.25)
 ax.set_title(f'{name}\nLong-leg occupancy {100*x["MeaningfulLong8"]:.0f}% | max {x["MeaningfulMaxLeg"]}m | strict pullbacks {x["MeaningfulPullbacks"]}',color='white',fontsize=10,loc='left')
 ax.tick_params(colors='#bbcce0',labelsize=8);ax.grid(alpha=.15);ax.axhline(0,color='#56718a',lw=.5);ax.set_xlim(-1,60)
for ax in axes.flat:ax.set_ylim(lo-.07,hi+.07)
for ax in list(axes.flat)[len(data):]:ax.set_visible(False)
fig.suptitle('Newly captured BX world — all tested arms, actual matched-order candles\nIdentical starting checkpoint; 20-minute adaptation, 60-minute measurement; one shared vertical scale',color='white',fontsize=16)
fig.tight_layout(rect=[0,0,1,.95]);fig.savefig(R/'CurrentBX-all-arms.png',dpi=130);plt.close(fig)
print('Rendered',len(data),'arms on one vertical scale')
