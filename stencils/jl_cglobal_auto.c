#include <inttypes.h>
#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(void **stack_ptr)
{
jl_value_t *a1 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *ret = jl_cglobal_auto(a1);
// TODO push result onto stack!
void (*continuation)(void **) = (stack_ptr--)[0];
continuation(stack_ptr);
}
    
