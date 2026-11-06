from pathlib import Path
from PIL import Image,ImageDraw
import subprocess
r=Path(__file__).resolve().parents[1];a=r/'OpenVK'
for s in (1,2):
 suffix='@2x' if s==2 else ''
 for name,w,h,top,bottom in [('MusicNavigation',320,44,45,9),('MusicPanel',64,140,35,8),('MusicButton',60,30,57,19)]:
  im=Image.new('RGBA',(w*s,h*s));d=ImageDraw.Draw(im)
  for y in range(h*s):
   c=round(top+(bottom-top)*y/max(1,h*s-1));d.line((0,y,w*s,y),fill=(c,c,c,255))
  if name=='MusicButton':
   mask=Image.new('L',im.size);ImageDraw.Draw(mask).rounded_rectangle((s,s,(w-1)*s,(h-1)*s),radius=5*s,fill=255);im.putalpha(mask);d=ImageDraw.Draw(im);d.rounded_rectangle((s,s,(w-1)*s,(h-1)*s),radius=5*s,outline=(5,5,5),width=s);d.line((7*s,2*s,(w-7)*s,2*s),fill=(88,88,88),width=s)
  else:d.line((0,0,w*s,0),fill=(74,74,74),width=s);d.line((0,(h-1)*s,w*s,(h-1)*s),fill=(0,0,0),width=s)
  im.save(a/(name+suffix+'.png'))
source=r/'tools/icons/Experimental.svg';source.parent.mkdir(exist_ok=True)
source.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" viewBox="0 0 30 30"><path d="M11 4h8M13 4v9L5 25h20l-8-12V4M9 20h12" fill="none" stroke="#aebbc9" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>')
for s in (1,2):subprocess.run(['rsvg-convert','-w',str(30*s),'-h',str(30*s),'-o',str(a/('Experimental'+('@2x' if s==2 else '')+'.png')),str(source)],check=True)
