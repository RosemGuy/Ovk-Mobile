"""Illustrative preview from project assets; not a captured iOS screen."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
r=Path(__file__).resolve().parents[1];a=r/'OpenVK';f='/usr/share/fonts/noto/NotoSans-Regular.ttf';fb='/usr/share/fonts/noto/NotoSans-Bold.ttf'
def text(im,xy,s,size=13,color='#283c51',bold=False):ImageDraw.Draw(im).text(xy,s,font=ImageFont.truetype(fb if bold else f,size),fill=color)
def art(im,name,xy,size=None):
 asset=Image.open(a/(name+'.png')).convert('RGBA')
 if size:
  if name in ['NavButton','FooterButton']:
   sw,sh=asset.size;dw,dh=size;cap=6;result=Image.new('RGBA',size);sx=[0,cap,sw-cap,sw];sy=[0,cap,sh-cap,sh];dx=[0,cap,dw-cap,dw];dy=[0,cap,dh-cap,dh]
   for row in range(3):
    for col in range(3):result.paste(asset.crop((sx[col],sy[row],sx[col+1],sy[row+1])).resize((dx[col+1]-dx[col],dy[row+1]-dy[row])),(dx[col],dy[row]))
   asset=result
  else:asset=asset.resize(size)
 im.paste(asset,xy,asset)
def base(title,black=False):
 im=Image.new('RGB',(320,568),'white');d=ImageDraw.Draw(im);d.rectangle((0,0,320,20),fill='black');text(im,(5,2),'Carrier',10,'white');text(im,(140,2),'9:41',10,'white');art(im,'MusicNavigation' if black else 'Navigation',(0,20),(320,44));text(im,(87,31),title,17,'white',True);return im
def post(im,y):
 d=ImageDraw.Draw(im);d.rectangle((0,y,320,y+50),fill='#ebf1f5');art(im,'DemoAnna',(8,y+7),(36,36));text(im,(53,y+6),'Анна Морозова',13,bold=True);text(im,(53,y+29),'сегодня в 9:41',10,'#8c99a5');text(im,(8,y+57),'Несколько фотографий с прогулки.',13);art(im,'DemoPhoto',(0,y+84),(202,200));art(im,'DemoPhoto',(205,y+84),(115,98));art(im,'DemoPhoto',(205,y+185),(115,99));d.rectangle((0,y+288,320,y+324),fill='#f5f7f9');text(im,(10,y+298),'Ответить · 2',11,'#4f7299');text(im,(278,y+298),'♥ 6',11,'#4f7299')
feed=base('Новости');art(feed,'SectionBar',(0,64),(320,34));text(feed,(71,74),'Потяните для обновления',11,'#748496');art(feed,'ComposeGlyph',(288,30),(23,23));post(feed,98)
profile=base('Профиль     Информация');art(profile,'ProfilePanel',(0,64),(320,332));art(profile,'DemoAlex',(8,74),(80,80));text(profile,(100,76),'Алексей Соколов',14,'white',True);text(profile,(100,114),'В сети · Москва',11,'#b6c1ce');text(profile,(100,132),'Хорошего дня!',11,'#b6c1ce')
for x,title,name in [(8,'Новая запись','NavButton'),(162,'Информация','FooterButton')]:art(profile,name,(x,164),(150,30));text(profile,(x+27,172),title,11,'white' if x==8 else '#384b5e',True)
for i,(number,title) in enumerate([('42','ДРУЗЬЯ'),('—','ОБЩИЕ'),('—','ПОДПИСЧИКИ'),('18','ФОТОГРАФИИ'),('—','ВИДЕО'),('—','АУДИО')]):
 x=8+(i%3)*103;y=202+(i//3)*45;art(profile,'ProfileCounter',(x,y),(98,40));text(profile,(x+36,y+1),number,18,'#dce2e9',True);font=ImageFont.truetype(fb,8);tw=ImageDraw.Draw(profile).textlength(title,font=font);text(profile,(x+(98-tw)/2,y+25),title,8,'#929da9',True)
for i in range(4):art(profile,'DemoPhoto',(8+i*77,298),(73,58))
art(profile,'SectionBar',(0,362),(320,36));text(profile,(16,373),'Все записи     Записи автора',11,'#526b85');art(profile,'ComposeGlyph',(286,368),(23,23));post(profile,398)
comments=base('Комментарии');text(comments,(256,35),'Ответить',11,'white');art(comments,'SectionBar',(0,64),(320,44));text(comments,(106,79),'Комментариев: 2',11,'#7b8795')
for y,name,body,reply in [(118,'Анна Морозова','Очень красиво! Где это снято?',False),(222,'Алексей Соколов','Недалеко от дома, на прогулке.',True)]:
 art(comments,'DemoAnna' if not reply else 'DemoAlex',(8,y),(42,42));text(comments,(60,y),name,13,bold=True);text(comments,(60,y+29),body,12);text(comments,(60,y+55),'сегодня в 9:41'+(' · ответ' if reply else ''),10,'#8c96a2');ImageDraw.Draw(comments).line((8,y+88,312,y+88),fill='#dce2e8')
editor=base('Новая запись',True);text(editor,(8,34),'Отмена',11,'white');art(editor,'NavButton',(225,27),(88,30));text(editor,(232,36),'Опубликовать',10,'white',True);text(editor,(8,82),'Сегодня отличный день для прогулки.',13);text(editor,(8,105),'Делюсь новостями с друзьями.',13)
art(editor,'SectionBar',(0,335),(320,38));text(editor,(265,348),'Готово',11,'#4f7299',True);ImageDraw.Draw(editor).rectangle((0,373,320,568),fill='#bdc5cf')
for row,letters in enumerate(['Й Ц У К Е Н Г Ш Щ З','Ф Ы В А П Р О Л Д Ж','Я Ч С М И Т Ь Б Ю']):
 for col,ch in enumerate(letters.split()):
  x=4+col*31+(0 if row<2 else 15);y=382+row*43;ImageDraw.Draw(editor).rounded_rectangle((x,y,x+27,y+36),radius=4,fill='#f7f8fa',outline='#919ba8');text(editor,(x+7,y+8),ch,15,'#171b20')
ImageDraw.Draw(editor).rounded_rectangle((76,515,250,554),radius=5,fill='#f7f8fa',outline='#8d98a6');text(editor,(139,528),'Пробел',12,'#465466')
out=Image.new('RGB',(1380,650),'#e8edf3');text(out,(22,12),'Ovk-Mobile alpha · лента, профиль, комментарии и редактор записи',20,bold=True)
for x,im in [(20,feed),(360,profile),(700,comments),(1040,editor)]:out.paste(im,(x,55));ImageDraw.Draw(out).rectangle((x-1,54,x+320,623),outline='#8798aa')
text(out,(22,631),'Иллюстративный макет по ресурсам проекта, не скриншот запущенного приложения.',11,'#6e7f91');out.save(r/'Feed-profile-preview.png')
