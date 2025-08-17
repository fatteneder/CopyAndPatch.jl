#include <stdio.h>
#include "common.h"

void
_JIT_ENTRY(void **stack_ptr)
{
    void (*continuation)(void **) = (stack_ptr--)[0];
    int nargs                     = (int)(uint64_t)(stack_ptr--)[0];
    jl_value_t **args             = (jl_value_t**)(uint64_t)(stack_ptr--)[0];
    jl_function_t *fn             = (jl_function_t*)(uint64_t)(stack_ptr--)[0];
    jl_value_t *ret = jl_call(fn, args, nargs);
    (++stack_ptr)[0] = ret;
    /** printf("SERS OIDA\n"); */
    /** printf("void (*continuation)(void **) = %p\n", continuation); */
    /** printf("int nargs = %d\n", nargs); */
    /** printf("jl_value_t **args = %p\n", args); */
    /** printf("jl_function_t *fn = %p\n", fn); */
    continuation(stack_ptr);
}
