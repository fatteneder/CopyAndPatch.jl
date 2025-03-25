#include "common.h"
#include "julia_internal.h" // for jl_atomic_fence

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("jl_atomic_fence", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip] = jl_atomic_fence(a1);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
