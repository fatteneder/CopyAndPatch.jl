
#include "common.h"

int16_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    int16_t val = jl_unbox_int16(_val);
    return val;
}

