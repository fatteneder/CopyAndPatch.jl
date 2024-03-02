#include <stdio.h>
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr)
{
    int nargs         = (int)(uint64_t)(stack_ptr--)[0];
    jl_value_t **args = (jl_value_t**)(uint64_t)(stack_ptr--)[0];
    jl_function_t *fn = (jl_function_t*)(uint64_t)(stack_ptr--)[0];
    void (*continuation)(void **) = (stack_ptr--)[0];
    jl_value_t *ret   = jl_call(fn, args, nargs);
    continuation(stack_ptr);
}
