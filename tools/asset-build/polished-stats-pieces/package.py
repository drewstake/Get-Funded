from pathlib import Path
from zipfile import ZipFile,ZIP_DEFLATED
import json,re,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[3]
LIB=ROOT/'assets/ui-kits'
OUT=LIB/'Collections/06 - Polished Stats Pieces'
checks=[]
def check(name,fn):
 fn();checks.append(dict(name=name,passed=True))
def verify_models():
 module=(OUT/'roblox/StatsPieces.luau').read_text(encoding='utf-8')
 tree=ET.parse(OUT/'roblox/PolishedStatsPieces.rbxmx')
 folder=tree.getroot().find('Item')
 comp=next(x for x in folder.findall('Item')if x.find("Properties/string[@name='Name']").text=='Components')
 assert len(comp.findall('Item'))==31
 assert tree.find(".//Item[@class='ModuleScript']/Properties/ProtectedString[@name='Source']").text==module
 assert tree.find(".//Item[@class='LocalScript']/Properties/bool[@name='Disabled']").text=='true'
 for name in ['PolishedStatsPieces.rbxmx','AssembledPreview.rbxmx']:
  root=ET.parse(OUT/'roblox'/name).getroot()
  refs=[x.get('referent')for x in root.iter('Item')]
  assert all(refs)and len(refs)==len(set(refs))
 assembled=ET.parse(OUT/'roblox/AssembledPreview.rbxmx')
 assert assembled.find(".//Item[@class='ScreenGui']/Properties/bool[@name='Enabled']").text=='false'
 assert assembled.find(".//Item[@class='TextLabel']/Properties")is not None
def verify_checks():
 web=json.loads((OUT/'validation-results.json').read_text(encoding='utf-8'))
 native=json.loads((OUT/'roblox/validation-results.json').read_text(encoding='utf-8'))
 assert all(c['passed'] for c in web['checks'])
 assert all(c['passed'] for c in native['checks'])
 assert native['passed']==13
def verify_assets():
 assets=json.loads((OUT/'assets.json').read_text(encoding='utf-8'))
 for a in assets:
  assert (OUT/a['png']).is_file() and (OUT/a['svg']).is_file()
 for name in ['01-assembled.png','02-components.png','03-dropdown-open.png','04-artwork.png','index.html','README.md']:
  assert (OUT/name).is_file()
check('31 editable native components plus module and disabled example',verify_models)
check('All browser and Studio verification passed',verify_checks)
check('All preview and asset files exist',verify_assets)
(OUT/'package-validation.json').write_text(json.dumps(checks,indent=2),encoding='utf-8')
archive=LIB/'Downloads/06 - Polished Stats Pieces.zip'
with ZipFile(archive,'w',ZIP_DEFLATED) as z:
 for file in OUT.rglob('*'):
  if file.is_file():z.write(file,Path('Polished Stats Pieces')/file.relative_to(OUT))
with ZipFile(archive) as z:
 assert z.testzip()is None
 count=len(z.namelist())
gallery=LIB/'Browse UI Kits.html'
text=gallery.read_text(encoding='utf-8')
base='Collections/06%20-%20Polished%20Stats%20Pieces'
section=f'''<section id="polished-stats-pieces"><div class="section-header"><div><h2>Polished Stats Pieces<span class="count">Implementation pack</span></h2><p>The chosen Summary Banner design, split into editable Roblox components and separate PNG/SVG assets.</p></div><div class="actions"><a class="action" href="{base}/index.html">Browse pieces →</a><a class="action" href="Downloads/06%20-%20Polished%20Stats%20Pieces.zip" download>Download ZIP</a></div></div><div class="cards"><a class="card" href="{base}/index.html"><img src="{base}/01-assembled.png" alt="Polished stats assembled example"><div class="caption"><strong>Assembled example</strong><span>Open ↗</span></div></a><a class="card" href="{base}/02-components.png"><img src="{base}/02-components.png" style="object-fit:cover;object-position:top" alt="Editable card and dropdown components"><div class="caption"><strong>Native components</strong><span>View ↗</span></div></a><a class="card" href="{base}/04-artwork.png"><img src="{base}/04-artwork.png" style="object-fit:cover;object-position:top" alt="Separate transparent artwork"><div class="caption"><strong>31 artwork assets</strong><span>View ↗</span></div></a></div></section>'''
if 'id="polished-stats-pieces"'in text:text=re.sub(r'<section id="polished-stats-pieces">.*?</section>',lambda _:section,text,flags=re.S)
else:
 text=text.replace('<section id="stats-kits">',section+'\n<section id="stats-kits">')
 text=text.replace('</nav></header>','<a href="#polished-stats-pieces">Polished Stats · Pieces</a></nav></header>')
text=text.replace('Browse 28 concepts in five collections.','Browse 28 concepts and implementation assets in six collections.')
gallery.write_text(text,encoding='utf-8')
print(json.dumps(dict(archive=str(archive),files=count,bytes=archive.stat().st_size,checks=checks),indent=2))

