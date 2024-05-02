#include "common.h"

typedef union {
   uint64_t ptr;
   uint32_t val;
} ptrval;

void
_JIT_ENTRY(void **stack_ptr)
{
    PATCH_VALUE(jl_method_instance_t *, mi, _JIT_MI);
    PATCH_VALUE_AND_CAST(uint64_t, ptrval, _nargs, _JIT_NARGS);
    PATCH_VALUE(jl_value_t **, args, _JIT_ARGS);
    PATCH_VALUE(jl_value_t *, F, _JIT_F);
    PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
    *ret = jl_invoke(F, args, _nargs.val, mi);
    void (*continuation)(void **) = (stack_ptr--)[0];
    continuation(stack_ptr);
}
