#include "common.h"
#include "julia_internal.h" // for jl_ctpop_int

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("jl_ctpop_int", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip] = jl_ctpop_int(a1);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
