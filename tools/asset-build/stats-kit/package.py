from pathlib import Path
import json,re
from zipfile import ZipFile,ZIP_DEFLATED
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
LIB=ROOT/'assets/ui-kits'
COL=LIB/'Collections/05 - Stats Collection'
DOWNLOADS=LIB/'Downloads'
themes=json.loads((COL/'themes.json').read_text(encoding='utf-8'))
gallery=LIB/'Browse UI Kits.html'
text=gallery.read_text(encoding='utf-8')
cards=''.join(f'''<a class="card" href="Collections/05%20-%20Stats%20Collection/{t['folder']}/index.html"><img src="Collections/05%20-%20Stats%20Collection/{t['folder']}/01-desktop.png" alt="{t['name']} stats UI kit with desktop, mobile and reusable components"><div class="caption"><strong>{t['name']}</strong><span>Open kit ↗</span></div></a>''' for t in themes)
section=f'''<section id="stats-kits"><div class="section-header"><div><h2>Stats Collection<span class="count">3 complete UI kits</span></h2><p>Polished Game, Dark Focus and Bright Minimal. SVG + PNG assets, responsive previews and native Roblox components.</p></div><div class="actions"><a class="action" href="Collections/05%20-%20Stats%20Collection/index.html">Compare all three →</a><a class="action" href="Downloads/05%20-%20Stats%20Collection%20-%20All%20Three.zip" download>Download all kits</a></div></div><div class="cards">{cards}</div></section>'''
if 'id="stats-kits"' in text:text=re.sub(r'<section id="stats-kits">.*?</section>',lambda _:section,text,flags=re.S)
else:
 text=text.replace('<section id="pop-shop">',section+'\n<section id="pop-shop">')
 text=text.replace('</nav></header>','<a href="#stats-kits">Stats Collection · 3 new kits</a></nav></header>')
text=text.replace('Browse 25 concepts in four collections.','Browse 28 concepts in five collections.')
text=text.replace('25 UI concepts','28 UI concepts')
text=text.replace('Design previews + reusable Pop Shop assets','Design previews + reusable Shop and Stats assets')
gallery.write_text(text,encoding='utf-8')

DOWNLOADS.mkdir(exist_ok=True)
checks=[]
for t in themes:
 folder=COL/t['folder']
 model=ET.parse(folder/'roblox/StatsKit.rbxmx')
 script_items=model.findall('.//Item')
 assert len(script_items)==3
 assert model.find('.//Item[@class="LocalScript"]/Properties/bool[@name="Disabled"]').text=='true'
 assert model.find('.//Item[@class="ModuleScript"]/Properties/ProtectedString').text==(folder/'roblox/StatsKit.luau').read_text(encoding='utf-8')
 data=json.loads((folder/'validation-results.json').read_text(encoding='utf-8'))
 assert all(c['passed'] for c in data['checks'])
 assert (folder/'roblox/validation-results.json').exists()
 archive=DOWNLOADS/f"05 - Stats - {t['name']}.zip"
 prefix=Path(t['name']+' Stats Kit')
 landing=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{t['name']} Stats Kit</title><style>body{{max-width:960px;margin:48px auto;padding:24px;background:#0b1220;color:#f1f5fc;font:17px/1.6 system-ui}}a{{color:#c7b0ff}}img{{width:100%;border-radius:16px}}h1{{font-size:42px}}</style></head><body><p>Get Funded! · Standalone UI kit</p><h1>{t['name']}</h1><p>{t['description']}</p><p><a href="{t['folder']}/index.html">Open interactive kit →</a> · <a href="{t['folder']}/README.md">Read integration notes</a></p><a href="{t['folder']}/index.html"><img src="{t['folder']}/01-desktop.png" alt="{t['name']} preview"></a><p>This download contains the {t['name']} kit. The complete Stats Collection download contains all three designs.</p></body></html>'''
 with ZipFile(archive,'w',ZIP_DEFLATED) as z:
  z.writestr((prefix/'index.html').as_posix(),landing)
  for f in folder.rglob('*'):
   if f.is_file():
    content=f.read_bytes()
    if f.name=='index.html':content=content.replace(b'All three kits',b'Kit collection')
    z.writestr((prefix/t['folder']/f.relative_to(folder)).as_posix(),content)
 with ZipFile(archive) as z:
  assert z.testzip() is None
  checks.append(dict(archive=archive.name,files=len(z.namelist()),bytes=archive.stat().st_size,valid=True))
full=DOWNLOADS/'05 - Stats Collection - All Three.zip'
with ZipFile(full,'w',ZIP_DEFLATED) as z:
 for f in COL.rglob('*'):
  if not f.is_file():continue
  content=f.read_bytes()
  if f==COL/'index.html':
   h=content.decode('utf-8')
   h=h.replace('href="../../Browse UI Kits.html">← All UI kits','href="README.md">Collection notes')
   for t in themes:h=h.replace(f'href="../../Downloads/05 - Stats - {t["name"]}.zip" download>Download ZIP',f'href="{t["folder"]}/README.md">Integration notes')
   h=h.replace('href="../../Downloads/05 - Stats Collection - All Three.zip" download>Download all three kits','href="README.md">All three kits included')
   content=h.encode('utf-8')
  z.writestr((Path('Stats Collection')/f.relative_to(COL)).as_posix(),content)
with ZipFile(full) as z:
 assert z.testzip() is None
 checks.append(dict(archive=full.name,files=len(z.namelist()),bytes=full.stat().st_size,valid=True))
(COL/'package-validation.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
print(json.dumps(checks,indent=2))

