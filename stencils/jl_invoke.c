#include "common.h"

typedef union {
   uint64_t addr;
   uint32_t val;
} convert_val;

typedef union {
   uint64_t addr;
   void (*fnptr)(void **);
} convert_cont;

void
_JIT_ENTRY(void **stack_ptr)
{
    PATCH_VALUE(jl_method_instance_t *, mi, _JIT_MI);
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_val, nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(jl_value_t *, fn, _JIT_FN);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    PATCH_VALUE_AND_CONVERT(uint64_t, convert_cont, cont, _JIT_CONT);
    *ret = jl_invoke(fn, args, nargs.val, mi);
    cont.fnptr(stack_ptr);
}