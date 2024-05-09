#include <stdio.h>
#include "common.h"

double
_JIT_ENTRY()
{
    PATCH_VALUE(jl_function_t *, func, _JIT_FUNC);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(int, nargs, _JIT_NARGS);
    jl_value_t *ret = jl_call(func, args, nargs);
    double _ret = jl_unbox_float64(ret);
    return _ret;
}
