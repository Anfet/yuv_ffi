#include <stdio.h>
#include "yuv420.h"

void freeYUV420Def(YUV420Def *yuv) {
    if (!yuv) return;
    free(yuv->y);
    free(yuv->u);
    free(yuv->v);
    free(yuv);
}