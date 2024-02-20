#include "common.h"

void
_JIT_ENTRY()
{
    PATCH_VALUE(jl_function_t *, func, _JIT_FUNC);
    PATCH_VALUE(jl_value_t *, arg1, _JIT_ARG1);
    jl_value_t *ret = jl_call1(func, arg1);
    return;
}
