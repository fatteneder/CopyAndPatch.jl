#include <stdio.h>
#include "common.h"

double
_JIT_ENTRY()
{
    PATCH_VALUE(jl_function_t *, func, _JIT_FUNC);
    PATCH_VALUE_AND_CAST(uint64_t, double, _arg1, _JIT_ARG1);
    PATCH_VALUE_AND_CAST(uint64_t, double, _arg2, _JIT_ARG2);
    jl_value_t *arg1 = jl_box_float64(_arg1);
    jl_value_t *arg2 = jl_box_float64(_arg2);
    jl_value_t *ret = jl_call2(func, arg1, arg2);
    double _ret = jl_unbox_float64(ret);
    printf("arg1, arg2, ret = %e, %e, %e\n", _arg1, _arg2, _ret);
    return _ret;
}
