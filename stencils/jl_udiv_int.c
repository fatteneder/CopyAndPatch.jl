#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY()
{
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, a2, _JIT_A2);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
DEBUGSTMT("jl_udiv_int", F, ip);
JL_GC_PUSH2(a1,a2);
*ret = jl_udiv_int(*a1,*a2);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, F, ip);
}
