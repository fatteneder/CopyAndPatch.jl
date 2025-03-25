#include "common.h"

JIT_ENTRY()
{
   PATCH_VALUE(int, ip, _JIT_IP);
   PATCH_VALUE(int, i, _JIT_I); // 1-based
   PATCH_VALUE(int16_t , x, _JIT_X);
   DEBUGSTMT("jl_box_int16", F, ip);
   F->tmps[i-1] = jl_box_int16(x);
   PATCH_JUMP(_JIT_CONT, F, ip);
}
