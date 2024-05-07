#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(int ip)
{
PATCH_VALUE(jl_value_t *, a1, _JIT_A1);
PATCH_VALUE(jl_value_t *, a2, _JIT_A2);
PATCH_VALUE(jl_value_t *, a3, _JIT_A3);
PATCH_VALUE(jl_value_t *, a4, _JIT_A4);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
JL_GC_PUSH4(a1,a2,a3,a4);
*ret = jl_atomic_pointermodify(a1,a2,a3,a4);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip+1);
}
