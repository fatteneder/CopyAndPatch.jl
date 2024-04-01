
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr) {
    jl_value_t *val = (jl_value_t *)(stack_ptr--)[0];
    float *ret = (float *)(stack_ptr--)[0];
    void (*continuation)(void **) = (stack_ptr--)[0];
    *ret = jl_unbox_float32(val);
    continuation(stack_ptr);
}

