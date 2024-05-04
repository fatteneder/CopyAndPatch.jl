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
    PATCH_JUMP(_JIT_CONT, ip+1);
}
