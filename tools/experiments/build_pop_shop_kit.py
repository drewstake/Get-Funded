from pathlib import Path
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui-kits/Collections/04 - Pop Shop'
ASSETS = OUT / 'assets'
for directory in [OUT, ASSETS / 'svg', ASSETS / 'png', ASSETS / 'fonts']:
    directory.mkdir(parents=True, exist_ok=True)

INK = '#171436'
icons = {}
icons['cash'] = '''<path d="M25 76 113 25 216 62 216 139 118 197 25 155Z" fill="#07963c"/><path d="m25 76 94 40 97-54-103-37Z" fill="#45e751"/><path d="m119 116 97-54v77l-98 58Z" fill="#13bb43"/><path d="m43 77 71-37 77 24-73 40Z" fill="#14b940" stroke="none"/><path d="m72 55 95 40v73l-43 26v-75L35 84Z" fill="#ffbd20"/><path d="m72 55 31-17 98 33-34 24Z" fill="#ffe252"/><path d="m35 123 34 14m83-4 42-23m-42 48 42-24" fill="none" stroke="#087a39" stroke-width="7"/><path d="m162 96 18 4-15 12Z" fill="white" stroke="none"/>'''
icons['rebirth'] = '''<path d="M39 93Q53 28 125 35q27 3 43 20l14-20 29 77-84-4 18-24q-44-26-67 34Z" fill="#ee245b"/><path d="m49 90 25-26-9 40Z" fill="white" stroke="none"/><path d="m104 43 42 10-39 52-28 8Z" fill="#ff4272" stroke="none"/><path d="M201 151q-15 60-83 55-30-1-49-20l-13 18-31-77 83 4-19 23q47 29 71-29Z" fill="#c9f8ff"/><path d="m185 155-23 28 8-41Z" fill="white" stroke="none"/><path d="m117 167 27-3-26 33-30-7Z" fill="#8edee9" stroke="none"/>'''
icons['speed'] = '''<path d="m47 36 23-7q16 32 49 12l15-5 20 68 32 22q26 4 31 30l-3 32q-39 12-77-2l-35-24-64-11q-22-8-18-29Z" fill="#f42c61"/><path d="m30 100 45 16 39 39q40 36 101 15l-1 18q-40 14-78-2l-35-24-64-11q-19-6-18-28Z" fill="#c4f3f8"/><path d="m51 39 18-8q17 29 49 13l12-6 5 20q-54 21-84-19Z" fill="white" stroke="none"/><path d="m126 90 23-7m-14 26 25-7m-13 25 22-7" stroke="#a61244" stroke-width="12"/><path d="M27 137q29-4 56 15l39 29q47 27 92 8" fill="none" stroke="#77cbdc" stroke-width="10"/>'''
icons['time'] = '''<circle cx="120" cy="124" r="95" fill="#ffd52c"/><circle cx="120" cy="124" r="72" fill="#ff9234" stroke="none"/><circle cx="120" cy="124" r="56" fill="#d8faff" stroke="none"/><path d="M120 76v13m0 70v13m-48-48h13m70 0h13" stroke="#ff9234" stroke-width="10"/><path d="M120 104v20H99" fill="none" stroke-width="10"/><circle cx="120" cy="124" r="11" fill="#ff9234" stroke="none"/><path d="m63 66 11-8" stroke="#fff69b" stroke-width="10"/>'''
icons['luck'] = '''<path d="M117 139q-63 32-83-9T65 76Q42 23 82 21q33-2 39 33 19-46 57-27 41 26 3 60 48 4 40 44-15 47-80 15l-14 60-26-6Z" fill="#52e633"/><path d="m76 55 44 70 51-65m-51 65-53-10m53 10 57-13" fill="none" stroke="#20b944" stroke-width="10"/><path d="M53 102q-17 19 3 31M153 41q22-10 29 9" fill="none" stroke="#baff88" stroke-width="9"/>'''
icons['shop'] = '''<path d="m31 91 24 112 130 4 29-116Z" fill="#f02861"/><path d="m31 91 88 31 95-31-91-29Z" fill="#ff4c7a"/><path d="m119 122 95-31-29 116-66-24Z" fill="#c9164e"/><path d="M71 100V54l88-22 1 56" fill="none" stroke-width="18"/><path d="M71 100V54l88-22 1 56" fill="none" stroke="#bceff6" stroke-width="8"/><path d="m50 121 14 46 32 12" fill="none" stroke="#ff829b" stroke-width="10"/>'''
icons['potion'] = '''<path d="M100 71V47h43v25q48 14 49 67 1 70-72 72-70-1-69-66 1-61 49-74Z" fill="#7fd9e9"/><path d="M76 136q48 16 95-1v23q-1 33-49 34-46-1-47-35Z" fill="#44bed9" stroke="none"/><rect x="99" y="25" width="45" height="32" rx="12" fill="#f73669"/><circle cx="138" cy="136" r="28" fill="#ff3f6c"/><path d="M83 101q-16 12-13 35" fill="none" stroke="#d2fbff" stroke-width="10"/>'''
icons['wheel'] = '''<circle cx="120" cy="120" r="97" fill="#74d6e7"/><circle cx="120" cy="120" r="76" fill="#ffe03b"/><path d="M120 44v76l54-54Z" fill="#72e94a" stroke="none"/><path d="m174 66-54 54h76Z" fill="#11be97" stroke="none"/><path d="M196 120h-76l54 54Z" fill="#42b7f2" stroke="none"/><path d="m174 174-54-54v76Z" fill="#9c68e8" stroke="none"/><path d="M120 196v-76l-54 54Z" fill="#f1426a" stroke="none"/><path d="m66 174 54-54H44Z" fill="#ff8436" stroke="none"/><circle cx="120" cy="120" r="14" fill="white"/><path d="m99 19 21 43 22-43Z" fill="#fff"/>'''
icons['pet'] = '''<path d="m36 73 24-34q7-15 19-2l17 29 40-1 26-32q11-11 19 4l14 38 8 114-81 25-85-26Z" fill="#ff9d39"/><path d="m39 158 83 23 79-22 2 30-81 25-85-26Z" fill="#f17a32" stroke="none"/><ellipse cx="85" cy="117" rx="18" ry="22" fill="white" stroke="none"/><ellipse cx="156" cy="117" rx="18" ry="22" fill="white" stroke="none"/><ellipse cx="89" cy="120" rx="10" ry="13" fill="#171436" stroke="none"/><ellipse cx="152" cy="120" rx="10" ry="13" fill="#171436" stroke="none"/><path d="m112 143 9 9 10-9m-10 9q-11 17-22 4m22-4q11 17 23 2" fill="none" stroke-width="6"/>'''
icons['codes'] = '''<path d="m29 71 166-34 20 118-54 12-16 31-101 8-18-29Z" fill="#f0fbff"/><path d="m45 87 6 92 72-4" fill="none" stroke="#a3d7e7" stroke-width="12"/><path d="m94 98-23 24 29 17m56-53 28 18-20 28m-26-43-18 48" fill="none" stroke-width="11"/>'''
icons['settings'] = '''<path d="m96 23 45 1 8 24 21 10 24-6 23 38-17 19v25l15 18-23 39-24-6-20 12-8 23H95l-8-23-21-12-24 6-23-39 17-18v-25L20 90l23-38 24 7 20-11Z" fill="#6fcde5"/><circle cx="119" cy="123" r="45" fill="#b9f0f9"/><circle cx="119" cy="123" r="32" fill="#71bddd" stroke="none"/><path d="m100 38-6 23-24 12" fill="none" stroke="#b7f5ff" stroke-width="8"/>'''
icons['gift'] = '''<path d="m43 93 155-1-6 104-73 20-70-26Z" fill="#f72f64"/><path d="m119 112 79-20-6 104-73 20Z" fill="#d91e57"/><path d="m92 90 48 2-2 117-35-5Z" fill="#ffd02e"/><path d="m30 74 89-24 91 24-6 37-85 22-86-24Z" fill="#ff4376"/><path d="m100 57 34 1 3 69-32 2Z" fill="#ffda37"/><path d="M119 66Q45 70 53 34q10-40 66 19 48-65 65-26 20 36-65 39Z" fill="#ffce25"/><path d="m119 65-37 52 2-40-31 4 39-32m27 16 41 46-4-39 30 1-43-28" fill="#ffa722" stroke="none"/><circle cx="119" cy="61" r="20" fill="#ffe047" stroke="none"/>'''
icons['upgrade'] = '''<path d="m28 119 90-101 90 100-51-3v93l-77 12V121Z" fill="#53e536"/><path d="m118 18 90 100-51-3v93l-32 5V78l-38 43-37 1Z" fill="#2ac448" stroke="none"/><path d="m56 112 56-68" stroke="#b0ff82" stroke-width="10" fill="none"/>'''
icons['boost'] = '''<path d="m111 29 85 34-48 51 34 24-99 80 11-64-55-6Z" fill="#ffcb29"/><path d="m119 100-25 54-11 64 99-80-34-24 48-51-33-13Z" fill="#ff9528" stroke="none"/><path d="m56 87 13-59 45 13 12-21 78 87-60 29-16-22-11 33Z" fill="#4ae338"/><path d="m125 22 79 85-60 29-16-22 11-46Z" fill="#22bc3e" stroke="none"/>'''
icons['gem'] = '''<path d="m25 81 42-46 105 1 43 47-95 128Z" fill="#3bbcff"/><path d="m25 81 68 5 27 125Zm190 2-68 3-27 125Z" fill="#1690e2" stroke="none"/><path d="m67 35 26 51 54 0 25-50Z" fill="#83e8ff" stroke="none"/><path d="m25 81 68 5 54 0 68-3M67 35l26 51 27 125 27-125 25-50" fill="none" stroke="#147cca" stroke-width="5"/><path d="m62 49-20 24 37 1Z" fill="#d9fbff" stroke="none"/>'''
icons['coin'] = '''<circle cx="120" cy="120" r="95" fill="#ffcf2f"/><circle cx="120" cy="120" r="72" fill="#ffe66a" stroke="#ee9f20" stroke-width="9"/><path d="M143 85q-40-23-47 4-6 21 24 29 38 8 23 32-12 22-49 2m25-88v112" fill="none" stroke="#efa124" stroke-width="14"/><path d="m54 69 14-14" stroke="#fff7c2" stroke-width="10"/>'''

def svg(body, width=240, height=240):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}"><g stroke="{INK}" stroke-width="9" stroke-linejoin="round" stroke-linecap="round">{body}</g></svg>'

for name, body in icons.items():
    (ASSETS / 'svg' / f'{name}.svg').write_text(svg(body), encoding='utf-8')

colors = {'cash':'#52e83e', 'rebirth':'#ff505f', 'speed':'#60f1e9', 'time':'#ffe04b', 'luck':'#8aef43'}
for name, color in colors.items():
    pattern = f'<defs><pattern id="check" width="80" height="80" patternUnits="userSpaceOnUse"><rect width="80" height="80" fill="{color}"/><path d="M0 0h40v40H0Zm40 40h40v40H40Z" fill="white" fill-opacity=".12"/></pattern></defs>'
    (ASSETS/'svg'/f'card-{name}.svg').write_text(svg(pattern+'<rect x="4" y="4" width="712" height="152" rx="25" fill="url(#check)" stroke-width="6"/>',720,160),encoding='utf-8')

for name, color in {'primary':'#ffda2c','success':'#57e83d','danger':'#ff5070','disabled':'#c5c9d7'}.items():
    (ASSETS/'svg'/f'button-{name}.svg').write_text(svg(f'<rect x="4" y="9" width="232" height="66" rx="25" fill="{INK}" stroke="none"/><rect x="4" y="4" width="232" height="65" rx="25" fill="{color}" stroke-width="6"/><path d="M26 16h185" stroke="white" stroke-opacity=".35" stroke-width="5"/>',240,80),encoding='utf-8')

(ASSETS/'svg'/'panel.svg').write_text(svg('<rect x="5" y="5" width="710" height="810" rx="40" fill="#fff" stroke-width="8"/>',720,820),encoding='utf-8')
(ASSETS/'svg'/'currency-chip.svg').write_text(svg('<rect x="4" y="4" width="232" height="64" rx="32" fill="#d5d9ef" stroke-width="6"/>',240,72),encoding='utf-8')

# Bundle the open-source typeface, so the preview works without a network connection.
font_dir = ASSETS/'fonts'
for name, url in {
    'LilitaOne-Regular.ttf':'https://raw.githubusercontent.com/google/fonts/main/ofl/lilitaone/LilitaOne-Regular.ttf',
    'OFL.txt':'https://raw.githubusercontent.com/google/fonts/main/ofl/lilitaone/OFL.txt',
}.items():
    if not (font_dir/name).exists():
        urllib.request.urlretrieve(url, font_dir/name)

tokens = {'name':'Pop Shop', 'colors':{'ink':INK,'paper':'#ffffff','header':'#f33443','primary':'#ffda2c',**colors},'outline':{'panel':6,'card':4,'icon':9},'radius':{'panel':34,'card':24,'button':24},'font':{'display':'Lilita One','body':'Trebuchet MS, Arial, sans-serif'},'spacing':[4,8,12,16,24,32,48], 'iconViewBox':[0,0,240,240]}
(OUT/'design-tokens.json').write_text(json.dumps(tokens,indent=2),encoding='utf-8')
(OUT/'icons.json').write_text(json.dumps([{'name':n,'svg':f'assets/svg/{n}.svg','png':f'assets/png/{n}.png','size':512} for n in icons],indent=2),encoding='utf-8')
print(f'Created {len(icons)} original icons and 11 component assets in {OUT}')
