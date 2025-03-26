#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,      ip,    _JIT_IP); // 1-based
   PATCH_VALUE(uint32_t, nargs, _JIT_NARGS);
   DEBUGSTMT("ast_call", F, ip);
   F->ssas[ip-1] = jl_apply(F->tmps, nargs);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
