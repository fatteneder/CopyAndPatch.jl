#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int prev_ip)
{
    PATCH_VALUE(int,             ip,   _JIT_IP);
    PATCH_VALUE(jl_value_t ***,  args, _JIT_ARGS);
    PATCH_VALUE(jl_value_t **,   ret,  _JIT_RET);
    PATCH_VALUE(jl_function_t *, fn, _JIT_FN);
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
    jl_value_t **argv;
    JL_GC_PUSHARGS(argv, nargs.val - 1);
    for (size_t i = 1; i < nargs.val; i++)
        argv[i-1] = *(args[i]);
    *ret = jl_call(fn, argv, nargs.val);
    JL_GC_POP();
    PATCH_JUMP(_JIT_CONT, ip);
}
