
#include "common.h"

jl_value_t *
_JIT_ENTRY() {
    PATCH_VALUE(void *, _val, _JIT_ARG);
    jl_value_t *val = jl_box_voidpointer(_val);
    return val;
}

