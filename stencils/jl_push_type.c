#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(jl_value_t **, ty, _JIT_TY);
   DEBUGSTMT("jl_push_type", F, ip);
   F->tmps[i-1] = *ty;
   PATCH_JUMP(_JIT_CONT, F, ip);
}
