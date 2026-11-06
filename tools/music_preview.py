"""Illustrative layout of music UI from shipped assets, not a simulator screenshot."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[1];a=r/'OpenVK'
f='/usr/share/fonts/noto/NotoSans-Regular.ttf';fb='/usr/share/fonts/noto/NotoSans-Bold.ttf'
def txt(im,xy,s,size=13,color='#283a50',bold=False):ImageDraw.Draw(im).text(xy,s,font=ImageFont.truetype(fb if bold else f,size),fill=color)
def asset(im,name,xy,size=None):
 x=Image.open(a/(name+'.png')).convert('RGBA')
 if size:x=x.resize(size)
 im.paste(x,xy,x)
def screen(title,black=False):
 im=Image.new('RGB',(320,568),'#fff');d=ImageDraw.Draw(im);d.rectangle((0,0,320,20),fill='black');txt(im,(5,2),'Carrier',10,'white');txt(im,(140,2),'9:41',10,'white');asset(im,'MusicNavigation' if black else 'Navigation',(0,20),(320,44));txt(im,(110,31),title,17,'white',True);return im
local=screen('Музыка');d=ImageDraw.Draw(local);d.rounded_rectangle((10,72,310,102),radius=5,fill='#4f7299',outline='#365578');txt(local,(28,79),'На устройстве',12,'white',True);d.rounded_rectangle((160,73,309,101),radius=4,fill='#edf1f5');txt(local,(207,79),'OpenVK',12,'#50677f');txt(local,(18,116),'Музыка, сохранённая в приложении',12,'#888')
for i,(title,ext) in enumerate([('Первый трек','MP3'),('Вечерняя прогулка','M4A'),('Проверочный звук','WAV')]):
 y=150+i*70;asset(local,'AudioMedia',(12,y+18));txt(local,(64,y+12),title,14,bold=True);txt(local,(64,y+36),ext+' · на устройстве',11,'#8c96a2');d.line((10,y+69,310,y+69),fill='#d8dfe5')
txt(local,(20,403),'Передача файлов через iTunes',12,'#7b8899');txt(local,(20,426),'или «Открыть в Ovk-Mobile»',12,'#7b8899')
player=screen('',True);d=ImageDraw.Draw(player);txt(player,(110,21),'Исполнитель',10,'#bcbcbc');txt(player,(106,35),'Первый трек',12,'white',True);txt(player,(120,49),'Альбом',10,'#bcbcbc');txt(player,(10,33),'‹ Музыка',12,'white');txt(player,(259,33),'Сведения',10,'white');d.rectangle((0,64,320,568),fill='black');asset(player,'MusicCover',(0,64),(320,320));asset(player,'MusicPanel',(0,428),(320,140));d.line((20,446,300,446),fill='#6a6a6a',width=4);d.ellipse((64,438,80,454),fill='#dedede');txt(player,(117,462),'0:35 / 3:42',11,'#bbb')
for x,name in [(35,'PreviousTrack'),(142,'PauseTrack'),(249,'NextTrack')]:asset(player,name,(x,486))
d.line((30,547,290,547),fill='#999',width=5);d.ellipse((175,537,195,557),fill='#ddd')
settings=screen('Настройки');asset(settings,'Linen',(0,64),(320,504));txt(settings,(18,91),'ПРИЛОЖЕНИЕ',12,'#63758b',True)
for i,title in enumerate(['Ovk-Mobile alpha','Оформление','Экспериментальное']):
 y=119+i*54;ImageDraw.Draw(settings).rounded_rectangle((10,y,310,y+54),radius=5,fill='white',outline='#c9d0d8');txt(settings,(55 if i==2 else 22,y+16),title,14,bold=True)
 if i==2:asset(settings,'Experimental',(19,y+10));txt(settings,(291,y+14),'›',20,'#aaa')
exp=screen('Экспериментальное');asset(exp,'Linen',(0,64),(320,504));
for i,title in enumerate(['Видеозаписи','Музыка OpenVK']):
 y=110+i*54;ImageDraw.Draw(exp).rounded_rectangle((10,y,310,y+54),radius=5,fill='white',outline='#cbd2da');txt(exp,(22,y+17),title,14,bold=True);ImageDraw.Draw(exp).rounded_rectangle((230,y+13,296,y+41),radius=14,fill='#d1d5da',outline='#999');ImageDraw.Draw(exp).ellipse((231,y+14,257,y+40),fill='#fafafa',outline='#999')
txt(exp,(19,242),'Выключены по умолчанию.',12,'#748297');txt(exp,(19,266),'OpenVK появится вкладкой в музыке,',12,'#748297');txt(exp,(19,287),'видео — отдельным пунктом меню.',12,'#748297')
out=Image.new('RGB',(1380,650),'#e8edf3');txt(out,(22,12),'Ovk-Mobile alpha · Музыка, плеер и экспериментальные функции',20,bold=True)
for x,im in [(20,local),(360,player),(700,settings),(1040,exp)]:out.paste(im,(x,55));ImageDraw.Draw(out).rectangle((x-1,54,x+320,623),outline='#8799ac')
txt(out,(22,631),'Макет по ресурсам проекта, не снимок симулятора. Пример вкладки OpenVK после включения в настройках.',11,'#67798b');out.save(r/'Music-preview.png')
