#include "OVKMessagesLayout.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    const float widths[]={480,696,704,952,960};
    for(unsigned i=0;i<sizeof(widths)/sizeof(widths[0]);i++) {
        OVKMessagesLayout l=OVKMessagesColumns(widths[i]);
        assert(l.listWidth>=230 && l.listWidth<=280);
        assert(l.chatX==l.listWidth+1 && l.chatWidth>=249);
        assert(fabsf(l.chatX+l.chatWidth-widths[i])<.01);
    }
    assert(OVKMessagesColumns(NAN).listWidth==0);
    assert(OVKMessagesColumns(320).listWidth==0);
    puts("PASS: iPad messages columns, separator and available chat width");
}
