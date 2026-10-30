from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
library = root / 'assets/ui-kits'
kit = library / 'Collections/04 - Pop Shop'
gallery = library / 'Browse UI Kits.html'
html = gallery.read_text(encoding='utf-8')
if 'id="pop-shop"' not in html:
    html = html.replace('Browse 24 concepts in three collections.', 'Browse 25 concepts in four collections.')
    html = html.replace('<span>Design previews only</span>', '<span>Design previews + reusable Pop Shop assets</span>')
    html = html.replace('</nav></header>', '<a href="#pop-shop">Pop Shop &middot; New kit</a></nav></header>')
    section = '''<section id="pop-shop"><div class="section-header"><div><h2>Pop Shop<span class="count">New reference-inspired kit</span></h2><p>Bold simulator shop, 16 original icons, and reusable SVG + PNG components.</p></div><div class="actions"><a class="action" href="Collections/04%20-%20Pop%20Shop/index.html">Open interactive kit &rarr;</a><a class="action" href="Downloads/04%20-%20Pop%20Shop.zip" download>Download ZIP</a></div></div><div class="cards"><a class="card" href="Collections/04%20-%20Pop%20Shop/index.html"><img src="Collections/04%20-%20Pop%20Shop/01-shop-preview.png" alt="Pop Shop with red header, bright checkerboard upgrade cards, and colorful sidebar icons"><div class="caption"><strong>Pop Shop</strong><span>Open kit &nearr;</span></div></a><a class="card" href="Collections/04%20-%20Pop%20Shop/00-kit-board.png" target="_blank" rel="noopener"><img src="Collections/04%20-%20Pop%20Shop/00-kit-board.png" alt="Full Pop Shop design board" style="object-fit:cover;object-position:top"><div class="caption"><strong>Component board</strong><span>View board &nearr;</span></div></a><a class="card" href="Collections/04%20-%20Pop%20Shop/assets/icons-atlas.png" target="_blank" rel="noopener"><img src="Collections/04%20-%20Pop%20Shop/assets/icons-atlas.png" alt="Sixteen transparent cartoon game icons" style="background:#dbeef0"><div class="caption"><strong>Icon collection</strong><span>View assets &nearr;</span></div></a></div></section>\n'''
    html = html.replace('<section id="premium">', section + '<section id="premium">')
    html = html.replace('24 UI concepts', '25 UI concepts')
    gallery.write_text(html, encoding='utf-8')

archive = library/'Downloads/04 - Pop Shop.zip'
with ZipFile(archive, 'w', ZIP_DEFLATED) as z:
    for file in kit.rglob('*'):
        if file.is_file() and file.name != 'debug.png':
            z.write(file, Path('Pop Shop')/file.relative_to(kit))
with ZipFile(archive) as z:
    assert z.testzip() is None
    print(f'Packaged {len(z.namelist())} files; {archive.stat().st_size:,} bytes: {archive}')
