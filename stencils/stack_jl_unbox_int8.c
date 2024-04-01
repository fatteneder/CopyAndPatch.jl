
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr) {
    jl_value_t *val = (jl_value_t *)(stack_ptr--)[0];
    int8_t *ret = (int8_t *)(stack_ptr--)[0];
    void (*continuation)(void **) = (stack_ptr--)[0];
    *ret = jl_unbox_int8(val);
    continuation(stack_ptr);
}

