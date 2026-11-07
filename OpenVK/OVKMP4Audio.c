#include "OVKMP4Audio.h"
#include <stdint.h>
#include <string.h>
typedef struct { int sound; unsigned codecCount; char codecs[4][5]; } Track;
typedef struct { const unsigned char *bytes; unsigned boxes; OVKMP4AudioInfo info; } Reader;
static uint32_t u32(const unsigned char *p) { return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3]; }
static int walk(Reader *r, size_t start, size_t end, unsigned depth, Track *track) {
    if (depth>8) return 0;
    while (start<end) {
        if (++r->boxes>8192 || end-start<8) return 0;
        const unsigned char *p=r->bytes+start; uint64_t length=u32(p); size_t header=8;
        if (length==1) { if (end-start<16) return 0; length=((uint64_t)u32(p+8)<<32)|u32(p+12); header=16; }
        if (length==0) length=end-start;
        if (length<header || length>end-start) return 0;
        size_t body=start+header, limit=start+(size_t)length;
        if (!memcmp(p+4,"trak",4)) {
            Track t={0}; if (!walk(r,body,limit,depth+1,&t)) return 0;
            if (t.sound) { r->info.audioTracks++; for (unsigned i=0;i<t.codecCount && r->info.codecCount<4;i++) memcpy(r->info.codecs[r->info.codecCount++],t.codecs[i],5); }
        } else if (!memcmp(p+4,"moov",4) || !memcmp(p+4,"mdia",4) || !memcmp(p+4,"minf",4) || !memcmp(p+4,"stbl",4)) {
            if (!memcmp(p+4,"moov",4)) r->info.valid=1;
            if (!walk(r,body,limit,depth+1,track)) return 0;
        } else if (track && !memcmp(p+4,"hdlr",4)) {
            if (limit-body<12) return 0;
            track->sound=!memcmp(r->bytes+body+8,"soun",4);
        } else if (track && !memcmp(p+4,"stsd",4)) {
            if (limit-body<8) return 0;
            unsigned count=u32(r->bytes+body+4); size_t entry=body+8;
            if (count>1024) return 0;
            for (unsigned i=0;i<count;i++) {
                if (limit-entry<8) return 0;
                uint32_t size=u32(r->bytes+entry); if (size<8 || size>limit-entry) return 0;
                if (track->codecCount<4) { char *codec=track->codecs[track->codecCount++]; memcpy(codec,r->bytes+entry+4,4); codec[4]=0; }
                entry+=size;
            }
        }
        start=limit;
    }
    return 1;
}
OVKMP4AudioInfo OVKInspectMP4Audio(const unsigned char *bytes, size_t size) {
    Reader reader={0}; reader.bytes=bytes;
    if (!bytes || !walk(&reader,0,size,0,NULL)) memset(&reader.info,0,sizeof(reader.info));
    return reader.info;
}
