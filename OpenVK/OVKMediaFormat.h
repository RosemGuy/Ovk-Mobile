#ifndef OVK_MEDIA_FORMAT_H
#define OVK_MEDIA_FORMAT_H
#include <stddef.h>
/* Detect container from bytes, never from a URL suffix. NULL means unknown. */
const char *OVKMediaContainer(const unsigned char *bytes,size_t length);
#endif
