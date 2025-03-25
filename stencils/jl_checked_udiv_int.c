#include "common.h"
#include "julia_internal.h" // for jl_checked_udiv_int

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("jl_checked_udiv_int", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   F->ssas[ip] = jl_checked_udiv_int(a1,a2);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
