#include <inttypes.h>
#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(void **stack_ptr)
{
jl_value_t *a1 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *a2 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *a3 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *a4 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *a5 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t *ret = jl_atomic_pointerreplace(a1,a2,a3,a4,a5);
// TODO push result onto stack!
void (*continuation)(void **) = (stack_ptr--)[0];
continuation(stack_ptr);
}
    
