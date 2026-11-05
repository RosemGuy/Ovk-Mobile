"""Draw original UI assets using the user's old VK screenshots as visual references."""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import random, math
ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'OpenVK'
def gradient(size, a, b):
    im=Image.new('RGB',size);d=ImageDraw.Draw(im)
    for y in range(size[1]):
        f=y/max(1,size[1]-1);d.line((0,y,size[0],y),fill=tuple(round(x*(1-f)+z*f) for x,z in zip(a,b)))
    return im
for s in (1,2):
    suffix='@2x' if s==2 else ''
    def save(im,name): im.save(P/(name+suffix+'.png'))
    for name,a,b,h in [('Navigation',(91,121,155),(39,65,98),44),('MenuRow',(44,51,64),(39,46,58),45),('MenuSelected',(54,133,218),(23,83,160),45),('MenuHeader',(49,57,70),(35,42,54),86),('ProfilePanel',(53,65,81),(32,42,55),250),('ProfileCounter',(42,54,70),(28,38,51),42),('SectionBar',(241,244,246),(210,217,223),34),('CellPanel',(255,255,255),(250,251,252),88)]:
        im=gradient((320*s,h*s),a,b);d=ImageDraw.Draw(im);d.line((0,0,320*s,0),fill=tuple(min(255,c+13) for c in a),width=s);d.line((0,(h-1)*s,320*s,(h-1)*s),fill=tuple(max(0,c-17) for c in b),width=s);save(im,name)
    im=Image.new('RGB',(64*s,64*s),(41,48,61));save(im,'SidebarTexture')
    # Subtle blue vignette, stretched as an image view rather than tiled.
    im=Image.new('RGB',(320*s,480*s));px=im.load();rng=random.Random(6)
    for y in range(im.height):
        for x in range(im.width):
            r=min(1,math.hypot((x/(320*s)-.45)*1.1,(y/(480*s)-.35)*.9));n=rng.choice((-1,0,0,1));px[x,y]=tuple(int(a*(1-r)+b*r)+n for a,b in zip((83,126,177),(34,61,108)))
    save(im,'LoginBackdrop')
    for name in ['News','Messages','Friends','Profile','Web','Settings','PhotoMedia','VideoMedia','AudioMedia','Menu']:
        im=Image.new('RGBA',(30*s,30*s));d=ImageDraw.Draw(im);c=(166,180,193,255);w=2*s
        if name in ['Friends','Profile']:
            for x,y,k in ([(15,8,1),(6,12,.72),(24,12,.72)] if name=='Friends' else [(15,8,1)]):
                d.ellipse(((x-4*k)*s,(y-5*k)*s,(x+4*k)*s,(y+3*k)*s),fill=c);d.polygon([((x-3*k)*s,(y+2*k)*s),((x+3*k)*s,(y+2*k)*s),((x+7*k)*s,(y+13*k)*s),((x-7*k)*s,(y+13*k)*s)],fill=c)
        elif name=='Messages':
            d.rectangle((4*s,7*s,26*s,23*s),fill=c);d.line((4*s,7*s,15*s,16*s,26*s,7*s),fill=(68,80,94),width=s)
        elif name=='News':
            d.ellipse((3*s,5*s,26*s,23*s),fill=c);d.polygon([(9*s,20*s),(8*s,27*s),(17*s,21*s)],fill=c)
        elif name=='PhotoMedia':
            d.rounded_rectangle((3*s,8*s,27*s,24*s),radius=2*s,fill=c);d.rectangle((8*s,5*s,15*s,9*s),fill=c);d.ellipse((10*s,10*s,22*s,22*s),fill=(65,78,92));d.ellipse((12*s,12*s,20*s,20*s),outline=c,width=s)
        elif name=='VideoMedia':
            d.rectangle((5*s,3*s,25*s,27*s),outline=c,width=2*s)
            for y in range(6,26,6):
                d.rectangle((6*s,y*s,8*s,(y+2)*s),fill=c);d.rectangle((22*s,y*s,24*s,(y+2)*s),fill=c)
            d.line((9*s,15*s,21*s,15*s),fill=c,width=s)
        elif name=='AudioMedia':
            d.line((12*s,23*s,12*s,7*s,25*s,4*s,25*s,20*s),fill=c,width=3*s);d.ellipse((4*s,20*s,13*s,27*s),fill=c);d.ellipse((17*s,17*s,26*s,24*s),fill=c)
        elif name=='Settings':
            for i in range(10):
                t=i*math.pi/5;d.line((15*s+8*s*math.cos(t),15*s+8*s*math.sin(t),15*s+13*s*math.cos(t),15*s+13*s*math.sin(t)),fill=c,width=4*s)
            d.ellipse((6*s,6*s,24*s,24*s),fill=c);d.ellipse((11*s,11*s,19*s,19*s),fill=(47,57,70))
        elif name=='Web':
            d.ellipse((3*s,3*s,27*s,27*s),outline=c,width=w);d.ellipse((10*s,3*s,20*s,27*s),outline=c,width=s);d.line((4*s,15*s,26*s,15*s),fill=c,width=s)
        else:
            for y in (8,15,22):d.line((5*s,y*s,25*s,y*s),fill=(242,247,252),width=2*s)
        # Small embossed shadow below the monochrome glyph.
        alpha=im.getchannel('A');shadow=Image.new('RGBA',im.size,(0,0,0,0));shadow.paste((0,0,0,130),(0,s),alpha.crop((0,0,im.width,im.height-s)));shadow.alpha_composite(im);save(shadow,name)
    # Small stretchable controls with fixed rounded edges, no stretched outlines.
    for name,top,bottom,w,h in [('NavButton',(112,145,181),(51,83,121),60,30),('NavButtonPressed',(54,83,119),(81,112,150),60,30),('LoginButton',(113,150,189),(51,88,131),60,42),('FooterButton',(251,252,253),(217,225,233),60,42),('BubbleIncoming',(255,255,255),(231,237,243),42,40),('BubbleOutgoing',(225,240,255),(175,204,233),42,40)]:
        im=gradient((w*s,h*s),top,bottom).convert('RGBA');mask=Image.new('L',im.size);md=ImageDraw.Draw(mask);md.rounded_rectangle((s,s,(w-1)*s,(h-1)*s),radius=5*s,fill=255);im.putalpha(mask);d=ImageDraw.Draw(im);d.rounded_rectangle((s,s,(w-1)*s,(h-1)*s),radius=5*s,outline=(31,54,82,230) if 'Button' in name and name!='FooterButton' else (159,177,194,255),width=s);d.line((6*s,2*s,(w-6)*s,2*s),fill=(255,255,255,120),width=s);save(im,name)
