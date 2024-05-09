#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

void
_JIT_ENTRY(int ip)
{
    PATCH_VALUE(jl_method_instance_t *, mi, _JIT_MI);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    jl_method_instance_t *meth = (jl_method_instance_t*)args[0];
    assert(jl_is_method_instance(meth));
    assert(nargs.val >= 2);
    jl_value_t **argv;
    JL_GC_PUSHARGS(argv, nargs.val - 1);
    for (size_t i = 1; i < nargs.val; i++)
        argv[i] = args[i];
    if (nargs.val > 2)
        *ret = jl_invoke(argv[1], &argv[2], nargs.val-2, meth);
    else
        *ret = jl_invoke(argv[1], NULL, nargs.val-2, meth);
    JL_GC_POP();
    PATCH_JUMP(_JIT_CONT, ip+1);
}
