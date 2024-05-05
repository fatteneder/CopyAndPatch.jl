#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int ip)
{
    PATCH_VALUE(jl_method_instance_t *, mi, _JIT_MI);
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(jl_value_t *, fn, _JIT_FN);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    *ret = jl_invoke(fn, args, nargs.val, mi);
    // TODO Make this more like src/interpreter.c
    /** jl_method_instance_t *meth = (jl_method_instance_t*)fn; */
    /** assert(jl_is_method_instance(meth)); */
    /** *ret = jl_invoke(fn, &argv[2], nargs - 2, meth); */
    PATCH_JUMP(_JIT_CONT, ip+1);
}
