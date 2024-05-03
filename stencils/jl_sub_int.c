#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

typedef union {
   uint64_t addr;
   void (*fnptr)(void **);
} convert_cont;

void
_JIT_ENTRY(void **stack_ptr)
{
PATCH_VALUE(jl_value_t *, a1, _JIT_A1);
PATCH_VALUE(jl_value_t *, a2, _JIT_A2);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
PATCH_VALUE_AND_CONVERT(uint64_t, convert_cont, cont, _JIT_CONT);
*ret = jl_sub_int(a1,a2);
cont.fnptr(stack_ptr);
}
