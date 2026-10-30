"""Export the two installed UI modules as a reusable native Roblox model."""
import sys
from pathlib import Path
sys.path.insert(0, str(next(p for p in Path(__file__).resolve().parents if (p / 'build/place-manifest.json').is_file()) / 'tools'))
from source_paths import source_file
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
document = ET.Element('roblox', version='4')
for index, name in enumerate(('ProgressView', 'TerminalUI')):
    item = ET.SubElement(document, 'Item', {'class': 'ModuleScript', 'referent': f'RBX{index}'})
    props = ET.SubElement(item, 'Properties')
    ET.SubElement(props, 'string', name='Name').text = name
    ET.SubElement(props, 'ProtectedString', name='Source').text = (source_file(root, f'{name}.luau')).read_text(encoding='utf-8')
destination = root / 'assets/progress-concepts/Progress UI Modules.rbxmx'
ET.ElementTree(document).write(destination, encoding='utf-8', xml_declaration=True)
saved = ET.parse(destination).getroot()
for item in saved.findall('Item'):
    props = item.find('Properties')
    name = props.find("string[@name='Name']").text
    assert props.find("ProtectedString[@name='Source']").text == (source_file(root, f'{name}.luau')).read_text(encoding='utf-8')
print(f'Verified native module export: {destination}')
