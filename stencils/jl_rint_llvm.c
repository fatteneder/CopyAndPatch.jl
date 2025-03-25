#include "common.h"
#include "julia_internal.h" // for jl_rint_llvm

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("jl_rint_llvm", F, ip);
   jl_value_t *a1 = F->tmps[0];
   F->ssas[ip] = jl_rint_llvm(a1);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
