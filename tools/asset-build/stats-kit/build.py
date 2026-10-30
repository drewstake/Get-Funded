from pathlib import Path
import json, shutil, html, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
COLLECTION=ROOT/'assets/ui-kits/Collections/05 - Stats Collection'
FONT=ROOT/'assets/ui-kits/Collections/04 - Pop Shop/assets/fonts'
REFERENCE=ROOT/'assets/design-previews/stats-ui-options-2026-09-29'
THEMES=[
 dict(id='01',name='Polished Game',layout='polished',folder='01 - Polished Game',reference='01-polished-game.png',
      description='A cleaner game feel. Rounded headings, rich blue surfaces, and one violet hero card.',
      bg='#06142E',sidebar='#0A2350',surface='#102E60',card='#102E60',border='#294F83',text='#F5F8FF',muted='#B0C7E8',
      accent='#7138E8',accent_text='#C8B2FF',gain='#3BE6B0',loss='#FF81AF',track='#294B79',notice='#0C254C',gold='#FFD34D',focus='#77D9FF',radius=18),
 dict(id='02',name='Dark Focus',layout='dark',folder='02 - Dark Focus',reference='02-dark-focus.png',
      description='Quiet surfaces and clear numbers. A larger P&L card anchors a compact, focused dashboard.',
      bg='#0B1220',sidebar='#0F1929',surface='#142135',card='#142135',border='#2B3E5A',text='#F1F5FC',muted='#ACBCD5',
      accent='#7141DB',accent_text='#C7B0FF',gain='#4AD9B1',loss='#FF87AC',track='#2A3B54',notice='#111F32',gold='#F5C65B',focus='#A99AFF',radius=14),
 dict(id='03',name='Bright Minimal',layout='light',folder='03 - Bright Minimal',reference='03-bright-minimal.png',
      description='Bright, spacious, and welcoming. A full-width summary sits above a simple set of stat cards.',
      bg='#F8F9FD',sidebar='#EEEBFB',surface='#FFFFFF',card='#FFFFFF',border='#D8D8EC',text='#172148',muted='#596582',
      accent='#6934D5',accent_text='#5B28C4',gain='#08785C',loss='#BB245C',track='#E7EAF2',notice='#F0EFFA',gold='#9A6A00',focus='#5424B9',radius=18)
]
ICONS={
'trade':'<rect x="3" y="14" width="4" height="7" rx="1"/><rect x="10" y="9" width="4" height="12" rx="1"/><rect x="17" y="3" width="4" height="18" rx="1"/>',
'accounts':'<path d="M7 3h10v6c0 4-2 6-5 6S7 13 7 9V3Z"/><path d="M7 5H3v3c0 3 2 5 5 5m9-8h4v3c0 3-2 5-5 5M12 15v5m-4 1h8"/>',
'shop':'<path d="M5 7h14l2 14H3L5 7Z"/><path d="M8 8V6a4 4 0 0 1 8 0v2"/>',
'stats':'<path d="M3 20V4m0 16h18M6 15l5-5 4 3 6-8m-5 0h5v5"/>',
'leaderboard':'<circle cx="12" cy="9" r="6"/><path d="m8 14-2 8 6-3 6 3-2-8m-4-9 1 2 2 .3-1.5 1.5.4 2.2-1.9-1-1.9 1 .4-2.2L9 7.3l2-.3Z"/>',
'positions':'<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V3h8v4M3 13h18m-11-2v4h4v-4"/>',
'review':'<path d="M8 4H5v17h14V4h-3"/><rect x="8" y="2" width="8" height="5" rx="1"/><path d="m8 14 3 3 6-6"/>',
'learn':'<path d="M12 6C8 3 5 3 2 4v16c3-1 6-1 10 2 4-3 7-3 10-2V4c-3-1-6-1-10 2Zm0 0v16M5 8l4 1m-4 3 4 1m6-4 4-1m-4 5 4-1"/>',
'settings':'<path d="m9 3 1-2h4l1 2 3 2 3 1 1 4-2 2 1 3-2 4-3-1-3 2-3 2-3-3H4l-2-4 2-3-1-3 3-3 3 1Z" transform="translate(1 1) scale(.9)"/><circle cx="12" cy="12" r="3.5"/>',
'info':'<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v.1"/>',
'calendar':'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 2v6m10-6v6M3 10h18m-14 4h1m4 0h1m4 0h1m-10 4h1m4 0h1"/>',
'chevron':'<path d="m6 9 6 6 6-6"/>',
'check':'<path d="m4 12 5 5L20 6"/>',
'close':'<path d="m6 6 12 12M18 6 6 18"/>',
'clock':'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
'warning':'<path d="m12 3 10 18H2L12 3Z"/><path d="M12 9v5m0 3v.1"/>'
}
NAV=[('Trade','trade'),('Accounts','accounts'),('Shop','shop'),('Stats','stats'),('Leaderboard','leaderboard'),('Positions','positions'),('Review','review'),('Learn','learn')]
def write(path,content):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(content,encoding='utf-8')
def img(name):return f'<img src="assets/svg/icon-{name}.svg" alt="">'
def fixture():
 # Original aggregate is preserved. Individual rows are synthetic demonstrations, not exported player history.
 positives=[1280,910,1450,600,1400,925,1530,1020,780,890,995]
 positives.append(12881-sum(positives))
 negatives=[-2300-(i%5)*50 for i in range(28)]
 negatives.append(-69689.75-sum(negatives))
 values=[]
 for i in range(29):
  if i<12:values.append(positives[i])
  values.append(negatives[i])
 tiers=['5K','5K','5K','10K','10K','25K','5K']
 return [dict(pnl=v,account=i%7+1,tier=tiers[i%7],current=i%7==6,date=None if i%9==0 else f'2026-09-{20+i%6:02}') for i,v in enumerate(values)]
def icon_svg(name,t):
 color=t['muted'] if t['layout']=='dark' else (t['gold'] if name in ['accounts','leaderboard'] else t['accent_text'])
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 48 48"><g transform="translate(6 6) scale(1.5)" fill="none" stroke="{color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{ICONS[name]}</g></svg>'
def background_svg(name,t):
 w,h=(480,280) if name in ['panel','hero'] else (360,80)
 colors={'panel':t['card'],'hero':t['accent'] if t['layout']!='light' else '#FFF5FA','button-primary':t['accent'],
         'button-default':t['surface'],'button-disabled':t['track'],'navigation-selected':t['accent'],'notice':t['notice'],'input':t['surface'],'progress-track':t['track']}
 fill=colors[name];r=min(t['radius'],h/2)
 return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect x="1" y="1" width="{w-2}" height="{h-2}" rx="{r}" fill="{fill}" stroke="{t["border"]}" stroke-width="1"/></svg>'
def css_vars(t):
 var={k.replace('_','-'):v for k,v in t.items() if k in ['bg','sidebar','surface','card','border','text','muted','accent','accent_text','gain','loss','track','notice','gold','focus']}
 var['radius']=str(t['radius'])+'px'
 var['display']='"Segoe UI",Arial,sans-serif' if t['layout']=='dark' else 'KitDisplay,"Trebuchet MS",sans-serif'
 var['shadow']='0 6px 20px #17214805' if t['layout']=='light' else 'none'
 return ':root{'+''.join('--'+k+':'+v+';' for k,v in var.items())+'}'
def luau_theme(t):
 mapping={'Bg':'bg','Sidebar':'sidebar','Surface':'surface','Card':'card','Border':'border','Text':'text','Muted':'muted','Accent':'accent','Gain':'gain','Loss':'loss','Track':'track','Notice':'notice'}
 lines=[]
 for key,value in mapping.items():
  c=t[value].lstrip('#');rgb=[int(c[i:i+2],16) for i in (0,2,4)]
  lines.append(f'{key}=Color3.fromRGB({",".join(map(str,rgb))})')
 lines += [f'Radius={t["radius"]}',f'Layout="{t["layout"]}"', 'DisplayFont=Enum.Font.'+('GothamBold' if t['layout']=='dark' else 'FredokaOne')]
 return '{\n '+',\n '.join(lines)+'\n}'
def module_xml(module,example,name):
 root=ET.Element('roblox',{'version':'4'})
 folder=ET.SubElement(root,'Item',{'class':'Folder','referent':'StatsKitFolder'})
 props=ET.SubElement(folder,'Properties');ET.SubElement(props,'string',{'name':'Name'}).text=name+' Stats Kit'
 for cls,n,source in [('ModuleScript','StatsKit',module),('LocalScript','Example',example)]:
  item=ET.SubElement(folder,'Item',{'class':cls,'referent':n})
  p=ET.SubElement(item,'Properties')
  ET.SubElement(p,'string',{'name':'Name'}).text=n
  ET.SubElement(p,'ProtectedString',{'name':'Source'}).text=source
  if cls=='LocalScript':ET.SubElement(p,'bool',{'name':'Disabled'}).text='true'
 return ET.tostring(root,encoding='unicode',xml_declaration=True)
def specimens(t):
 swatches=''.join(f'<div class="swatch"><div class="color" style="background:{t[k]}"></div><strong>{label}</strong><code>{t[k]}</code></div>' for k,label in [('bg','Canvas'),('surface','Surface'),('text','Text'),('muted','Secondary'),('accent','Selected'),('gain','Gain'),('loss','Loss')])
 icons=''.join(f'<div class="icon-tile">{img(n)}<span>{n.title()}</span></div>' for n in ICONS)
 states=[('clock','Loading','Keep the container stable while results arrive.'),('stats','Empty','No closed trades in this scope. Offer a next step.'),('warning','Error','Keep the last valid scope and offer Retry.'),('calendar','Missing dates','Show — and link to the same dated scope.'),('info','Partial history','Keep net P&L; suppress unsupported ratios.'),('check','No losses','Show ∞ only for positive gains with zero losses.')]
 states_html=''.join(f'<div class="mini-state">{img(i)}<strong>{title}</strong><p>{text}</p></div>' for i,title,text in states)
 return f'''<section class="components" id="components"><div class="section-heading"><div><p class="eyebrow">02 / Component system</p><h2>Built to be reused.</h2></div><p>Shared spacing, consistent states, and editable assets. Every label stays live text.</p></div>
 <div class="component-grid">
 <article class="spec"><h3>Buttons &amp; interaction</h3><p>44 px minimum target · 140 ms feedback · visible keyboard focus</p><div class="samples">
 <div class="sample"><button class="primary" data-demo="Primary action activated">View history</button><small>Primary / default</small></div>
 <div class="sample"><button data-demo="Secondary action activated">All accounts</button><small>Secondary</small></div>
 <div class="sample"><button class="primary pressed" data-demo="Pressed state example">Selected</button><small>Pressed</small></div>
 <div class="sample"><button class="focus-sample" data-demo="Focused action activated">Retry</button><small>Focus</small></div>
 <div class="sample"><button disabled>Unavailable</button><small>Disabled</small></div></div>
 <div class="chips"><span class="chip">Lifetime</span><span class="chip success">Win</span><span class="chip error">Loss</span><span class="chip">No dates</span></div></article>
 <article class="spec"><h3>Typography &amp; hierarchy</h3><p>{'Segoe UI' if t['layout']=='dark' else 'Lilita One + Segoe UI'} · tabular figures for data</p>
 <div class="type-row"><small>Page / 36</small><strong>Your Stats</strong></div><div class="type-row"><small>Value / 46</small><strong class="numeral">-$56,808.75</strong></div><div class="type-row"><small>Body / 14</small><span>Closed trades only</span></div></article>
 <article class="spec spec-wide"><h3>Semantic color</h3><p>Violet marks selection. Green and pink carry trading meaning; labels always explain the color.</p><div class="swatches">{swatches}</div></article>
 <article class="spec"><h3>Comparisons</h3><p>Small, labeled bars replace oversized gauges.</p><div class="bar"><span class="win" style="width:29.27%"></span><span class="lose" style="width:70.73%"></span></div><div class="breakdown"><div><span>Winning trades</span><strong class="gain">12 / 41</strong></div><div><span>Trade win rate</span><strong>29.27%</strong></div></div>
 <div class="notice">{img('info')}<p>Gross wins share is 15.60%. Profit factor is 0.18; these express different comparisons.</p></div></article>
 <article class="spec"><h3>Surfaces &amp; spacing</h3><p>Simple backgrounds with text, icons, and numbers placed as separate layers.</p>
 <div class="surface-examples">{''.join(f'<figure><img src="assets/svg/{n}.svg" alt="{n} background"><figcaption>{n.replace("-"," ").title()}</figcaption></figure>' for n in ['panel','button-primary','notice'])}</div>
 <div class="rules"><span><b>{t['radius']} px</b> cards</span><span><b>1 px</b> borders</span><span><b>8 / 16 / 24</b> spacing</span></div></article>
 <article class="spec spec-wide"><h3>Complete states</h3><p>Use the scenario control above to inspect full-screen examples.</p><div class="mini-grid">{states_html}</div></article>
 <article class="spec spec-wide"><h3>16 editable icons</h3><p>Original SVG source + transparent 256 px PNGs + a 1024 px atlas. Upload the PNGs for Roblox.</p><div class="icons">{icons}</div></article>
 </div></section>'''
def page(t):
 nav=''.join(f'<button class="nav-item" data-nav="{n}"'+(' aria-current="page"' if n=='Stats' else '')+f'>{img(icon)}<span>{n}</span></button>' for n,icon in NAV)
 return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
 <title>{t['name']} — Get Funded! Stats Kit</title><link rel="stylesheet" href="kit.css"><style>{css_vars(t)}</style></head>
 <body class="layout-{t['layout']}" data-layout="{t['layout']}">
 <header class="kit-header"><div><p class="eyebrow">Get Funded! / Stats kit {t['id']}</p><h1>{t['name']}</h1><p class="kit-intro">{t['description']}</p></div>
 <nav class="kit-links" aria-label="Kit links"><a href="../index.html">All three kits</a><a href="#components">Components ↓</a><a href="roblox/StatsKit.rbxmx" download>Roblox model</a><a href="design-tokens.json" download>Design tokens</a></nav></header>
 <div class="app">
 <aside class="sidebar"><div class="brand">Get <b>Funded!</b></div><nav aria-label="Game navigation">{nav}</nav><div class="sidebar-bottom"><button class="account-switch" data-account>{img('accounts')}<span>$5K Funded #5</span><span>⌄</span></button><button class="settings" data-settings>{img('settings')}Settings</button></div></aside>
 <main class="content"><div class="content-head"><div><h1>Your Stats</h1><p class="subtitle">Your trading performance at a glance</p></div><span class="sample-label">KIT PREVIEW</span></div>
 <div class="filters"><span class="filter-title">Funded accounts</span><div class="segments" role="group" aria-label="Account size">{''.join(f'<button data-tier="{k}" aria-pressed="{str(k=="All").lower()}">{k if k=="All" else "$"+k}</button>' for k in ['All','5K','10K','25K'])}</div>
 <label class="field">Scope <select id="period"><option value="Life">Lifetime · all attempts</option><option value="Current">Usable accounts</option><option value="Dated">Dated history</option></select></label></div>
 <p class="scope-summary" id="scope-summary"></p>
 <div class="notice" id="coverage">{img('info')}<p></p><button data-dated>View dated history →</button></div>
 <div id="metric-content" aria-live="polite"></div><p class="app-footer">Closed trades · UTC days · Saved across restarts</p></main></div>
 <div class="demo-controls"><span>Interactive kit · synthetic filter fixtures</span><label for="scenario">Scenario</label><select id="scenario"><option value="snapshot">Original totals</option><option value="positive">Profitable days</option><option value="no-loss">No losing trades</option><option value="even">Break-even only</option><option value="partial">Partial history</option><option value="loading">Loading</option><option value="empty">Empty</option><option value="error">Error</option></select><button data-reset>Reset</button><label class="motion"><input id="motion" type="checkbox">Reduced motion</label></div>
 {specimens(t)}
 <footer class="kit-footer">Get Funded! · {t['name']} · Editable local kit <a href="README.md">Integration notes</a><a href="source-concept.png">Original mockup</a></footer>
 <dialog id="help-dialog" aria-labelledby="help-title"><button class="close" data-close aria-label="Close help">×</button><h2 id="help-title"></h2><p></p></dialog>
 <div class="toast" id="toast" role="status" hidden></div><script src="fixture.js"></script><script src="kit.js"></script></body></html>'''
def readme(t):
 return f'''# {t['name']} — Get Funded! Stats UI Kit

{t['description']}

Open index.html locally. This kit works offline and has no build step or external dependency.

## Included
- 01-desktop.png, 02-mobile.png, 03-components.png: rendered previews of this editable kit.
- source-concept.png: original generated direction from the previous request.
- index.html, kit.css, kit.js, fixture.js: responsive interactive components and fixture-driven preview.
- design-tokens.json: colors, typography, spacing, breakpoints, motion, and component sizes.
- assets/svg/: 16 original editable icons and 9 text-free background components.
- assets/png/: matching transparent exports. Icons are 256 × 256; surfaces are exported at 2×.
- assets/icons-atlas.png and assets/icons-atlas.json: 1024 × 1024 image with exact icon rectangles.
- roblox/StatsKit.luau: a self-contained native component module with this theme.
- roblox/StatsKit.rbxmx: importable Folder containing the ModuleScript and a disabled Example LocalScript.
- roblox/Example.client.luau: same explicitly labeled sample entrypoint.
- validation-results.json: export, layout, data-state, interaction and contrast checks.

## Preview interactions
Account size and scope filter a synthetic set of closing fills. The initial All + Lifetime aggregate matches the supplied screenshot: -$56,808.75 net, 12 wins / 41 trades, 0.45 win/loss ratio and 0.18 profit factor. The individual fills, date groups and tier allocations are invented fixtures, not exported account history.
Dated history recomputes ALL six metrics using only dated fixture rows. Current includes only usable fixture accounts.
Scenario examples cover profitable days, no losing trades, break-even trades, partial history, loading, empty and error. Reset restores the original aggregate.
Help works by pointer and keyboard, Escape closes dialogs, and reduced motion respects the OS preference.
Other navigation buttons demonstrate the component; they do not include other game screens.

## Use in Roblox Studio
1. Import roblox/StatsKit.rbxmx as a local model into StarterPlayer > StarterPlayerScripts. This creates the "{t['name']} Stats Kit" Folder with a StatsKit ModuleScript and disabled Example LocalScript.
2. For a preview, enable Example and run Play. It creates a separate ScreenGui using sample totals. Remove or disable Example when done.
3. For integration, require the StatsKit module and call Kit.Mount(player.PlayerGui, aggregate, options).
4. Keep the returned controller and call controller:Update(newAggregate, nextOptions) when server stats or scope change. Call controller:Destroy() on unmount.
5. Reuse Kit.Panel, Kit.Label, Kit.Button, Kit.Progress and Kit.Metric separately if replacing only the Stats page.
No existing source or place was changed by this kit. The native library was validated with temporary unparented instances; production screen integration remains a separate step.

## Native options
- Scope: "All", "5K", "10K", or "25K"; Period: "Life", "Current", or "Dated".
- AccountLabel: displayed funded-account name.
- OnFilter(scopeKey, period): return the matching server aggregate to commit the change. Without this callback, native filters are disabled, so old numbers are never shown with a new scope label.
- OnNavigate(name), OnSettings(), OnRetry(): connect these to the existing game handlers.
- State: "Ready", "Loading", "Empty", or "Error".
The native period button cycles the three scopes. The browser preview uses a select menu. Native phone layout uses a compact title instead of the full sidebar.

## Data contract
Kit.FromAggregate accepts the fields already read by src/shared/StatsView.luau:
Net, Gains, Loss (positive magnitude), Wins, Losses, Even, Trades, AvgWin, AvgLoss (positive magnitude), WinRate, WinLossRatio, ProfitFactor, NoLosses, DailyComplete, DayWinRate, WinningDays, DayCount, BestDayShare, Partial, CountUnknown, Attempts, Blown.
Ratios and percentages arrive from the exchange. Rates are fractions (0.2927), not whole percentages (29.27).
Partial or CountUnknown suppresses trade ratios while retaining total net P&L. Missing dates suppresses daily metrics. Best-day share requires positive net profit and can exceed 100%. Zero gross loss is infinity only when positive gross wins exist; no activity is unavailable.
The progress bar for gross P&L shows gain / (gain + absolute loss), whereas profit factor is gain / absolute loss. They are deliberately distinct.

## Assets and typography
Use SVGs for editing and PNGs for Roblox upload. Text-free surfaces may be sliced; use the asset manifest's recommended slice center in source PNG pixels.
For the icon atlas, upload the PNG and apply ImageRectOffset / ImageRectSize from icons-atlas.json. No asset uploads were performed.
The preview uses {'Segoe UI / Arial system fonts' if t['layout']=='dark' else 'bundled Lilita One for headings and Segoe UI / Arial for body copy'}. Roblox uses {'GothamBold' if t['layout']=='dark' else 'FredokaOne'} for headings and Gotham for body text. These are intentional available-font equivalents rather than identical font files. Lilita One retains its SIL Open Font License in assets/fonts/OFL.txt.
The original vector icons and component assets may be reused and modified in this project.

## Layout and motion
Desktop: {('equal 3 × 2 card grid' if t['layout']=='polished' else 'larger P&L card and compact secondary stats' if t['layout']=='dark' else 'full-width P&L hero, three ratio cards, two daily cards')}.
At tablet widths, cards form two columns; phone width uses a single scrollable column. Targets are at least 44 px high. Browser button feedback is 80–140 ms with 1 px press travel; reduced motion removes transitions.
Native components use immediate selection feedback and keyboard/gamepad selectable controls. Panel objects remain editable Roblox GUI instances, not flattened screenshots.

## Regenerate
From the project root: python tools/asset-build/stats-kit/build.py, then node tools/asset-build/stats-kit/export.cjs, then python tools/asset-build/stats-kit/package.py.
Export uses the locally installed Chrome and bundled Sharp / Playwright paths recorded in the helper. The final ZIP runs without those development tools.
'''
EXAMPLE='''-- Disabled by default. Enable only for a separate sample preview during Play.
local Players=game:GetService("Players")
local Kit=require(script.Parent:WaitForChild("StatsKit"))
local sample={
 Net=-56808.75,Gains=12881,Loss=69689.75,Wins=12,Losses=29,Even=0,Trades=41,
 AvgWin=12881/12,AvgLoss=69689.75/29,WinRate=12/41,
 WinLossRatio=(12881/12)/(69689.75/29),ProfitFactor=12881/69689.75,
 NoLosses=false,DailyComplete=false,Partial=false,CountUnknown=false,Attempts=7,Blown=6,
}
local controller=Kit.Mount(Players.LocalPlayer:WaitForChild("PlayerGui"),sample,{AccountLabel="SAMPLE · $5K Funded #5"})
-- Bind server aggregates with controller:Update(aggregate). Do not calculate production stats on the client.
script.Destroying:Connect(function() controller:Destroy() end)
'''
def build():
 COLLECTION.mkdir(parents=True,exist_ok=True)
 for t in THEMES:
  out=COLLECTION/t['folder']
  for d in ['assets/svg','assets/png','assets/fonts','roblox']:(out/d).mkdir(parents=True,exist_ok=True)
  for f in ['LilitaOne-Regular.ttf','OFL.txt']:shutil.copy2(FONT/f,out/'assets/fonts'/f)
  for f in ['kit.css','kit.js']:shutil.copy2(HERE/f,out/f)
  shutil.copy2(REFERENCE/t['reference'],out/'source-concept.png')
  write(out/'index.html',page(t))
  write(out/'fixture.js','window.STATS_FIXTURE='+json.dumps(fixture())+';')
  manifest=[]
  for name in ICONS:
   write(out/f'assets/svg/icon-{name}.svg',icon_svg(name,t))
   manifest.append(dict(name=name,kind='icon',svg=f'assets/svg/icon-{name}.svg',png=f'assets/png/icon-{name}.png',size=[256,256]))
  for name in ['panel','hero','button-primary','button-default','button-disabled','navigation-selected','notice','input','progress-track']:
   write(out/f'assets/svg/{name}.svg',background_svg(name,t))
   w,h=(960,560) if name in ['panel','hero'] else (720,160)
   inset=48
   manifest.append(dict(name=name,kind='surface',svg=f'assets/svg/{name}.svg',png=f'assets/png/{name}.png',size=[w,h],sliceCenter=[inset,inset,w-inset,h-inset]))
  write(out/'assets.json',json.dumps(manifest,indent=2))
  tokens=dict(name=t['name'],colors={k:v for k,v in t.items() if isinstance(v,str) and v.startswith('#')},radius=dict(card=t['radius'],control=10,pill=999),
    stroke=1,spacing=[4,8,12,16,24,32,48],typography=dict(display='Segoe UI' if t['layout']=='dark' else 'Lilita One',body='Segoe UI, Arial',
    robloxDisplay='GothamBold' if t['layout']=='dark' else 'FredokaOne',robloxBody='Gotham',page=36,cardTitle=18,value=46,bodySize=14,caption=12),
    motion=dict(pressMs=80,selectionMs=140,pressTravelPx=1,reducedMotion=True),layout=dict(sidebar=216,cardPadding=20,cardGap=16,minimumTarget=44,phoneBreakpoint=760,tabletBreakpoint=1200))
  write(out/'design-tokens.json',json.dumps(tokens,indent=2))
  module=(HERE/'StatsKit.luau').read_text(encoding='utf-8').replace('__THEME__',luau_theme(t))
  write(out/'roblox/StatsKit.luau',module);write(out/'roblox/Example.client.luau',EXAMPLE)
  write(out/'roblox/StatsKit.rbxmx',module_xml(module,EXAMPLE,t['name']))
  write(out/'README.md',readme(t))
 write(COLLECTION/'themes.json',json.dumps(THEMES,indent=2))
 cards=''.join(f'''<article><a href="{html.escape(t['folder'])}/index.html"><img src="{html.escape(t['folder'])}/01-desktop.png" alt="{t['name']} stats desktop"></a><div><small>OPTION {t['id']}</small><h2>{t['name']}</h2><p>{t['description']}</p><a class="button" href="{t['folder']}/index.html">Open interactive kit →</a><a href="../../Downloads/05 - Stats - {t['name']}.zip" download>Download ZIP</a></div></article>''' for t in THEMES)
 write(COLLECTION/'index.html',f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Get Funded! — Three Stats UI Kits</title><style>*{{box-sizing:border-box}}body{{margin:0;background:#0b1220;color:#f1f5fc;font:16px/1.6 "Segoe UI",Arial,sans-serif}}main{{max-width:1480px;margin:auto;padding:48px 32px}}small{{color:#b6a0ed;font-size:12px;letter-spacing:.16em}}h1{{font-size:clamp(36px,5vw,64px);line-height:1.05;letter-spacing:-.04em;margin:18px 0}}header{{padding-bottom:36px;max-width:860px}}p{{color:#b2c0d7}}.cards{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:24px}}article{{background:#142135;border:1px solid #2b3e5a;border-radius:18px;overflow:hidden}}article img{{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;object-position:top}}article>div{{padding:24px}}h2{{font-size:25px;margin:8px 0}}a{{color:#c7b0ff}}a:focus-visible{{outline:3px solid #b9a1ff;outline-offset:4px}}article p{{font-size:14px;min-height:70px}}.button{{display:block;padding:11px 14px;background:#713bdd;border-radius:9px;color:white;text-decoration:none;margin:20px 0 14px;text-align:center}}footer{{margin-top:36px;color:#aab9d1;font-size:14px}}.meta{{border-top:1px solid #2b3e5a;padding-top:24px}}@media(max-width:900px){{.cards{{grid-template-columns:1fr}}main{{padding:32px 18px}}article p{{min-height:0}}}}</style></head><body><main><header><small>GET FUNDED! / DESIGN LIBRARY 05</small><h1>Three ways to make<br>your stats feel clearer.</h1><p>Full UI kits for Polished Game, Dark Focus, and Bright Minimal. Each includes desktop and phone previews, reusable components, editable vector assets, and a native Roblox module.</p><a href="../../Browse UI Kits.html">← All UI kits</a></header><section class="cards">{cards}</section><footer><p class="meta">Per kit: 16 icons · 9 surfaces · SVG + transparent PNG · design tokens · native Luau + RBXMX · offline interactive preview</p><p>Original aggregate preserved. Filters use synthetic demonstration trades. See each kit’s README for integration details.</p><a href="../../Downloads/05 - Stats Collection - All Three.zip" download>Download all three kits</a></footer></main></body></html>''')
 write(COLLECTION/'README.md','# Get Funded! — Stats Collection\n\nOpen index.html to compare all three kits. Each subfolder is self-contained; read its README for the asset inventory, data contract and Roblox import instructions. The Downloads folder contains three individual ZIPs and one collection ZIP.\n\nThese kits preserve the three approved visual directions as editable HTML/CSS and native Roblox components. Original generated concept images are included for reference. No production UI source was replaced.\n')
 print(json.dumps(dict(collection=str(COLLECTION),kits=[t['name'] for t in THEMES],assetsPerKit=25)))
if __name__=='__main__':build()

