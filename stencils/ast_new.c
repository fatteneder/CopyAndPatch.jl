#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,      ip,    _JIT_IP); // 1-based
   PATCH_VALUE(uint32_t, nargs, _JIT_NARGS);
   DEBUGSTMT("ast_new", F, ip);
   jl_value_t **argv = F->tmps;
   F->ssas[ip-1] = jl_new_structv((jl_datatype_t *)argv[0], &argv[1], nargs-1);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
