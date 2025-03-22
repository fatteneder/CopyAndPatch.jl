#include "common.h"
#include "julia_internal.h"
#include "julia_threads.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(jl_value_t **, a1, _JIT_A1);
   DEBUGSTMT("jl_ctpop_int", F, ip);
   JL_GC_PUSH1(a1);
   F->ssas[ip] = jl_ctpop_int(*a1);
   JL_GC_POP();
   PATCH_JUMP(_JIT_CONT, F, ip);
}
