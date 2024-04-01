#include "common.h"

typedef union {
   void *ptr;
   uint32_t val;
} ptrval;

void
_JIT_ENTRY(void **stack_ptr)
{
    jl_method_instance_t *mi = (jl_method_instance_t *)(stack_ptr--)[0];
    ptrval nargs = (ptrval)(stack_ptr--)[0];
    jl_value_t **args = (jl_value_t **)(stack_ptr--)[0];
    jl_value_t *F = (jl_value_t *)(stack_ptr--)[0];
    jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
    *ret = jl_invoke(F, args, nargs.val, mi);
    void (*continuation)(void **) = (stack_ptr--)[0];
    continuation(stack_ptr);
}
