#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP); // 1-based
   DEBUGSTMT("ast_gc_perserve_end", F, ip);
   F->ssas[ip-1] = jl_nothing;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
