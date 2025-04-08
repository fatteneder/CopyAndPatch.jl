#include "common.h"
#include "julia.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(jl_value_t *, q, _JIT_Q);
   DEBUGSTMT("jl_push_quotenode_value", F, ip);
   jl_value_t *v = jl_quotenode_value(q);
   F->tmps[i-1] = v;
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
