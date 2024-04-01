
#include "common.h"

double
_JIT_ENTRY() {
    PATCH_VALUE(jl_value_t *, _val, _JIT_ARG);
    double val = jl_unbox_float64(_val);
    return val;
}

