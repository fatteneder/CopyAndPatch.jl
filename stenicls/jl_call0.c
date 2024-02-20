#include <julia.h>
#include "common.h"

void
_JIT_ENTRY()
{
    PATCH_VALUE(jl_function_t *, func, _JIT_FUNC);
    jl_value_t *ret = jl_call0(func);
    return;
}
