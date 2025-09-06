#include <stdio.h>
#include <stdlib.h>
#include "yuv.h"

void freeYUVDef(YUVDef *yuv) {
    if (!yuv) return;
    free(yuv->y);
    free(yuv->u);
    free(yuv->v);
    free(yuv);
}