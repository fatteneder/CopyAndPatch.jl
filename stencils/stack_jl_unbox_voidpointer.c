
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr) {
    jl_value_t *val = (jl_value_t *)(stack_ptr--)[0];
    void * *ret = (void * *)(stack_ptr--)[0];
    void (*continuation)(void **) = (stack_ptr--)[0];
    *ret = jl_unbox_voidpointer(val);
    continuation(stack_ptr);
}

