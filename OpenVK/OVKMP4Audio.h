#ifndef OVK_MP4_AUDIO_H
#define OVK_MP4_AUDIO_H
#include <stddef.h>
typedef struct { int valid; unsigned audioTracks; unsigned codecCount; char codecs[4][5]; } OVKMP4AudioInfo;
/* Inspect MP4 metadata independently of the platform's codec support. */
OVKMP4AudioInfo OVKInspectMP4Audio(const unsigned char *bytes, size_t size);
#endif
