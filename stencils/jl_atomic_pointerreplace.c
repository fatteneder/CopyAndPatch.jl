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
PATCH_VALUE(jl_value_t **, a5, _JIT_A5);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
DEBUGSTMT("jl_atomic_pointerreplace", prev_ip, ip);
JL_GC_PUSH5(a1,a2,a3,a4,a5);
*ret = jl_atomic_pointerreplace(*a1,*a2,*a3,*a4,*a5);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}
