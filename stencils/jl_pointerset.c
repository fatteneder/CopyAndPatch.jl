#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY()
{
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, a2, _JIT_A2);
PATCH_VALUE(jl_value_t **, a3, _JIT_A3);
PATCH_VALUE(jl_value_t **, a4, _JIT_A4);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
DEBUGSTMT("jl_pointerset", F, ip);
JL_GC_PUSH4(a1,a2,a3,a4);
*ret = jl_pointerset(*a1,*a2,*a3,*a4);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, F, ip);
}
