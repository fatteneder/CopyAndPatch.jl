#include "common.h"
#include "julia_internal.h" // for jl_abs_float

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_abs_float", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip-1] = jl_abs_float(a1);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
