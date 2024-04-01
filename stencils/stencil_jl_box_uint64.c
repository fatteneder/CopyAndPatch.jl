
#include "common.h"

jl_value_t *
_JIT_ENTRY() {
    PATCH_VALUE(uint64_t, _val, _JIT_ARG);
    jl_value_t *val = jl_box_uint64(_val);
    return val;
}

