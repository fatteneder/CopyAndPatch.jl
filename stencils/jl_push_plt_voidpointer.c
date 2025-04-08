#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int,    ip, _JIT_IP);
   PATCH_VALUE(int,    i,  _JIT_I); // 1-based
   PATCH_VALUE(void *, p,  _JIT_P);
   DEBUGSTMT("jl_push_plt_voidpointer", F, ip);
   // TODO cache result
   F->tmps[i-1] = (jl_value_t *)p;
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
