#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY(prev_ip)
{
PATCH_VALUE(int, ip, _JIT_IP);
PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
PATCH_VALUE(jl_value_t **, ret, _JIT_RET);
DEBUGSTMT("jl_bswap_int", prev_ip, ip);
JL_GC_PUSH1(a1);
*ret = jl_bswap_int(*a1);
JL_GC_POP();
PATCH_JUMP(_JIT_CONT, ip);
}
