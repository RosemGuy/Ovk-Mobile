#ifndef OVK_MUSIC_LAYOUT_H
#define OVK_MUSIC_LAYOUT_H
struct OVKMusicRect { float x,y,width,height; };
typedef struct {
    struct OVKMusicRect timeline,cover,queue,transport;
    int showCover,showQueue;
} OVKMusicLayout;
OVKMusicLayout OVKMusicPlayerLayout(float width,float height,int tablet,int queueVisible);
long OVKMusicNextPosition(long count,long position,int direction,int repeatMode,int automatic);
#endif
