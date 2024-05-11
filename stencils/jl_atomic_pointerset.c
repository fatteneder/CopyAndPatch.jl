#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(int prev_ip)
{
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, a2, _JIT_A2);
PATCH_VALUE(jl_value_t **, a3, _JIT_A3);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
JL_GC_PUSH3(*a1,*a2,*a3);
*ret = jl_atomic_pointerset(*a1,*a2,*a3);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}
