#include "common.h"


void
_JIT_ENTRY()
{
    PATCH_VALUE(uint64_t, _fn, _JIT_FUNC);
    void (*fn)() = (void(*)())_fn;
    printf("Calling fn from mwe_fnptr.c ...\n");
    fn();
}
