#include "common.h"
#include "julia_internal.h" // for jl_cglobal_auto

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_cglobal_auto", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip-1] = jl_cglobal_auto(a1);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
