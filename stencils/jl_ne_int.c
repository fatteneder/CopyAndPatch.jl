#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(int prev_ip)
{
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, a2, _JIT_A2);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
JL_GC_PUSH2(*a1,*a2);
*ret = jl_ne_int(*a1,*a2);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}
