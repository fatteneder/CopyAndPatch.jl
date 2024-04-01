
#include "common.h"

int8_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    int8_t val = jl_unbox_bool(_val);
    return val;
}

