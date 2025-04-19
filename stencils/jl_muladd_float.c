#include "common.h"
#include "julia_internal.h" // for jl_muladd_float

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_muladd_float", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   jl_value_t *a3 = F->tmps[2];
   F->ssas[ip-1] = jl_muladd_float(a1,a2,a3);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}

int isIntrinsicFunction = 1;
