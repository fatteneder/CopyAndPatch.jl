#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int ip)
{
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(jl_function_t *, fn, _JIT_FN);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    *ret = jl_call(fn, args, nargs.val);
    PATCH_JUMP(_JIT_CONT, ip+1);
}
