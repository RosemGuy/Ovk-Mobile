#include "OVKAudioDuration.h"
#include <string.h>
static unsigned be32(const unsigned char *p) { return ((unsigned)p[0]<<24)|((unsigned)p[1]<<16)|((unsigned)p[2]<<8)|p[3]; }
double OVKMP3Duration(const unsigned char *b,size_t n) {
    if (!b || n<4) return 0;
    size_t pos=0,frames=0; double seconds=0; unsigned firstRate=0;
    if (n>=10 && !memcmp(b,"ID3",3)) {
        if ((b[6]|b[7]|b[8]|b[9])&128) return 0;
        size_t size=((size_t)b[6]<<21)|((size_t)b[7]<<14)|((size_t)b[8]<<7)|b[9];
        if (size>n-10) return 0;
        pos=size+10; if (b[3]==4 && (b[5]&16)) { if(n-pos<10)return 0; pos+=10; }
    }
    while (pos<n) {
        size_t remain=n-pos;
        if (remain==128 && !memcmp(b+pos,"TAG",3)) break;
        if (remain>=32 && !memcmp(b+pos,"APETAGEX",8)) break;
        if (remain<4) return 0;
        unsigned h=be32(b+pos),version=(h>>19)&3,layer=(h>>17)&3,bi=(h>>12)&15,si=(h>>10)&3;
        if ((h&0xffe00000)!=0xffe00000 || version==1 || layer!=1 || !bi || bi==15 || si==3) return 0;
        static const unsigned rates[3]={44100,48000,32000};
        static const unsigned mpeg1[16]={0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
        static const unsigned mpeg2[16]={0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};
        unsigned rate=rates[si]/(version==3 ? 1 : version==2 ? 2 : 4);
        unsigned bitrate=version==3 ? mpeg1[bi] : mpeg2[bi];
        size_t size=(version==3 ? 144000 : 72000)*bitrate/rate+((h>>9)&1);
        if (size<4 || size>remain || (firstRate && firstRate!=rate)) return 0;
        if (!firstRate) firstRate=rate;
        int metadata=0;
        if (!frames) {
            unsigned side=version==3 ? (((h>>6)&3)==3 ? 17 : 32) : (((h>>6)&3)==3 ? 9 : 17);
            size_t offset=4+((h&0x10000) ? 0 : 2)+side;
            if (offset+8<=size && (!memcmp(b+pos+offset,"Xing",4) || !memcmp(b+pos+offset,"Info",4))) metadata=1;
            if (size>=40 && !memcmp(b+pos+36,"VBRI",4)) metadata=1;
        }
        if (!metadata) seconds+=(version==3 ? 1152.0 : 576.0)/rate;
        frames++; pos+=size;
    }
    return frames>=2 ? seconds : 0;
}
