#include "OVKFeedLayout.h"
#include <math.h>
unsigned OVKFeedPhotoLayout(unsigned count,float width,float height,OVKPhotoRect out[3]) {
    if (!out || !count || !isfinite(width) || !isfinite(height) || width<=6 || height<=6) return 0;
    out[0]=(OVKPhotoRect){0,0,width,height};
    if (count==1) return 1;
    if (count==2) { float half=(width-3)/2; out[0].width=half;out[1]=(OVKPhotoRect){half+3,0,half,height};return 2; }
    float main=floorf((width-3)*.64f),side=width-main-3,half=(height-3)/2;
    out[0].width=main;out[1]=(OVKPhotoRect){main+3,0,side,half};out[2]=(OVKPhotoRect){main+3,half+3,side,half};return 3;
}
