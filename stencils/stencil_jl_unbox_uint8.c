
#include "common.h"

uint8_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    uint8_t val = jl_unbox_uint8(_val);
    return val;
}

