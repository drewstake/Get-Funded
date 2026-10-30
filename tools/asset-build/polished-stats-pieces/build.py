from pathlib import Path
from copy import deepcopy
from collections import defaultdict
import json,html,shutil,importlib.util,itertools,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'assets/ui-kits/Collections/06 - Polished Stats Pieces'
COLORS=dict(bg='#031634',blueTop='#093982',blueBottom='#041B49',blueEdge='#0866D6',purpleTop='#7531FF',purpleBottom='#2813A5',purpleEdge='#A16AFF',text='#F5F8FF',muted='#ABC8F6',gain='#20EDAE',loss='#FF69A7',gold='#FFCF36',track='#28518D')
IDS=dict(Trade='135864586704544',Accounts='80175474742009',Shop='133669386970310',Stats='140314319475475',Leaderboard='80175474742009',Positions='133669386970310',Review='77222088024812',Learn='103790301090850',Settings='101222726907418',Help='135400245653127')
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
def node(kind,name,x,y,w,h,**kwargs):return dict(kind=kind,name=name,x=x,y=y,w=w,h=h,**kwargs)
def frame(name,x,y,w,h,style='blue',**kwargs):
 styles=dict(blue=dict(top=COLORS['blueTop'],bottom=COLORS['blueBottom'],edge=COLORS['blueEdge'],radius=19,stroke=2),
  purple=dict(top=COLORS['purpleTop'],bottom=COLORS['purpleBottom'],edge=COLORS['purpleEdge'],radius=19,stroke=3),
  control=dict(top='#0A3274',bottom='#031B4E',edge='#265DC0',radius=12,stroke=2),
  selected=dict(top='#9437FF',bottom='#4914CF',edge='#B176FF',radius=15,stroke=3),
  account=dict(top='#0279E6',bottom='#00409B',edge='#0B8AFF',radius=13,stroke=2))
 return node('Frame',name,x,y,w,h,**(styles.get(style,{})|kwargs))
def label(name,text,x,y,w,h,size=22,color=None,font='display',align='left'):
 return node('TextLabel',name,x,y,w,h,text=text,size=size,color=color or COLORS['text'],font=font,align=align)
def button(name,text,x,y,w,h,style='control'):
 n=frame(name,x,y,w,h,style);n['kind']='TextButton';n['children']=[label(name+'Label',text,18,0,w-36,h,20)]
 return n
def line(name,x,y,w,h,color='#365DE0'):return node('Frame',name,x,y,w,h,bg=color)
def icon(name,kind,x,y,size):
 if kind in IDS:return node('ImageLabel',name,x,y,size,size,image='rbxassetid://'+IDS[kind],asset=kind.lower())
 n=node('Frame',name,x,y,size,size,children=[])
 def c(nn):n['children'].append(nn)
 if kind=='info':
  n.update(bg='#94C9FF',radius=size/2)
  c(label(name+'Glyph','i',0,-1,size,size,round(size*.76),'#123A83','display','center'))
 elif kind=='chevron':
  c(node('Frame',name+'Left',size*.27,size*.43,size*.33,3,bg='#FFFFFF',rotation=45,radius=2))
  c(node('Frame',name+'Right',size*.48,size*.43,size*.33,3,bg='#FFFFFF',rotation=-45,radius=2))
 elif kind=='calendar':
  c(frame(name+'Body',size*.12,size*.2,size*.76,size*.7,'none',bg='#092D6E',edge='#80B5FF',stroke=3,radius=4))
  c(line(name+'Top',size*.14,size*.38,size*.72,3,'#80B5FF'))
  for a in (.3,.7):c(node('Frame',name+'Ring'+str(a),size*a-2,0,4,size*.3,bg='#80B5FF',radius=2))
  for row in range(2):
   for col in range(3):c(node('Frame',name+f'Dot{row}{col}',size*(.25+.2*col),size*(.52+.19*row),size*.1,size*.1,bg='#80B5FF',radius=1))
 elif kind=='bars':
  for i in range(3):c(frame(name+str(i),size*(.08+.30*i),size*(.60-.20*i),size*.23,size*(.35+.20*i),'none',top='#B38CFF',bottom='#6031EE',radius=5))
 elif kind=='clipboard':
  c(frame(name+'Body',size*.2,size*.12,size*.6,size*.8,'none',top='#A794FF',bottom='#674AF0',radius=7))
  c(frame(name+'Clip',size*.36,0,size*.28,size*.26,'none',bg='#B5A7FF',radius=5))
  for i in range(3):c(node('Frame',name+str(i),size*.33,size*(.36+i*.16),size*.34,3,bg='#5B35CF',radius=2))
 return n
def help_button(name,x,y):
 n=node('TextButton',name,x,y,44,44,children=[icon(name+'Disc','info',7,7,30)]);return n
def dropdown(name,text,x,y,w):
 n=button(name,text,x,y,w,56)
 n['children'][0].update(w=w-70,size=20)
 n['children'].append(icon(name+'Chevron','chevron',w-43,16,24))
 return n
def bar(name,x,y,w,win,loss,even=0):
 total=win+loss+even
 n=frame(name,x,y,w,21,'none',bg=COLORS['track'],radius=11,clip=True,children=[])
 at=0
 for nameSuffix,v,top,bottom in [('Win',win,'#29F9BA','#0AD59E'),('Loss',loss,'#FF85B9','#F65096'),('Even',even,'#85A8DB','#5977A6')]:
  if v>0 and total>0:
   n['children'].append(frame(name+nameSuffix,at*w,0,w*v/total,21,'none',top=top,bottom=bottom,radius=10))
   at+=v/total
 n['weights']=[win,loss,even]
 return n
def metric(key,title,value,x,y,w,caption=None,details=None,weights=None):
 n=frame(key+'Card',x,y,w,265,children=[
 label(key+'Title',title,26,22,w-88,44,28),help_button(key+'Help',w-62,16),
 label(key+'Value',value,26,82,w-52,59,52)])
 n['children'].append(bar(key+'Bar',26,150,w-52,*(weights or [0,0,0])))
 if details:
  for i,(text,val,color) in enumerate(details):
   xx=26 if i==0 else w/2
   align='left' if i==0 else 'right'
   n['children'] += [label(key+'DetailLabel'+str(i),text,xx,187,w/2-26,29,19,COLORS['muted'],'body',align),label(key+'Detail'+str(i),val,xx,216,w/2-26,29,22,color,'display',align)]
 if caption:n['children'].append(label(key+'Caption',caption,26,210,w-52,36,21,COLORS['muted'],'body'))
 return n
def templates():
 hero=frame('HeroCard',284,202,1364,214,'purple',children=[
  label('TotalTitle','Total P&L',32,22,190,44,34),help_button('TotalHelp',200,19),
  label('TotalValue','-$56,808.75',32,74,820,92,84,COLORS['loss']),
  label('TotalCaption','Closed trades only',32,164,640,35,22,COLORS['muted'],'body'),
  line('HeroDivider',852,40,1,134,'#775BFA'),
  label('AttemptsLabel','7 attempts',900,56,166,30,22,COLORS['text'],'body'),
  label('ClosedTradesLabel','41 closed trades',1090,56,250,30,22),
  icon('AttemptsIcon','clipboard',940,102,52),icon('ClosedTradesIcon','bars',1136,94,68),
  icon('HeroWatermark','bars',1240,106,110)])
 for part in hero['children'][-1]['children']:part['transparency']=0.8
 cards=[
  metric('Trade','Trade win rate','29.27%',286,434,446,'12 wins / 41 trades',weights=[12,29,0]),
  metric('Average','Avg win / avg loss','0.45',749,434,440,details=[('Avg win','$1,073.42',COLORS['gain']),('Avg loss','-$2,403.09',COLORS['loss'])],weights=[12881/12,69689.75/29,0]),
  metric('Factor','Profit factor','0.18',1205,434,443,details=[('Gross wins','$12,881.00',COLORS['gain']),('Gross losses','-$69,689.75',COLORS['loss'])],weights=[12881,69689.75,0])]
 daily=frame('DailyStats',286,717,1362,158,children=[
  label('DailyTitle','Daily stats',26,14,230,42,30),help_button('DailyHelp',176,12),
  label('DayTitle','Day win rate',82,63,265,29,21,COLORS['muted'],'body'),
  icon('DayCalendar','calendar',28,95,37),label('DayValue','—',82,96,220,37,34),
  line('DailyDividerA',376,69,1,66),label('BestTitle','Best day % of total profit',452,63,337,29,21,COLORS['muted'],'body'),
  icon('BestCalendar','calendar',444,95,37),label('BestValue','—',496,96,245,37,34),
  line('DailyDividerB',777,69,1,66),icon('DailyInfo','info',817,77,30),
  label('CoverageCopy','Some trades have no dates.\nDaily stats need dated history.',864,70,279,66,17,COLORS['text'],'body'),
  button('DatedButton','View dated history',1136,71,206,52)])
 daily['children'][-1]['children'][0].update(size=18,w=164)
 daily['children'][-1]['children'].append(icon('DatedArrow','chevron',178,16,20))
 daily['children'][-1]['children'][-1]['rotation']=-90
 side=frame('Sidebar',0,0,258,941,'none',top='#073473',bottom='#041D50',edge='#0C4BA0',stroke=3,radius=28,children=[
  label('BrandGet','Get',24,24,74,56,38),label('BrandFunded','Funded!',96,24,154,56,38,COLORS['gold'])])
 for i,name in enumerate(['Trade','Accounts','Shop','Stats','Leaderboard','Positions','Review','Learn']):
  n=button('Nav'+name,name,16,96+i*70,230,63,'selected' if name=='Stats' else 'control')
  n['children'][0].update(x=78,w=146,size=22)
  n['children'].append(icon('Icon'+name,name,26,12,39))
  side['children'].append(n)
 account=dropdown('AccountPicker','$5K Funded #5',16,760,230);account.update(top='#0279E6',bottom='#00409B',edge='#0B8AFF')
 account['children'][0].update(x=50,w=147,size=18)
 account['children'].append(icon('AccountTrophy','Accounts',10,9,36))
 side['children'] += [account,icon('SettingsIcon','Settings',24,847,42),label('SettingsText','Settings',81,850,140,35,21),icon('HelpIcon','Help',194,837,52)]
 full=node('Frame','PolishedStats',0,0,1672,941,bg=COLORS['bg'],children=[
 side,label('PageTitle','Your Stats',296,10,980,80,62),
 label('PageSubtitle','Your trading performance at a glance',296,84,1080,36,24,'#9EC7FF'),
 label('AccountLabel','Funded accounts',297,132,149,45,18,COLORS['muted'],'body'),
 dropdown('FundedDropdown','All funded accounts',448,128,393),
 line('FilterDivider',865,138,1,36),
 label('ScopeLabel','Scope',888,132,66,45,18,COLORS['muted'],'body'),
 dropdown('ScopeDropdown','Lifetime · all attempts',953,128,282),
 label('ScopeSummary','7 attempts · 6 blown · Includes restarts',1318,135,329,42,18,COLORS['muted'],'body'),
 hero,*cards,daily,label('Footer','Closed trades · UTC days · Saved across restarts',286,890,1310,34,16,COLORS['muted'],'body')])
 result={'Assembled':full}
 for n in [hero,*cards,daily,full['children'][4],full['children'][7],side]:
  nn=deepcopy(n);nn['x']=nn['y']=0;result[nn['name']]=nn
 # Text-free surfaces, separate from values, icons and hit targets.
 for name,style,w,h in [('HeroBackground','purple',600,160),('CardBackground','blue',440,265),('DailyBackground','blue',700,158),('DropdownBackground','control',392,56),('DropdownHover','control',392,56),('DropdownPressed','control',392,56),('DropdownDisabled','control',392,56),('MenuBackground','control',392,218),('NavDefault','control',230,63),('NavSelected','selected',230,63),('AccountBackground','account',230,56),('ButtonDefault','control',206,52),('ButtonPrimary','selected',206,52),('ProgressTrack','none',392,21),('ProgressWin','none',196,21),('ProgressLoss','none',196,21)]:
  n=frame(name,0,0,w,h,style)
  if name=='DropdownHover':n['edge']='#96C9FF'
  if name=='DropdownPressed':n.update(top='#061B44',bottom='#04122B',edge='#5276D6')
  if name=='DropdownDisabled':n.update(top='#233252',bottom='#192441',edge='#3C4C70')
  if name=='ProgressTrack':n.update(bg=COLORS['track'],radius=11)
  if name=='ProgressWin':n.update(top='#29F9BA',bottom='#0AD59E',radius=11)
  if name=='ProgressLoss':n.update(top='#FF85B9',bottom='#F65096',radius=11)
  result[name]=n
 result['InfoButton']=help_button('InfoButton',0,0)
 result['CalendarIcon']=icon('CalendarIcon','calendar',0,0,48)
 result['AttemptsIcon']=icon('AttemptsIcon','clipboard',0,0,64)
 result['TradesIcon']=icon('TradesIcon','bars',0,0,64)
 result['ChevronIcon']=icon('ChevronIcon','chevron',0,0,32)
 result['OutcomeBar']=bar('OutcomeBar',0,0,392,12,29,0)
 menu=frame('FundedMenuOpen',0,0,392,274,'control',children=[dropdown('MenuTrigger','All funded accounts',0,0,392)])
 for i,text in enumerate(['All funded accounts','$5K accounts','$10K accounts','$25K accounts']):
  n=button('MenuOption'+str(i),text,8,64+i*50,376,46,'selected' if i==0 else 'control')
  n['children'][0]['size']=18
  menu['children'].append(n)
 result['FundedMenuOpen']=menu
 return result

def svg(n,root=True):
 w,h=n['w'],n['h'];name=n['name']
 if root:s=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
 else:s=f'<g transform="translate({n["x"]} {n["y"]}) rotate({n.get("rotation",0)} {w/2} {h/2})">'
 fill=n.get('bg','none')
 if 'top'in n:
  s+=f'<defs><linearGradient id="{name}Fill" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{n["top"]}"/><stop offset="1" stop-color="{n["bottom"]}"/></linearGradient></defs>'
  fill=f'url(#{name}Fill)'
 if fill!='none' or n.get('edge'):
  stroke=n.get('stroke',0);inset=stroke/2
  s+=f'<rect x="{inset}" y="{inset}" width="{w-stroke}" height="{h-stroke}" rx="{n.get("radius",0)}" fill="{fill}" stroke="{n.get("edge","none")}" stroke-width="{stroke}"/>'
 # Only text-free primitive nodes are exported as SVG assets.
 for c in n.get('children',[]):s+=svg(c,False)
 s+='</svg>' if root else '</g>'
 return s

# Reconstructed vector navigation icons for offline reuse. Native GUI reuses existing game IDs.
def nav_svg(name):
 stroke='#062652'
 shapes={
 'trade':'<rect x="8" y="32" width="12" height="24" rx="3" fill="#B690FF"/><rect x="25" y="20" width="12" height="36" rx="3" fill="#9659FF"/><rect x="42" y="6" width="12" height="50" rx="3" fill="#7230EF"/>',
 'accounts':'<path d="M19 8h26v19c0 11-6 18-13 18s-13-7-13-18Z" fill="#FFD22C"/><path d="M18 12H7v11c0 10 7 16 17 16m22-27h11v11c0 10-7 16-17 16" fill="none" stroke="#FFB415" stroke-width="6"/><path d="M28 44h8v9h10v7H18v-7h10Z" fill="#FFAF08"/><path d="m32 16 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z" fill="#FFF19C"/>',
 'shop':'<rect x="7" y="21" width="50" height="35" rx="6" fill="#148AF2"/><path d="M23 22V11h18v11" fill="none" stroke="#6EE0FF" stroke-width="6"/><path d="M8 32h48v10H8Z" fill="#0069C9"/><rect x="27" y="31" width="10" height="15" rx="2" fill="#FFE045"/>',
 'stats':'<path d="m8 36 25-31 23 29-14-2-8 27-18-5 8-22Z" fill="#36E44E"/><path d="m24 29 9-13 10 13" fill="none" stroke="#A0FF67" stroke-width="4"/>',
 'review':'<path d="M14 5h26l13 14v41H14Z" fill="#F3F7FF"/><path d="M40 5v15h13" fill="#91C8F4"/><path d="M21 24h15m-15 8h10" fill="none" stroke="#3877B4" stroke-width="4"/><path d="m23 43 7 7 16-18" fill="none" stroke="#25BD68" stroke-width="8"/>',
 'learn':'<path d="M32 15C23 8 12 7 5 11v42c10-2 18 0 27 7 9-7 17-9 27-7V11c-7-4-18-3-27 4Z" fill="#9860F5"/><path d="M32 13C23 6 15 6 9 8v40c10 0 17 3 23 8 6-5 13-8 23-8V8c-6-2-14-2-23 5Z" fill="#FFFBEF"/><path d="M32 14v40M15 18l11 4m-11 6 11 4m12-10 11-4m-11 14 11-4" fill="none" stroke="#AE97DA" stroke-width="3"/>',
 'settings':'<path d="m26 4 12 0 2 9 7 4 9-2 6 11-7 7v8l5 7-8 9-9-4-7 4-3 7-12-3-1-9-7-5-9 1-3-12 7-5 1-8-4-8 10-7 7 5Z" fill="#20BCEA"/><circle cx="31" cy="33" r="12" fill="#064779"/><circle cx="31" cy="33" r="5" fill="#5CE4FF"/>',
 'help':'<rect x="6" y="4" width="52" height="56" rx="14" fill="#A846FF"/><path d="M22 23c0-13 23-13 23 0 0 7-11 7-11 16" fill="none" stroke="#E7BBFF" stroke-width="7"/><circle cx="34" cy="49" r="4" fill="#E7BBFF"/>'
 }
 shapes['leaderboard']=shapes['accounts'];shapes['positions']=shapes['shop']
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 64 64"><g stroke="{stroke}" stroke-width="2" stroke-linejoin="round">{shapes[name]}</g></svg>'

def prop(p,tag,name,value):
 el=ET.SubElement(p,tag,{'name':name})
 if tag=='Color3':
  for key,val in zip(['R','G','B'],[int(value[i:i+2],16)/255 for i in (1,3,5)]):ET.SubElement(el,key).text=str(val)
 elif tag=='UDim2':
  for key,val in zip(['XS','XO','YS','YO'],value):ET.SubElement(el,key).text=str(val)
 elif tag=='UDim':
  for key,val in zip(['S','O'],value):ET.SubElement(el,key).text=str(val)
 elif tag=='Content':ET.SubElement(el,'url').text=value
 else:el.text=str(value).lower() if isinstance(value,bool) else str(value)
 return el
REFERENTS=itertools.count(1)
def add_item(parent,cls,name):
 item=ET.SubElement(parent,'Item',{'class':cls,'referent':'RBX'+str(next(REFERENTS))});p=ET.SubElement(item,'Properties');prop(p,'string','Name',name);return item,p
def xml_node(parent,n):
 item,p=add_item(parent,n['kind'],n['name'])
 prop(p,'UDim2','Position',[0,n['x'],0,n['y']]);prop(p,'UDim2','Size',[0,n['w'],0,n['h']])
 prop(p,'int','BorderSizePixel',0);prop(p,'float','BackgroundTransparency',n.get('transparency',0) if ('top'in n or 'bg'in n)else 1)
 if 'top'in n:prop(p,'Color3','BackgroundColor3','#FFFFFF')
 elif 'bg'in n:prop(p,'Color3','BackgroundColor3',n['bg'])
 if n.get('rotation'):prop(p,'float','Rotation',n['rotation'])
 if n.get('clip'):prop(p,'bool','ClipsDescendants',True)
 if n['kind'] in ['TextLabel','TextButton']:
  prop(p,'string','Text',n.get('text',''));prop(p,'Color3','TextColor3',n.get('color',COLORS['text']))
  prop(p,'float','TextSize',n.get('size',20));prop(p,'float','TextStrokeTransparency',1)
  prop(p,'token','Font',17 if n.get('font')=='body' else 26);prop(p,'bool','TextWrapped',True)
  prop(p,'token','TextXAlignment',{'left':0,'right':1,'center':2}.get(n.get('align'),0))
 if n['kind']=='TextButton':prop(p,'bool','AutoButtonColor',False);prop(p,'bool','Active',True);prop(p,'bool','Selectable',True)
 if n['kind']=='ImageLabel':prop(p,'Content','Image',n['image']);prop(p,'token','ScaleType',3)
 if n.get('radius'):
  _,cp=add_item(item,'UICorner','Corners');prop(cp,'UDim','CornerRadius',[0,n['radius']])
 if n.get('edge'):
  _,sp=add_item(item,'UIStroke','Border');prop(sp,'Color3','Color',n['edge']);prop(sp,'float','Thickness',n.get('stroke',1));prop(sp,'token','ApplyStrokeMode',1)
 if n.get('top'):
  _,gp=add_item(item,'UIGradient','Gradient');prop(gp,'float','Rotation',90)
  a=[int(n['top'][i:i+2],16)/255 for i in (1,3,5)];b=[int(n['bottom'][i:i+2],16)/255 for i in (1,3,5)]
  prop(gp,'ColorSequence','Color','0 '+' '.join(map(str,a))+' 0 1 '+' '.join(map(str,b))+' 0 ')
 for c in n.get('children',[]):xml_node(item,c)
 return item
def aggregate(rows):
 wins=[r['pnl'] for r in rows if r['pnl']>0];losses=[-r['pnl'] for r in rows if r['pnl']<0]
 gain,loss=sum(wins),sum(losses);days=defaultdict(float)
 for r in rows:
  if r['date']:days[r['date']]+=r['pnl']
 daily=bool(rows) and all(r['date'] for r in rows)
 av,al=(gain/len(wins) if wins else None),(loss/len(losses) if losses else None)
 data=dict(Net=gain-loss,Gains=gain,Loss=loss,Wins=len(wins),Losses=len(losses),Even=len(rows)-len(wins)-len(losses),Trades=len(rows),AvgWin=av,AvgLoss=al,WinRate=len(wins)/len(rows)if rows else None,
 WinLossRatio=av/al if av is not None and al else None,ProfitFactor=gain/loss if loss else None,NoLosses=gain>0 and loss==0,DailyComplete=daily,DayWinRate=sum(v>0 for v in days.values())/len(days) if daily else None,
 WinningDays=sum(v>0 for v in days.values()),DayCount=len(days),BestDayShare=max(days.values())/(gain-loss) if daily and gain>loss else None,Partial=False,CountUnknown=False,
 Attempts=len(set(r['account'] for r in rows)),Blown=len(set(r['account'] for r in rows if not r['current'])))
 return {k:v for k,v in data.items() if v is not None}
def fixtures():
 old=importlib.util.spec_from_file_location('old_stats_builder',ROOT/'tools/asset-build/stats-kit/build.py');mod=importlib.util.module_from_spec(old);old.loader.exec_module(mod)
 rows=mod.fixture()
 return {tier:{period:aggregate([r for r in rows if(tier=='All' or r['tier']==tier)and(period!='Current'or r['current'])and(period!='Dated'or r['date'])])for period in ['Life','Current','Dated']}for tier in ['All','5K','10K','25K']}
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 for d in ['assets/svg','assets/png','assets/fonts','roblox','source']:(OUT/d).mkdir(parents=True,exist_ok=True)
 spec=dict(width=1672,height=941,colors=COLORS,icons=IDS,templates=templates())
 write(OUT/'source/components.json',json.dumps(spec,indent=2))
 data=fixtures();write(OUT/'source/demo-fixtures.json',json.dumps(data,indent=2))
 assets=[]
 surfaces=[(k,n)for k,n in spec['templates'].items() if k.endswith('Background') or k.startswith(('DropdownH','DropdownP','DropdownD','Button','Nav','Progress'))]
 for k,n in surfaces:
  filename='surface-'+''.join('-'+c.lower() if c.isupper()else c for c in k).lstrip('-')
  write(OUT/f'assets/svg/{filename}.svg',svg(n))
  assets.append(dict(name=k,kind='surface',svg=f'assets/svg/{filename}.svg',png=f'assets/png/{filename}.png',width=round(n['w']*2),height=round(n['h']*2),scale=2,
  sliceCenter=[48,48,round(n['w']*2-48),round(n['h']*2-48)] if n['h']>=52 else [22,20,round(n['w']*2-22),22],
  nativeTemplate=k))
 for name in IDS:
  k=name.lower();write(OUT/f'assets/svg/icon-{k}.svg',nav_svg(k))
  assets.append(dict(name=name,kind='icon',svg=f'assets/svg/icon-{k}.svg',png=f'assets/png/icon-{k}.png',width=256,height=256,existingRobloxId='rbxassetid://'+IDS[name],provenance='New vector reconstruction for offline use. Native uses existing game asset ID.'))
 for k in ['CalendarIcon','AttemptsIcon','TradesIcon','ChevronIcon']:
  n=spec['templates'][k];filename='icon-'+k.replace('Icon','').lower();write(OUT/f'assets/svg/{filename}.svg',svg(n))
  assets.append(dict(name=k,kind='icon',svg=f'assets/svg/{filename}.svg',png=f'assets/png/{filename}.png',width=256,height=256,nativeTemplate=k))
 # The info disc includes a glyph, authored as vector paths so it is independent of font availability.
 write(OUT/'assets/svg/icon-info.svg','<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><circle cx="32" cy="32" r="29" fill="#94C9FF"/><circle cx="32" cy="18" r="4" fill="#123A83"/><path d="M28 27h8v20h-8Z" fill="#123A83"/></svg>')
 assets.append(dict(name='Info',kind='icon',svg='assets/svg/icon-info.svg',png='assets/png/icon-info.png',width=256,height=256,nativeTemplate='InfoButton'))
 write(OUT/'assets.json',json.dumps(assets,indent=2))
 write(OUT/'assets.js','window.ASSETS='+json.dumps(assets)+';')
 for f in ['LilitaOne-Regular.ttf','OFL.txt']:shutil.copy2(ROOT/'assets/ui-kits/Collections/04 - Pop Shop/assets/fonts'/f,OUT/'assets/fonts'/f)
 shutil.copy2(ROOT/'assets/design-previews/polished-game-layout-options-2026-09-29/v2-dropdown/01-summary-banner.png',OUT/'reference.png')
 tokens=dict(colors=COLORS,referenceCanvas=[1672,941],font=dict(robloxDisplay='FredokaOne',robloxBody='Gotham',webDisplay='Lilita One',webBody='Segoe UI'),corner=dict(card=19,control=12,nav=15),stroke=dict(card=2,hero=3),spacing=[8,16,24,32],minimumTarget=44)
 write(OUT/'design-tokens.json',json.dumps(tokens,indent=2))
 previous=(ROOT/'assets/ui-kits/Collections/05 - Stats Collection/01 - Polished Game/roblox/StatsKit.luau').read_text(encoding='utf-8')
 formatter=previous[previous.index('local function money'):previous.index('function Kit.Metric')]
 module=(HERE/'StatsPieces.luau').read_text(encoding='utf-8').replace('__SPEC_JSON__',json.dumps(spec,separators=(',',':'))).replace('__FORMATTERS__',formatter)
 write(OUT/'roblox/StatsPieces.luau',module)
 example=(HERE/'Example.client.luau').read_text(encoding='utf-8').replace('__FIXTURES__',json.dumps(data,separators=(',',':')))
 write(OUT/'roblox/Example.client.luau',example)
 root=ET.Element('roblox',{'version':'4'});folder,_=add_item(root,'Folder','PolishedStatsPieces')
 components,_=add_item(folder,'Folder','Components')
 for name,n in spec['templates'].items():
  if name!='Assembled':xml_node(components,n)
 for cls,name,source in [('ModuleScript','StatsPieces',module),('LocalScript','Example',example)]:
  _,p=add_item(folder,cls,name);prop(p,'ProtectedString','Source',source)
  if cls=='LocalScript':prop(p,'bool','Disabled',True)
 write(OUT/'roblox/PolishedStatsPieces.rbxmx',ET.tostring(root,encoding='unicode',xml_declaration=True))
 root=ET.Element('roblox',{'version':'4'});screen,p=add_item(root,'ScreenGui','PolishedStats_Assembled')
 prop(p,'bool','Enabled',False);prop(p,'bool','ResetOnSpawn',False);prop(p,'bool','IgnoreGuiInset',True);prop(p,'token','ZIndexBehavior',1)
 xml_node(screen,spec['templates']['Assembled'])
 write(OUT/'roblox/AssembledPreview.rbxmx',ET.tostring(root,encoding='unicode',xml_declaration=True))
 write(OUT/'spec.js','window.PIECES='+json.dumps(spec)+';\nwindow.FIXTURES='+json.dumps(data)+';')
 for f in ['index.html','preview.css','preview.js','README.md']:shutil.copy2(HERE/f,OUT/f)
 print(json.dumps(dict(output=str(OUT),templates=len(spec['templates']),assets=len(assets))))
if __name__=='__main__':main()
