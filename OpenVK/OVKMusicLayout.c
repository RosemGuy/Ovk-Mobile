#include "OVKMusicLayout.h"
#include <math.h>
OVKMusicLayout OVKMusicPlayerLayout(float w,float h,int tablet,int queueVisible) {
    OVKMusicLayout out={0}; if (!isfinite(w)||!isfinite(h)||w<240||h<220) return out;
    float top=84,bottom=100,available=h-top-bottom;
    out.timeline=(struct OVKMusicRect){0,0,w,top}; out.transport=(struct OVKMusicRect){0,h-bottom,w,bottom};
    if (tablet && available<200) tablet=0;
    out.showCover=tablet || !queueVisible; out.showQueue=tablet || queueVisible;
    if (!tablet) {
        float side=fminf(w,available);
        out.cover=(struct OVKMusicRect){(w-side)/2,top+(available-side)/2,side,side};
        out.queue=(struct OVKMusicRect){0,top,w,available};
    } else if (w>=640) {
        float left=floorf((w-60)*.48f),side=fminf(left,available-32);
        out.cover=(struct OVKMusicRect){20+(left-side)/2,top+(available-side)/2,side,side};
        out.queue=(struct OVKMusicRect){left+40,top+16,w-left-60,available-32};
    } else {
        float side=fminf(320,fminf(w-40,available*.46f));
        out.cover=(struct OVKMusicRect){(w-side)/2,top+8,side,side};
        out.queue=(struct OVKMusicRect){20,top+side+24,w-40,available-side-32};
    }
    return out;
}

long OVKMusicNextPosition(long count,long position,int direction,int repeatMode,int automatic) {
    if (count<=0 || position<0 || position>=count || direction==0) return -1;
    if (automatic && repeatMode==2) return position;
    long next=position+(direction<0 ? -1 : 1);
    if (next<0 || next>=count) { if (repeatMode!=1) return -1; next=next<0 ? count-1 : 0; }
    return next;
}
