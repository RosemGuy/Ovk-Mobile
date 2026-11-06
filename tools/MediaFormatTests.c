#include "OVKMediaFormat.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void check(const unsigned char *b,size_t n,const char *expected) {
 const char *actual=OVKMediaContainer(b,n);
 if ((!actual)!=(!expected) || (actual && strcmp(actual,expected))) { fprintf(stderr,"Wrong container\n"); exit(1); }
}
int main(int argc,char **argv) {
 check((const unsigned char *)"ID3",3,"mp3");
 check((const unsigned char *)"\xff\xfb\x90\x00",4,"mp3");
 check((const unsigned char *)"\xff\xf1\x50\x80",4,"aac");
 check((const unsigned char *)"RIFFxxxxWAVE",12,"wav");
 check((const unsigned char *)"xxxxftypM4A ",12,"mp4");
 check((const unsigned char *)"OggS",4,"ogg");
 check((const unsigned char *)"<html>",6,NULL);check(NULL,0,NULL);
 check((const unsigned char *)"\xff",1,NULL);
 if (argc==3) { unsigned char bytes[64]; FILE *f=fopen(argv[1],"rb");if (!f) return 2;size_t n=fread(bytes,1,sizeof(bytes),f);fclose(f);check(bytes,n,argv[2]); }
 puts("PASS: container detection (MP3, ADTS AAC, MP4, WAV, Ogg, invalid/truncated)"); return 0;
}
