#include "OVKMP4Audio.h"
#include <stdint.h>
#include <string.h>
#include <stdio.h>
typedef struct {
    int sound; unsigned codecCount; char codecs[4][5];
    unsigned objectType, audioObjectType, frequencyIndex, channels;
    size_t stsc, stsz, offsets; unsigned chunks, mappings, samples, fixedSize, offsetWidth;
} Track;
typedef struct { const unsigned char *bytes; unsigned boxes; OVKMP4AudioInfo info; Track audio; } Reader;
static uint32_t u32(const unsigned char *p) { return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3]; }
static void descriptors(Reader *r, Track *track, size_t start, size_t end, unsigned depth) {
    if (depth>4) return;
    while (start<end) {
        unsigned tag=r->bytes[start++], length=0, count=0, byte;
        do { if (start>=end || ++count>4) return; byte=r->bytes[start++]; length=(length<<7)|(byte&127); } while (byte&128);
        if (length>end-start) return;
        size_t next=start+length, child=start;
        if (tag==3) {
            if (next-child<3) return;
            unsigned flags=r->bytes[child+2]; child+=3;
            if (flags&128) child+=2;
            if (flags&64) { if (child>=next) return; unsigned n=r->bytes[child++]; child+=n; }
            if (flags&32) child+=2;
            if (child<=next) descriptors(r,track,child,next,depth+1);
        } else if (tag==4) {
            if (length<13) return;
            track->objectType=r->bytes[start]; descriptors(r,track,start+13,next,depth+1);
        } else if (tag==5 && length>=2) {
            track->audioObjectType=r->bytes[start]>>3;
            track->frequencyIndex=((r->bytes[start]&7)<<1)|(r->bytes[start+1]>>7);
            track->channels=(r->bytes[start+1]>>3)&15;
        }
        start=next;
    }
}
static void sampleChildren(Reader *r, Track *track, size_t start, size_t end, unsigned depth) {
    if (depth>4) return;
    while (end-start>=8) {
        uint32_t length=u32(r->bytes+start); if (length<8 || length>end-start) return;
        if (!memcmp(r->bytes+start+4,"esds",4) && length>=12) descriptors(r,track,start+12,start+length,0);
        else if (!memcmp(r->bytes+start+4,"wave",4)) sampleChildren(r,track,start+8,start+length,depth+1);
        start+=length;
    }
}
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
            if (t.sound) { if (!r->info.audioTracks) { r->audio=t; r->info.objectType=t.objectType; r->info.audioObjectType=t.audioObjectType; } r->info.audioTracks++; for (unsigned i=0;i<t.codecCount && r->info.codecCount<4;i++) memcpy(r->info.codecs[r->info.codecCount++],t.codecs[i],5); }
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
                if (size>=36) {
                    unsigned version=((unsigned)r->bytes[entry+16]<<8)|r->bytes[entry+17];
                    size_t skip=version==0 ? 36 : (version==1 ? 52 : (version==2 ? 72 : size));
                    if (skip<=size) sampleChildren(r,track,entry+skip,entry+size,0);
                }
                entry+=size;
            }
        } else if (track && !memcmp(p+4,"stsc",4)) {
            if (limit-body<8) return 0;
            track->mappings=u32(r->bytes+body+4); track->stsc=body+8;
            if (track->mappings>(limit-track->stsc)/12) return 0;
        } else if (track && !memcmp(p+4,"stsz",4)) {
            if (limit-body<12) return 0;
            track->fixedSize=u32(r->bytes+body+4); track->samples=u32(r->bytes+body+8); track->stsz=body+12;
            if (!track->fixedSize && track->samples>(limit-track->stsz)/4) return 0;
        } else if (track && (!memcmp(p+4,"stco",4) || !memcmp(p+4,"co64",4))) {
            if (limit-body<8) return 0;
            track->offsetWidth=!memcmp(p+4,"co64",4) ? 8 : 4;
            track->chunks=u32(r->bytes+body+4); track->offsets=body+8;
            if (track->chunks>(limit-track->offsets)/track->offsetWidth) return 0;
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

int OVKExtractMP4Audio(const unsigned char *bytes, size_t size, const char *path) {
    Reader r={0}; r.bytes=bytes;
    if (!bytes || !path || !walk(&r,0,size,0,NULL) || !r.info.valid) return 0;
    Track *t=&r.audio; int format=0;
    if (t->objectType==0x69 || t->objectType==0x6b || !memcmp(t->codecs[0],".mp3",4)) format=1;
    else if (t->objectType==0x40 && t->audioObjectType==2 && t->frequencyIndex<13 && t->channels>0 && t->channels<=7) format=2;
    if (!format || t->codecCount!=1 || !t->chunks || !t->mappings || !t->samples || t->samples>1000000 || u32(bytes+t->stsc)!=1) return 0;
    for (unsigned i=0;i<t->mappings;i++) {
        const unsigned char *map=bytes+t->stsc+i*12;
        if (!u32(map) || u32(map)>t->chunks || !u32(map+4) || u32(map+8)!=1 || (i && u32(map)<=u32(map-12))) return 0;
    }
    FILE *output=fopen(path,"wb"); if (!output) return 0;
    unsigned sample=0, mapping=0; int success=1;
    for (unsigned chunk=1;chunk<=t->chunks && success;chunk++) {
        while (mapping+1<t->mappings && u32(bytes+t->stsc+(mapping+1)*12)<=chunk) mapping++;
        unsigned count=u32(bytes+t->stsc+mapping*12+4);
        const unsigned char *offset=bytes+t->offsets+(size_t)(chunk-1)*t->offsetWidth;
        uint64_t position=t->offsetWidth==8 ? ((uint64_t)u32(offset)<<32)|u32(offset+4) : u32(offset);
        if (count>t->samples-sample) { success=0; break; }
        for (unsigned j=0;j<count;j++,sample++) {
            uint32_t length=t->fixedSize ? t->fixedSize : u32(bytes+t->stsz+(size_t)sample*4);
            if (!length || position>size || length>size-position) { success=0; break; }
            if (format==2) {
                if (length>8184) { success=0; break; }
                unsigned frame=length+7, index=t->frequencyIndex, channels=t->channels;
                unsigned char adts[7]={0xff,0xf1,(unsigned char)((1<<6)|(index<<2)|(channels>>2)),(unsigned char)(((channels&3)<<6)|(frame>>11)),(unsigned char)(frame>>3),(unsigned char)(((frame&7)<<5)|31),0xfc};
                if (fwrite(adts,1,7,output)!=7) { success=0; break; }
            }
            if (fwrite(bytes+(size_t)position,1,length,output)!=length) { success=0; break; }
            position+=length;
        }
    }
    if (sample!=t->samples) success=0;
    if (fclose(output)!=0) success=0;
    if (!success) { remove(path); return 0; }
    return format;
}
