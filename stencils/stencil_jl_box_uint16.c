
#include "common.h"

jl_value_t *
_JIT_ENTRY() {
    PATCH_VALUE(uint16_t, _val, _JIT_ARG);
    jl_value_t *val = jl_box_uint16(_val);
    return val;
}

