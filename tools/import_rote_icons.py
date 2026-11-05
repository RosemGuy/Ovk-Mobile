"""Import only icon artwork from the user's RoteCode VK checkout (requires Pillow)."""
from pathlib import Path
import sys, shutil
from PIL import Image
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1]) if len(sys.argv)>1 else root.parent/'RoteCode VK'/'OpenVK Me'
assets=root/'OpenVK'
for src,dst in {'news':'News','friends':'Friends','messages':'Messages','settings':'Settings'}.items():
    for suffix in ('','@2x'):
        with Image.open(source/(src+suffix+'.png')) as original:
            rgba=original.convert('RGBA')
            # Preserve the source silhouette and antialiasing. Only recolor for the dark drawer.
            icon=Image.new('RGBA',rgba.size,(183,194,204,0));icon.putalpha(rgba.getchannel('A'))
            icon.save(assets/(dst+suffix+'.png'))
for suffix in ('','@2x'):
    shutil.copyfile(source/('icon'+suffix+'.png'),assets/('Icon'+suffix+'.png'))
# Existing Info.plist / project also reference iPad and iOS 7/10 icon sizes.
with Image.open(source/'icon@2x.png') as original:
    for name,size in [('Icon-60@2x',120),('Icon-72',72),('Icon-72@2x',144),('Icon-76',76),('Icon-76@2x',152)]:
        original.convert('RGBA').resize((size,size),Image.Resampling.LANCZOS).save(assets/(name+'.png'))
with Image.open(source/'siluette.png') as original:
    with Image.open(assets/'Avatar.png') as current: size=current.size
    original.convert('RGBA').resize(size,Image.Resampling.LANCZOS).save(assets/'Avatar.png')
print('Imported 4 menu icons (1x/2x), app icon (1x/2x), avatar placeholder')
