#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(void **stack_ptr)
{
jl_value_t *a1 = (jl_value_t *)(stack_ptr--)[0];
jl_value_t **ret = (jl_value_t **)(stack_ptr--)[0];
*ret = jl_ctlz_int(a1);
void (*continuation)(void **) = (stack_ptr--)[0];
continuation(stack_ptr);
}
