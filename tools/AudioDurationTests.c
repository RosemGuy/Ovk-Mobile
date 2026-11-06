#include "OVKAudioDuration.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    unsigned char data[20000]={0}; size_t n=0;
    /* 10 Layer III frames, alternating 128/192 kb/s: VBR must not use file-size/first-bitrate. */
    for (int i=0;i<10;i++) { unsigned rate=i%2 ? 192 : 128; size_t size=144000*rate/44100; data[n]=255;data[n+1]=251;data[n+2]=(i%2 ? 11 : 9)<<4; n+=size; }
    double expected=10*1152.0/44100;
    assert(fabs(OVKMP3Duration(data,n)-expected)<1e-8);
    assert(OVKMP3Duration(data,n-1)==0);
    /* First frame is metadata. An intentionally false Xing count must be ignored. */
    memcpy(data+36,"Xing",4);data[43]=1;data[44]=0x7f;data[45]=0xff;data[46]=0xff;data[47]=0xff;
    assert(fabs(OVKMP3Duration(data,n)-9*1152.0/44100)<1e-8);
    unsigned char tagged[21000]={0};memcpy(tagged,"ID3\4\0\0\0\0\0\4",10);memcpy(tagged+14,data,n);memcpy(tagged+14+n,"TAG",3);
    assert(fabs(OVKMP3Duration(tagged,14+n+128)-9*1152.0/44100)<1e-8);
    assert(OVKMP3Duration(NULL,0)==0);assert(OVKMP3Duration((const unsigned char *)"garbage",7)==0);
    puts("PASS: VBR frame timing, incorrect Xing count, ID3 tags, truncation and invalid data");return 0;
}
