#include "OVKMediaFormat.h"
#include <string.h>
const char *OVKMediaContainer(const unsigned char *b,size_t n) {
    if (!b) return NULL;
    if (n>=12 && !memcmp(b,"RIFF",4) && !memcmp(b+8,"WAVE",4)) return "wav";
    if (n>=12 && !memcmp(b,"FORM",4) && (!memcmp(b+8,"AIFF",4) || !memcmp(b+8,"AIFC",4))) return "aiff";
    if (n>=4 && !memcmp(b,"caff",4)) return "caf";
    if (n>=8 && (!memcmp(b+4,"ftyp",4) || !memcmp(b+4,"moov",4) || !memcmp(b+4,"mdat",4) || !memcmp(b+4,"wide",4))) return "mp4";
    if (n>=4 && !memcmp(b,"OggS",4)) return "ogg";
    if (n>=4 && !memcmp(b,"fLaC",4)) return "flac";
    if (n>=4 && b[0]==0x1a && b[1]==0x45 && b[2]==0xdf && b[3]==0xa3) return "webm";
    if (n>=3 && !memcmp(b,"ID3",3)) return "mp3";
    if (n>=4 && b[0]==0xff && (b[1]&0xf6)==0xf0 && ((b[2]>>2)&15)!=15) return "aac";
    if (n>=4 && b[0]==0xff && (b[1]&0xe0)==0xe0 && (b[1]&0x18)!=8 && (b[1]&6)!=0 && (b[2]&0xf0)!=0xf0 && (b[2]&0xf0)!=0 && (b[2]&12)!=12) return "mp3";
    return NULL;
}
