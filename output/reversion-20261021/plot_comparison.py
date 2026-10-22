from pathlib import Path
import sys,json
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'plot-runtime'))
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from analyze import measures

folder=sys.argv[1]if len(sys.argv)>1 else 'results'
data={(d['Case'],d['Arm']):d for p in (ROOT/folder).glob('*.json')for d in [json.loads(p.read_text(encoding='utf8'))]}
cases=[n for n in ['Seed71','Seed7919','Seed104729','Current','Older','Aged','Seed907','Seed65537']if (n,'Baseline')in data and(n,'Candidate')in data]
for market in ['BX','BT','BG']:
    fig,axes=plt.subplots(len(cases),2,figsize=(15,3.05*len(cases)),squeeze=False,facecolor='#071b39')
    fig.suptitle(f'{market} | 60 one-minute candles per run\nMomentum + Whale baseline versus Reversion candidate',color='white',fontsize=17,y=.995)
    for row,name in enumerate(cases):
        limits=[]
        for col,arm in enumerate(['Baseline','Candidate']):
            ax=axes[row,col];ax.set_facecolor('#071b39')
            bars=data[name,arm]['Markets'][market]['Bars'];first=bars[0]['Open'];normalize=lambda x:100*(x/first-1)
            for i,b in enumerate(bars):
                color='#27e8b8'if b['Close']>=b['Open']else'#ff4e80'
                ax.vlines(i,normalize(b['Low']),normalize(b['High']),color=color,linewidth=.7)
                lower=normalize(min(b['Open'],b['Close']));height=abs(normalize(b['Close'])-normalize(b['Open']))
                if height:ax.add_patch(Rectangle((i-.32,lower),.64,height,facecolor=color,edgecolor=color,linewidth=.4))
                else:ax.hlines(lower,i-.32,i+.32,color=color,linewidth=.7)
                limits.extend([normalize(b['Low']),normalize(b['High'])])
            x=measures(bars,.1 if market=='BG'else.25)
            ax.set_title(f'{name} - {arm} | longest color run {x["LongestRun"]}m | completed pullbacks {x["Pullbacks"]}',color='white',fontsize=10,loc='left')
            ax.tick_params(colors='#a6bcd7',labelsize=8);ax.grid(color='#263d60',alpha=.4,linewidth=.6)
            ax.axhline(0,color='#6485ad',linewidth=.5,alpha=.6);ax.set_xlim(-1,len(bars));ax.set_ylabel('Change from first open (%)',color='#a6bcd7',fontsize=8)
            for spine in ax.spines.values():spine.set_color('#263d60')
            if row==len(cases)-1:ax.set_xlabel('Simulated minutes after adaptation',color='#a6bcd7',fontsize=9)
        pad=max(.02,(max(limits)-min(limits))*.08)
        for ax in axes[row]:ax.set_ylim(min(limits)-pad,max(limits)+pad)
    fig.tight_layout(rect=[0,0,1,.965]);fig.savefig(ROOT/f'{folder}-{market}.png',dpi=130,facecolor=fig.get_facecolor());plt.close(fig)
print('Rendered',folder,len(cases),'paired cases in all three markets')
