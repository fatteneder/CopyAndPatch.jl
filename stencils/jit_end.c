#include <stdio.h>
#include "common.h"

void
_JIT_ENTRY(int ip) {
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    printf("WE ARE DONE!!!\n");
}
