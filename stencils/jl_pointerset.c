#include "common.h"
#include "julia_internal.h" // for jl_pointerset

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_pointerset", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   jl_value_t *a3 = F->tmps[2];
   jl_value_t *a4 = F->tmps[3];
   F->ssas[ip-1] = jl_pointerset(a1,a2,a3,a4);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
