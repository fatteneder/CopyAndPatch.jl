#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(uint8_t *, p, _JIT_P);
   DEBUGSTMT("jl_box_and_push_uint8pointer", F, ip);
   F->tmps[i-1] = jl_box_uint8pointer(p);
   // push operations don't increment ip
   PATCH_JUMP(_JIT_CONT, F);
}
