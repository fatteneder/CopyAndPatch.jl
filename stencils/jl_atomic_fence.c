#include "common.h"
#include <julia_internal.h>
#include <julia_threads.h>

void
_JIT_ENTRY(int prev_ip)
{
DEBUGSTMT("jl_atomic_fence", prev_ip);
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
JL_GC_PUSH1(*a1);
*ret = jl_atomic_fence(*a1);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}
