#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("ast_the_exception", F, ip);
   F->ssas[ip] = jl_current_exception(jl_current_task);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
