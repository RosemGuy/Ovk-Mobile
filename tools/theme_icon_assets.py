"""Recolor existing app icons for alternate themes; retain the original logo."""
from pathlib import Path
import colorsys
import plistlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
ASSETS=ROOT/'OpenVK'
COLORS={'purple':(.47,.30,.67),'red':(.70,.24,.25),'green':(.23,.50,.36),'orange':(.73,.39,.15),'pink':(.68,.29,.50)}
SIZES={'60@2x':(120,'Icon-60@2x.png'),'60@3x':(180,'Icon-60@2x.png'),'76':(76,'Icon-76.png'),'76@2x':(152,'Icon-76@2x.png'),'83.5@2x':(167,'Icon-76@2x.png')}

def main():
    base_h,base_s,base_v=colorsys.rgb_to_hsv(.31,.45,.60)
    for color,rgb in COLORS.items():
        hue,saturation,value=colorsys.rgb_to_hsv(*rgb)
        for suffix,(edge,source) in SIZES.items():
            image=Image.open(ASSETS/source).convert('RGBA').resize((edge,edge),Image.Resampling.LANCZOS)
            pixels=[]
            for r,g,b,a in image.getdata():
                h,s,v=colorsys.rgb_to_hsv(r/255,g/255,b/255)
                # Neutral logo, highlights and border remain unchanged.
                if s>.15:
                    r,g,b=colorsys.hsv_to_rgb((h+ hue-base_h)%1,min(1,s*saturation/base_s),min(1,v*value/base_v))
                    r,g,b=round(r*255),round(g*255),round(b*255)
                pixels.append((r,g,b,a))
            image.putdata(pixels);image.save(ASSETS/f'Theme-{color}-{suffix}.png',optimize=True)
    path=ASSETS/'Info.plist';info=plistlib.loads(path.read_bytes())
    for key,files in [('CFBundleIcons',['60']),('CFBundleIcons~ipad',['76','83.5'])]:
        info[key]['CFBundleAlternateIcons']={f'Theme-{color}':{'CFBundleIconFiles':[f'Theme-{color}-{size}' for size in files],'UIPrerenderedIcon':True} for color in COLORS}
    path.write_bytes(plistlib.dumps(info,sort_keys=False))
    print('Generated five color variants from existing icons; alternate icon metadata updated.')
if __name__=='__main__':main()
