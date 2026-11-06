#include "OVKMusicLayout.h"
#include <assert.h>
#include <stdio.h>
static void inside(struct OVKMusicRect r,float w,float h) { assert(r.x>=0&&r.y>=0&&r.width>=0&&r.height>=0&&r.x+r.width<=w+.1&&r.y+r.height<=h+.1); }
static int overlap(struct OVKMusicRect a,struct OVKMusicRect b) { return a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<b.y+b.height&&b.y<a.y+a.height; }
int main(void) {
 float sizes[][2]={{320,416},{320,504},{375,600},{528,916},{784,660},{768,960},{1024,704}};
 for (unsigned i=0;i<sizeof(sizes)/sizeof(sizes[0]);i++) for (int tab=0;tab<2;tab++) for (int mode=0;mode<2;mode++) {
  float w=sizes[i][0],h=sizes[i][1];OVKMusicLayout l=OVKMusicPlayerLayout(w,h,tab,mode);
  inside(l.timeline,w,h);inside(l.transport,w,h);if(l.showCover)inside(l.cover,w,h);if(l.showQueue)inside(l.queue,w,h);
  if(l.showCover&&l.showQueue)assert(!overlap(l.cover,l.queue));
  assert(!overlap(l.timeline,l.transport));if(l.showCover){assert(!overlap(l.cover,l.timeline));assert(!overlap(l.cover,l.transport));}
  if(l.showQueue){assert(!overlap(l.queue,l.timeline));assert(!overlap(l.queue,l.transport));}
 }
 assert(OVKMusicNextPosition(3,2,1,0,1)==-1);assert(OVKMusicNextPosition(3,2,1,1,1)==0);
 assert(OVKMusicNextPosition(3,1,1,2,1)==1);assert(OVKMusicNextPosition(3,1,1,2,0)==2);
 assert(OVKMusicNextPosition(1,0,1,1,1)==0);assert(OVKMusicNextPosition(0,0,1,0,1)==-1);
 assert(OVKMusicNextPosition(3,0,-1,1,0)==2);assert(OVKMusicNextPosition(3,0,-1,0,0)==-1);
 puts("PASS: phone/tablet player bounds, cover/queue modes, repeat and navigation boundaries");return 0;
}
