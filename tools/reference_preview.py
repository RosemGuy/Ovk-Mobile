"""Illustrative layout from project assets, not an iOS simulator screenshot."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[1];a=r/'OpenVK'
f='/usr/share/fonts/noto/NotoSans-Regular.ttf';fb='/usr/share/fonts/noto/NotoSans-Bold.ttf'
def text(im,xy,s,size=14,fill='#293c52',bold=False):ImageDraw.Draw(im).text(xy,s,font=ImageFont.truetype(fb if bold else f,size),fill=fill)
def paste(im,name,xy,size=None):
 asset=Image.open(a/(name+'.png')).convert('RGBA')
 if size:
  if name in ['NavButton','LoginButton','BubbleIncoming','BubbleOutgoing']:
   # Match UIKit cap insets: keep edges fixed, stretch the centre only.
   sw,sh=asset.size;dw,dh=size;cap=8;result=Image.new('RGBA',size)
   sx=[0,cap,sw-cap,sw];sy=[0,cap,sh-cap,sh];dx=[0,cap,dw-cap,dw];dy=[0,cap,dh-cap,dh]
   for row in range(3):
    for col in range(3):
     tile=asset.crop((sx[col],sy[row],sx[col+1],sy[row+1])).resize((dx[col+1]-dx[col],dy[row+1]-dy[row]));result.paste(tile,(dx[col],dy[row]))
   asset=result
  else:asset=asset.resize(size)
 im.paste(asset,xy,asset)
def base(title):
 im=Image.new('RGB',(320,568),'white');paste(im,'Linen',(0,0),(320,568));ImageDraw.Draw(im).rectangle((0,0,320,20),fill='#111');text(im,(6,1),'Carrier',11,'#ddd');text(im,(135,1),'9:41 PM',11,'white',True);paste(im,'Navigation',(0,20));paste(im,'NavButton',(6,27),(34,30));paste(im,'Menu',(8,27));text(im,(92,29),title,18,'white',True);return im
profile=base('Моя страница');paste(profile,'ProfilePanel',(0,64),(320,272));paste(profile,'DemoAlex',(8,74),(74,74));text(profile,(92,75),'Алексей Соколов',15,'white',True);text(profile,(92,111),'Online',11,'#adb8c7');text(profile,(92,127),'Хорошего дня!',11,'#adb8c7');paste(profile,'NavButton',(8,158),(304,30));text(profile,(115,165),'Фотографии',12,'white',True)
for i,title in enumerate(['ДРУЗЬЯ','ПОДПИСЧИКИ','ФОТОГРАФИИ','ВИДЕО','АУДИО','ГРУППЫ']):
 w=98;x=8+(i%3)*103;y=196+(i//3)*47;paste(profile,'ProfileCounter',(x,y),(w,42));text(profile,(x+40,y+1),'—',18,'#d9dfe7',True);font=ImageFont.truetype(fb,8);tw=ImageDraw.Draw(profile).textlength(title,font=font);text(profile,(x+(w-tw)/2,y+26),title,8,'#94a0ae',True)
paste(profile,'SectionBar',(0,298),(320,38));text(profile,(116,309),'Все записи',12,'#687787',True)
def post(im,y):
 paste(im,'CellPanel',(0,y),(320,230));paste(im,'DemoAlex',(10,y+10),(36,36));text(im,(56,y+8),'Алексей Соколов',13,bold=True);text(im,(56,y+30),'сегодня в 9:41',10,'#8893a0');text(im,(10,y+56),'Старый добрый интерфейс.',14);paste(im,'DemoPhoto',(10,y+86),(300,110));text(im,(10,y+207),'Комментарии 2',11,'#7b8c9f');text(im,(270,y+207),'♥ 6',11,'#4f7299')
post(profile,336)
menu=Image.new('RGB',(320,568),'#29303d');paste(menu,'MenuHeader',(0,20),(265,86));paste(menu,'DemoAlex',(15,40),(45,45));text(menu,(73,40),'Алексей Соколов',15,'white',True);text(menu,(73,68),'Демонстрация',11,'#aeb9c7')
for i,(icon,title) in enumerate([('Friends','Друзья'),('PhotoMedia','Фотографии'),('Messages','Сообщения'),('News','Новости'),('Profile','Моя страница'),('AudioMedia','Аудиозаписи'),('VideoMedia','Видеозаписи'),('Web','Сайт инстанса'),('Settings','Настройки')]):
 y=106+i*45;paste(menu,'MenuSelected' if i==5 else 'MenuRow',(0,y),(265,45));paste(menu,icon,(10,y+7));text(menu,(52,y+10),title,17,'#e1e7ef',True)
menu.paste(profile,(265,0));ImageDraw.Draw(menu).rectangle((0,0,265,20),fill='#111');text(menu,(6,1),'Carrier',11,'white');text(menu,(115,1),'9:41 PM',11,'white',True)
feed=base('Новости');paste(feed,'SectionBar',(0,64),(320,34));text(feed,(55,74),'Потяните вниз для обновления',11,'#768597');post(feed,98);post(feed,328)
chat=base('Анна');ImageDraw.Draw(chat).rectangle((0,64,320,568),fill='#e0e8ef')
for x,y,w,h,out,lines,stamp in [(48,90,232,105,False,['Привет! Нашла фотографии.','Посмотри, какие красивые.'],'9:41'),(116,210,194,68,True,['Спасибо! Сейчас посмотрю.'],'9:42'),(48,300,232,217,False,['Вот одна из них.'],'9:43')]:
 paste(chat,'BubbleOutgoing' if out else 'BubbleIncoming',(x,y),(w,h));
 if not out:paste(chat,'DemoAnna',(8,y+h-32),(30,30))
 for j,line in enumerate(lines):text(chat,(x+11,y+10+20*j),line,13)
 if h>200:paste(chat,'DemoPhoto',(x+8,y+40),(w-16,145))
 text(chat,(x+w-40,y+h-22),stamp,10,'#8090a0')
out=Image.new('RGB',(1380,650),'#e8edf3');text(out,(22,12),'OpenVK Classic 1.11 · меню, профиль, лента и сообщения',20,bold=True)
for x,im in [(20,menu),(360,profile),(700,feed),(1040,chat)]:out.paste(im,(x,55));ImageDraw.Draw(out).rectangle((x-1,54,x+320,623),outline='#899aad')
text(out,(22,630),'Иллюстративный макет: это не снимок симулятора. Реальные данные и отображение зависят от сервера и устройства.',12,'#667484');out.save(r/'Style-preview.png')
