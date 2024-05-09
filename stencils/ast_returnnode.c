#include <stdio.h>
#include "common.h"

jl_value_t *
_JIT_ENTRY(int ip) {
    PATCH_VALUE(jl_value_t *, ret, _JIT_RET);
    return ret;
}
