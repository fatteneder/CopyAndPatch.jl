
#include "common.h"

int32_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    int32_t val = jl_unbox_int32(_val);
    return val;
}

