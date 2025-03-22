#include "common.h"

JIT_ENTRY()
{

   PATCH_VALUE(int, ip, _JIT_IP);
   DEBUGSTMT("ast_gc_preserve_begin", F, ip);
   F->ssas[ip] = jl_nothing;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
