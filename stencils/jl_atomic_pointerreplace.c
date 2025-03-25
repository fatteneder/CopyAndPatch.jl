#include "common.h"
#include "julia_internal.h" // for jl_atomic_pointerreplace

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("jl_atomic_pointerreplace", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   jl_value_t *a3 = F->tmps[2];
   jl_value_t *a4 = F->tmps[3];
   jl_value_t *a5 = F->tmps[4];
   F->ssas[ip-1] = jl_atomic_pointerreplace(a1,a2,a3,a4,a5);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
