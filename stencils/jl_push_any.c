#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(jl_value_t *, p, _JIT_P);
   DEBUGSTMT("jl_push_any", F, ip);
   F->tmps[i-1] = p;
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
