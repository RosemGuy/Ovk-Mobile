#include "OVKFeedLayout.h"
#include <stdio.h>
#include <stdlib.h>
static void check(int condition) { if (!condition) { fputs("FAIL: feed photo geometry\n",stderr);exit(1); } }
int main(void) {
 const float widths[]={320,375,414,768,1024};const float heights[]={120,198.5,280};OVKPhotoRect r[3];
 check(OVKFeedPhotoLayout(0,320,200,r)==0);check(OVKFeedPhotoLayout(3,0,200,r)==0);
 for (unsigned w=0;w<5;w++) for(unsigned h=0;h<3;h++) for(unsigned count=1;count<10;count++) {
  unsigned n=OVKFeedPhotoLayout(count,widths[w],heights[h],r);check(n==(count<3 ? count : 3));
  for(unsigned i=0;i<n;i++) { check(r[i].x>=0 && r[i].y>=0 && r[i].width>0 && r[i].height>0);check(r[i].x+r[i].width<=widths[w]+.01 && r[i].y+r[i].height<=heights[h]+.01);
   for(unsigned j=0;j<i;j++) check(r[i].x>=r[j].x+r[j].width || r[j].x>=r[i].x+r[i].width || r[i].y>=r[j].y+r[j].height || r[j].y>=r[i].y+r[i].height);
  }
 }
 puts("PASS: collage bounds/non-overlap, 1-9 photos, phone/tablet widths");return 0;
}
