#ifndef OVK_FEED_LAYOUT_H
#define OVK_FEED_LAYOUT_H
typedef struct { float x,y,width,height; } OVKPhotoRect;
unsigned OVKFeedPhotoLayout(unsigned count,float width,float height,OVKPhotoRect rects[3]);
#endif
