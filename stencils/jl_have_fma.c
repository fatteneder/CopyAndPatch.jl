#include "common.h"
#include "julia_internal.h" // for jl_have_fma

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_have_fma", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip-1] = jl_have_fma(a1);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
