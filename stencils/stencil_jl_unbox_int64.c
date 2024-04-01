
#include "common.h"

int64_t
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    int64_t val = jl_unbox_int64(_val);
    return val;
}

