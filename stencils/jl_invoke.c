#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} rawval;

typedef union {
   uint64_t addr;
   void (*fnptr)(void **);
} rawcont;

void
_JIT_ENTRY(void **stack_ptr)
{
    PATCH_VALUE(jl_method_instance_t *, mi, _JIT_MI);
    PATCH_VALUE_AND_CAST(uint64_t, rawval, nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(jl_value_t *, F, _JIT_F);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    *ret = jl_invoke(F, args, nargs.val, mi);
    PATCH_VALUE_AND_CAST(uint64_t, rawcont, cont, _JIT_CONT);
    cont.fnptr(stack_ptr);
}
