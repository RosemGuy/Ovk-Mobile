"""Lay out existing UI assets for the legacy iOS 6 Default launch images.
The logo and backdrop sources are preserved; no artwork is regenerated.
"""
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'OpenVK'
SIZES = {
    'Default.png': (320, 480, 1),
    'Default@2x.png': (640, 960, 2),
    'Default-568h@2x.png': (640, 1136, 2),
    'Default-Landscape~ipad.png': (1024, 748, 1),
    'Default-Landscape@2x~ipad.png': (2048, 1496, 2),
    'Default-Portrait~ipad.png': (768, 1004, 1),
    'Default-Portrait@2x~ipad.png': (1536, 2008, 2),
}

def main():
    backdrop = Image.open(ASSETS / 'LoginBackdrop@2x.png').convert('RGB')
    logo = Image.open(ASSETS / 'Avatar.png').convert('RGBA')
    for name, (width, height, scale) in SIZES.items():
        canvas = backdrop.resize((width, height), Image.Resampling.LANCZOS).convert('RGBA')
        # Same 96pt mark as the login screen; retain its transparent source.
        size = 96 * scale
        mark = logo.resize((size, size), Image.Resampling.LANCZOS)
        canvas.alpha_composite(mark, ((width-size)//2, (height-size)//2))
        canvas.convert('RGB').save(ASSETS / name, optimize=True)
        print(name, width, height)

if __name__ == '__main__':
    main()
