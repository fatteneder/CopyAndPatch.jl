
#include "common.h"

uint32_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    uint32_t val = jl_unbox_uint32(_val);
    return val;
}

