"""Validate stretch regions against actual 1x/2x artwork and import hashes."""
from pathlib import Path
import hashlib
import json
from PIL import Image
root=Path(__file__).resolve().parents[1]
assets=root/'OpenVK'
caps=json.loads((assets/'ChromeCaps.json').read_text())
manifest=json.loads((root/'tools/vk-ipa-assets.json').read_text())['files']
for name,values in caps.items():
    assert len(values)==4 and all(isinstance(x,(int,float)) and x>=0 for x in values),name
    top,left,bottom,right=values
    one=Image.open(assets/(name+'.png'))
    two=Image.open(assets/(name+'@2x.png'))
    assert two.size==(2*one.width,2*one.height),(name,one.size,two.size)
    assert left+right<one.width and top+bottom<one.height,(name,values,one.size)
for name,entry in manifest.items():
    data=(assets/name).read_bytes()
    assert hashlib.sha256(data).hexdigest()==entry['sha256'],name
    assert list(Image.open(assets/name).size)==entry['size'],name
assert Image.open(assets/'ProfilePanel.png').size==(64,64)
assert Image.open(assets/'FooterButton.png').height==33
assert Image.open(assets/'ProfileCounter.png').height==46
assert Image.open(assets/'LoginField.png').height==44
print(f'PASS: {len(caps)} stretch regions, Retina pairs and {len(manifest)} original-asset hashes')
