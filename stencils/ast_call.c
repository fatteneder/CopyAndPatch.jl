#include "common.h"

void
_JIT_ENTRY(int prev_ip)
{
    PATCH_VALUE(jl_value_t ***,  args,    _JIT_ARGS);
    PATCH_VALUE(jl_function_t *, fn,      _JIT_FN);
    PATCH_VALUE(int,             ip,      _JIT_IP);
    PATCH_VALUE(uint32_t,        nargs,   _JIT_NARGS);
    PATCH_VALUE(jl_value_t **,   ret,     _JIT_RET);
    PATCH_VALUE(int,             retused, _JIT_RETUSED);
    jl_value_t **argv;
    JL_GC_PUSHARGS(argv, nargs);
    for (size_t i = 0; i < nargs; i++)
        argv[i] = *(args[i]);
    jl_value_t *_ret = jl_apply(argv, nargs);
    JL_GC_POP();
    if (retused)
        *ret = _ret;
    PATCH_JUMP(_JIT_CONT, ip);
}
