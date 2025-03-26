#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("ast_the_exception", F, ip);
   F->ssas[ip-1] = jl_current_exception(jl_current_task);
   SET_IP(F, ip);
   PATCH_JUMP(_JIT_CONT, F);
}
