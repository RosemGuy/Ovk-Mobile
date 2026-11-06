#include "OVKMessagesLayout.h"
#include <math.h>
OVKMessagesLayout OVKMessagesColumns(float width) {
    OVKMessagesLayout result={0};if(!isfinite(width)||width<480)return result;
    result.listWidth=fminf(280,fmaxf(230,floorf(width*.36f)));
    result.chatX=result.listWidth+1;result.chatWidth=width-result.chatX;return result;
}
