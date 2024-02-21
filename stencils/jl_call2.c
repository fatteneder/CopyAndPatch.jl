#include <stdio.h>
#include "common.h"

int
_JIT_ENTRY()
{
    // TODO This function needs to access .data when we use jl_box_float64 instead of jl_box_int32
    PATCH_VALUE(jl_function_t *, func, _JIT_FUNC);
    PATCH_VALUE(double, _arg1, _JIT_ARG1);
    PATCH_VALUE(double, _arg2, _JIT_ARG2);
    jl_value_t *arg1 = jl_box_float64(_arg1);
    jl_value_t *arg2 = jl_box_float64(_arg2);
    jl_value_t *ret = jl_call2(func, arg1, arg2);
    double _ret = jl_unbox_float64(ret);
    return _ret;
}
