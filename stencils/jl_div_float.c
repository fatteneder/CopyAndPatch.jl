#include "common.h"
#include "julia_internal.h" // for jl_div_float

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("jl_div_float", F, ip);
   jl_value_t *a1 = F->tmps[0];
   jl_value_t *a2 = F->tmps[1];
   F->ssas[ip] = jl_div_float(a1,a2);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
