"""Import selected legacy GUI assets from the user-provided IPA; exclude branding.
Decode Apple CgBI BGRA/premultiplied PNGs to standard RGBA PNGs.
"""
from pathlib import Path
from zipfile import ZipFile
from PIL import Image
import io,struct,zlib,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'VK_2_0.ipa'
MAP={
 'Navigation':'blue_header','NavButton':'blue_btn_nav','NavButtonPressed':'blue_btn_nav_hl',
 'BackButton':'blue_back_btn_nav','BackButtonPressed':'blue_back_btn_nav_hl',
 'MusicRepeat':'audioplayer_replay','MusicRepeatActive':'audioplayer_replay_hl','MusicShuffle':'audioplayer_shuffle','MusicShuffleActive':'audioplayer_shuffle_hl',
 'MusicNavigation':'black_header','MusicButton':'black_btn_nav','MusicButtonPressed':'black_btn_nav_hl',
 'ProfilePanel':'wall_background',
 'Answers':'left_answers','Groups':'left_groups','GroupPlaceholder':'group_placeholder_50px',
 'News':'left_news','Friends':'left_friends','Messages':'left_messages','Settings':'left_settings',
 'PhotoMedia':'left_photos','AudioMedia':'left_audio','VideoMedia':'left_videos','Profile':'left_wall',
 'Menu':'menu_icon','MenuRow':'left_cell','MenuSelected':'menu_cell_hl',
 'LoginButton':'login_btn','LoginButtonPressed':'login_btn_hl',
 'ProfileBlueButton':'wall_blue_btn','ProfileBlueButtonPressed':'wall_blue_btn_hl',
 'FooterButton':'wall_gray_btn','FooterButtonPressed':'wall_gray_btn_hl',
 'ProfileCounter':'wall_block','ProfileCounterPressed':'wall_block_hl',
 'BubbleIncoming':'Grey_Bubble','BubbleOutgoing':'Blue_Bubble',
 'ComposeGlyph':'newpost_icon','PlayTrack':'audioplayer_play','PauseTrack':'audioplayer_pause',
 'NextTrack':'audioplayer_next','PreviousTrack':'audioplayer_previous',
 'MessageBar':'MessageEntryBackground','MessageField':'MessageEntryInputField',
 'SendButton':'send_button','SendButtonPressed':'send_button_hl',
 'PostComment':'post_btn_comment','PostLike':'post_btn_like',
 'PostHeader':'news_post_header','PostButton':'post_detail_btn','PostButtonPressed':'post_detail_btn_hl',
 'ProfileTabs':'wall_posts_panel','LoginField':'new_login_field',
}
def decode(data):
 if b'CgBI' not in data[:40]:
  image=Image.open(io.BytesIO(data));image.load();return image.convert('RGBA')
 chunks=[];pos=8
 while pos<len(data):
  size=struct.unpack_from('>I',data,pos)[0];kind=data[pos+4:pos+8];payload=data[pos+8:pos+8+size];chunks.append((kind,payload));pos+=12+size
  if kind==b'IEND':break
 header=next(p for k,p in chunks if k==b'IHDR');w,h,depth,color,comp,filt,interlace=struct.unpack('>IIBBBBB',header)
 assert depth==8 and color in (2,6) and interlace==0,(w,h,depth,color,interlace)
 bpp=4 if color==6 else 3;stride=w*bpp;raw=zlib.decompress(b''.join(p for k,p in chunks if k==b'IDAT'),-15);assert len(raw)==h*(stride+1)
 prior=bytearray(stride);pixels=bytearray();pos=0
 for _ in range(h):
  method=raw[pos];row=bytearray(raw[pos+1:pos+1+stride]);pos+=stride+1
  assert method<=4
  for x in range(stride):
   left=row[x-bpp] if x>=bpp else 0;up=prior[x];corner=prior[x-bpp] if x>=bpp else 0
   if method==1:predict=left
   elif method==2:predict=up
   elif method==3:predict=(left+up)//2
   elif method==4:
    p=left+up-corner;dist=(abs(p-left),abs(p-up),abs(p-corner));predict=(left,up,corner)[dist.index(min(dist))]
   else:predict=0
   row[x]=(row[x]+predict)&255
  for x in range(0,stride,bpp):
   b,g,r=row[x:x+3];alpha=row[x+3] if bpp==4 else 255
   if alpha: pixels.extend((min(255,(r*255+alpha//2)//alpha),min(255,(g*255+alpha//2)//alpha),min(255,(b*255+alpha//2)//alpha),alpha))
   else:pixels.extend((0,0,0,0))
  prior=row
 return Image.frombytes('RGBA',(w,h),bytes(pixels))
def main():
 manifest={}
 with ZipFile(SOURCE) as archive:
  for target,source in MAP.items():
   for suffix in ['', '@2x']:
    name='Payload/vkclient.app/'+source+suffix+'.png';data=archive.read(name);image=decode(data)
    if target=='ProfilePanel':
     edge=128 if suffix else 64;image=image.crop((0,0,edge,edge))
    output=ROOT/'OpenVK'/(target+suffix+'.png');image.save(output,optimize=True)
    manifest[output.name]={'source':name,'source_sha256':hashlib.sha256(data).hexdigest(),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'size':image.size}
    if target=='ProfilePanel':manifest[output.name]['crop']=[0,0,edge,edge]
 (ROOT/'tools/vk-ipa-assets.json').write_text(json.dumps({'ipa_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'files':manifest},indent=2)+'\n')
 print('Imported',len(manifest),'legacy GUI assets; no logo, app icon or launch image imported.')
if __name__=='__main__':main()
