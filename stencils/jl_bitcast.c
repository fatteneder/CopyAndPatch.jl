#include "common.h"
#include "julia_internal.h" // for jl_bitcast

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_bitcast", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   F->ssas[ip-1] = jl_bitcast(a1,a2);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
